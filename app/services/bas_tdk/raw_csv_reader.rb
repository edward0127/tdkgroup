require "csv"

module BasTdk
  class RawCsvReader
    class ReadError < StandardError; end

    DELIMITERS = [ ",", "\t", ";" ].freeze
    ENCODING_CANDIDATES = [
      [ "UTF-8", "UTF-8" ],
      [ "Windows-1252", "Windows-1252" ],
      [ "ISO-8859-1", "ISO-8859-1" ]
    ].freeze
    UTF8_BOM = "\xEF\xBB\xBF".b.freeze
    SAMPLE_ROW_LIMIT = 20

    Sheet = Struct.new(:name, :cells_by_row, :column_count, keyword_init: true) do
      def last_row
        cells_by_row.keys.max.to_i
      end

      def last_column
        [ column_count.to_i, cells_by_row.values.filter_map { |row| row.keys.max }.max.to_i ].max
      end

      def cell(row_number, column_number)
        cells_by_row.dig(row_number, column_number)
      end
    end

    attr_reader :metadata

    def initialize(path)
      @path = path
      @metadata = {}
    end

    def first_sheet
      content, encoding = decoded_content
      delimiter = sniff_delimiter(content)
      rows = parse_csv(content, delimiter)

      Sheet.new(
        name: "CSV transaction table",
        cells_by_row: cells_by_row(rows),
        column_count: detected_column_count(rows)
      ).tap do |sheet|
        @metadata = {
          "csv_encoding" => encoding,
          "csv_delimiter" => delimiter_label(delimiter),
          "csv_row_count" => meaningful_rows(rows).size,
          "csv_detected_column_count" => sheet.last_column
        }
      end
    rescue CSV::MalformedCSVError, Errno::ENOENT => e
      raise ReadError, e.message
    end

    private

    def decoded_content
      binary = File.binread(@path)
      return [ "", "UTF-8" ] if binary.blank?

      if binary.start_with?(UTF8_BOM)
        text = binary.byteslice(UTF8_BOM.bytesize..).to_s
        text.force_encoding("UTF-8")
        return [ text.encode("UTF-8"), "UTF-8" ] if text.valid_encoding?
      end

      ENCODING_CANDIDATES.each do |encoding_name, label|
        text = binary.dup.force_encoding(encoding_name)
        next unless text.valid_encoding?

        return [ text.encode("UTF-8"), label ]
      end

      [ binary.dup.force_encoding("ISO-8859-1").encode("UTF-8"), "ISO-8859-1" ]
    end

    def sniff_delimiter(content)
      DELIMITERS.max_by do |delimiter|
        delimiter_score(content, delimiter) + [ -DELIMITERS.index(delimiter) ]
      end || ","
    end

    def delimiter_score(content, delimiter)
      rows = parse_csv(content, delimiter)
      counts = meaningful_rows(rows).first(SAMPLE_ROW_LIMIT).map { |row| non_blank_column_count(row) }.select(&:positive?)
      return [ 0, 0, 0, 0 ] if counts.blank?

      mode_columns, consistency = counts.tally.max_by { |column_count, frequency| [ frequency, column_count ] }
      [ mode_columns > 1 ? 1 : 0, consistency, mode_columns, counts.size ]
    rescue CSV::MalformedCSVError
      [ 0, 0, 0, 0 ]
    end

    def parse_csv(content, delimiter)
      CSV.parse(content, col_sep: delimiter, liberal_parsing: true)
    end

    def cells_by_row(rows)
      rows.each_with_index.each_with_object({}) do |(row, row_index), cells|
        Array(row).each_with_index do |value, column_index|
          normalized = normalize_cell(value)
          next if normalized.blank?

          cells[row_index + 1] ||= {}
          cells[row_index + 1][column_index + 1] = normalized
        end
      end
    end

    def detected_column_count(rows)
      rows.map { |row| Array(row).length }.max.to_i
    end

    def meaningful_rows(rows)
      rows.select { |row| Array(row).any? { |value| normalize_cell(value).present? } }
    end

    def non_blank_column_count(row)
      Array(row).count { |value| normalize_cell(value).present? }
    end

    def normalize_cell(value)
      value.to_s.delete_prefix("\uFEFF").strip
    end

    def delimiter_label(delimiter)
      delimiter == "\t" ? "tab" : delimiter
    end
  end
end
