require "bigdecimal"
require "digest"
require "zip"

module BasTdk
  class ReferenceWorkbookReader
    class ReadError < StandardError; end

    MAX_FILE_BYTES = 25.megabytes
    MAX_UNCOMPRESSED_WORKSHEET_BYTES = 75.megabytes
    MAX_ROWS = 50_000
    MAX_COLUMNS = 128
    HEADER_SCAN_ROWS = 30
    SAMPLE_VALUES_PER_COLUMN = 5

    ROLE_ALIASES = {
      "description" => %w[
        description narrative details memo particulars payee merchant transactiondescription
        transactiondetails transactionnarrative
      ],
      "category" => %w[
        category accountname accountcode expensecategory incomecategory classification
        ledger generalledger glcode chartofaccount
      ],
      "amount" => %w[
        amount gross grossamount total totalamount transactionamount
      ],
      "debit" => %w[
        debit debitamount withdrawal withdrawals withdrawalamount moneyout paidout
      ],
      "credit" => %w[
        credit creditamount deposit deposits depositamount moneyin paidin
      ],
      "gst" => %w[
        gst gstamount gstvalue tax taxamount inputtax inputtaxcredit
      ],
      "date" => %w[
        date transactiondate valuedate effectivedate postingdate
      ]
    }.freeze
    REQUIRED_SINGLE_ROLES = %w[description category].freeze
    OPTIONAL_SINGLE_ROLES = %w[gst date].freeze
    CODING_ROLES = %w[description category amount debit credit gst].freeze

    ReferenceRow = Struct.new(
      :source_row_number,
      :description,
      :normalized_description,
      :category,
      :amount,
      :direction,
      :gst_amount,
      :gst_ratio,
      :gst_treatment,
      :snapshot,
      keyword_init: true
    )

    Result = Struct.new(
      :status,
      :rows,
      :sheet_name,
      :header_row_number,
      :data_start_row,
      :original_headers,
      :column_mapping,
      :metadata,
      :errors,
      keyword_init: true
    ) do
      def success?
        status == "processed"
      end

      def needs_mapping?
        status == "needs_mapping"
      end
    end

    def initialize(path:, source_filename: nil, mapping_override: nil)
      @path = path.to_s
      @source_filename = source_filename.to_s
      @mapping_override = mapping_override.is_a?(Hash) ? mapping_override.deep_stringify_keys : {}
    end

    def call
      preflight_file!
      sheet, reader_metadata = read_sheet
      populated_rows = bounded_populated_rows(sheet)
      raise ReadError, "Reference workbook has no populated rows." if populated_rows.empty?

      detection = detect_mapping(populated_rows, sheet)
      unless detection.fetch(:valid)
        return needs_mapping_result(sheet, detection, reader_metadata)
      end

      rows = extract_rows(populated_rows, detection.fetch(:mapping), detection.fetch(:data_start_row))
      Result.new(
        status: "processed",
        rows: rows,
        sheet_name: sheet.name.to_s,
        header_row_number: detection.fetch(:header_row_number),
        data_start_row: detection.fetch(:data_start_row),
        original_headers: detection.fetch(:headers),
        column_mapping: detection.fetch(:mapping),
        metadata: reader_metadata.merge(
          "file_sha256" => Digest::SHA256.file(@path).hexdigest,
          "reference_row_count" => rows.length,
          "bounded_source_row_count" => populated_rows.length,
          "bounded_source_column_count" => bounded_column_count(populated_rows),
          "column_detection" => detection.fetch(:metadata)
        ),
        errors: []
      )
    rescue ReadError, BasTdk::RawCsvReader::ReadError, BasTdk::RawXlsxReader::ReadError => e
      Result.new(
        status: "failed",
        rows: [],
        original_headers: [],
        column_mapping: {},
        metadata: {},
        errors: [ e.message ]
      )
    end

    private

    def preflight_file!
      raise ReadError, "Reference workbook is no longer available. Please upload it again." unless File.file?(@path)
      raise ReadError, "Reference workbook is empty." if File.size(@path).zero?
      raise ReadError, "Reference workbook is too large. The maximum file size is 25 MB." if File.size(@path) > MAX_FILE_BYTES

      return unless xlsx?

      Zip::File.open(@path) do |zip|
        worksheet_entries = zip.entries.select { |entry| entry.name.match?(%r{\Axl/worksheets/[^/]+\.xml\z}) }
        if worksheet_entries.any? { |entry| entry.size > MAX_UNCOMPRESSED_WORKSHEET_BYTES }
          raise ReadError, "Reference worksheet is too large to process safely."
        end
      end
    rescue Zip::Error => e
      raise ReadError, "Reference Excel workbook could not be opened: #{e.message}"
    end

    def read_sheet
      if csv?
        reader = BasTdk::RawCsvReader.new(@path)
        sheet = reader.first_sheet
        [ sheet, reader.metadata ]
      elsif xlsx?
        [ BasTdk::RawXlsxReader.new(@path).first_sheet, {} ]
      else
        raise ReadError, "Reference workbook must be an Excel .xlsx or CSV file."
      end
    end

    def csv?
      extension == ".csv"
    end

    def xlsx?
      extension.in?([ ".xlsx", ".xlsm" ])
    end

    def extension
      File.extname(@source_filename.presence || @path).downcase
    end

    def bounded_populated_rows(sheet)
      source_rows = sheet.cells_by_row.to_a.sort_by(&:first)
      raise ReadError, "Reference workbook exceeds the #{MAX_ROWS.to_fs(:delimited)} row limit." if source_rows.length > MAX_ROWS

      source_rows.each_with_object({}) do |(row_number, cells), rows|
        bounded_cells = cells.to_h.select { |column_number, _value| column_number.to_i.between?(1, MAX_COLUMNS) }
        next if bounded_cells.empty?

        if cells.keys.any? { |column_number| column_number.to_i > MAX_COLUMNS }
          raise ReadError, "Reference workbook exceeds the #{MAX_COLUMNS} column limit."
        end

        rows[row_number.to_i] = bounded_cells
      end
    end

    def bounded_column_count(rows)
      rows.values.flat_map(&:keys).max.to_i
    end

    def detect_mapping(rows, sheet)
      override_header_row = positive_integer(@mapping_override["header_row_number"])
      candidate_rows = if override_header_row
        [ override_header_row ]
      else
        rows.keys.first(HEADER_SCAN_ROWS)
      end

      candidates = candidate_rows.filter_map do |row_number|
        headers = header_values(rows.fetch(row_number, {}))
        next if headers.empty?

        role_candidates = role_candidates_for(headers)
        score = detection_score(role_candidates)
        { row_number: row_number, headers: headers, role_candidates: role_candidates, score: score }
      end
      detected = candidates.max_by { |candidate| [ candidate.fetch(:score), -candidate.fetch(:row_number) ] }

      if detected.blank?
        return invalid_detection(rows, sheet, "No recognizable header row was found.")
      end

      available_columns = rows.values.flat_map(&:keys).map(&:to_i).uniq
      mapping = resolve_mapping(
        detected.fetch(:headers),
        detected.fetch(:role_candidates),
        available_columns: available_columns
      )
      data_start_row = positive_integer(@mapping_override["data_start_row"]) || detected.fetch(:row_number) + 1
      problems = mapping_problems(mapping, detected.fetch(:role_candidates))

      {
        valid: problems.empty?,
        mapping: mapping,
        header_row_number: detected.fetch(:row_number),
        data_start_row: data_start_row,
        headers: headers_in_order(detected.fetch(:headers)),
        metadata: detection_metadata(rows, detected, mapping, problems),
        problems: problems
      }
    end

    def invalid_detection(rows, sheet, problem)
      {
        valid: false,
        mapping: {},
        header_row_number: nil,
        data_start_row: nil,
        headers: [],
        problems: [ problem ],
        metadata: {
          "sheet_name" => sheet.name.to_s,
          "problems" => [ problem ],
          "columns" => sample_columns(rows, nil)
        }
      }
    end

    def header_values(cells)
      cells.each_with_object({}) do |(column_number, value), headers|
        header = value.to_s.strip
        headers[column_number.to_i] = header if header.present?
      end
    end

    def role_candidates_for(headers)
      ROLE_ALIASES.each_key.to_h do |role|
        columns = headers.filter_map do |column_number, header|
          column_number if ROLE_ALIASES.fetch(role).include?(normalized_header(header))
        end
        [ role, columns ]
      end
    end

    def normalized_header(value)
      ActiveSupport::Inflector.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, "")
    end

    def detection_score(role_candidates)
      required = REQUIRED_SINGLE_ROLES.count { |role| role_candidates.fetch(role).one? }
      amount_shape = role_candidates.fetch("amount").one? ||
        (role_candidates.fetch("debit").one? && role_candidates.fetch("credit").one?)
      optional = OPTIONAL_SINGLE_ROLES.count { |role| role_candidates.fetch(role).one? }
      (required * 10) + (amount_shape ? 10 : 0) + optional
    end

    def resolve_mapping(headers, detected_candidates, available_columns:)
      mapping = {}
      CODING_ROLES.each do |role|
        override = resolve_override_column(role, headers, available_columns)
        mapping[role] = override if override
        next if override

        candidates = detected_candidates.fetch(role)
        preferred = preferred_detected_column(role, headers, candidates)
        mapping[role] = preferred if preferred
      end
      mapping
    end

    def preferred_detected_column(role, headers, candidates)
      return candidates.first if candidates.one?
      return if candidates.empty?

      ranked = candidates.map do |column_number|
        alias_rank = ROLE_ALIASES.fetch(role).index(normalized_header(headers[column_number]))
        [ column_number, alias_rank || ROLE_ALIASES.fetch(role).length ]
      end
      best_rank = ranked.map(&:last).min
      best_columns = ranked.select { |_column_number, rank| rank == best_rank }.map(&:first)
      best_columns.one? ? best_columns.first : nil
    end

    def resolve_override_column(role, headers, available_columns)
      raw = normalized_override_columns[role]
      raw = raw["source_column"] || raw["column"] || raw["index"] if raw.is_a?(Hash)
      return if raw.blank?

      if raw.to_s.match?(/\A\d+\z/)
        column = raw.to_i
        return column if column.positive? && available_columns.include?(column)
        return column + 1 if column.zero? && available_columns.include?(1)
      end

      normalized = normalized_header(raw)
      matches = headers.filter_map { |column_number, header| column_number if normalized_header(header) == normalized }
      matches.first if matches.one?
    end

    def normalized_override_columns
      @normalized_override_columns ||= begin
        raw = @mapping_override["columns"]
        raw = @mapping_override["mapping"] unless raw.is_a?(Hash)
        raw = @mapping_override unless raw.is_a?(Hash)
        raw = raw.deep_stringify_keys

        if (raw.keys & ROLE_ALIASES.keys).any?
          raw.slice(*ROLE_ALIASES.keys)
        else
          raw.each_with_object({}) do |(source_column, role), mapping|
            mapping[role.to_s] = source_column if ROLE_ALIASES.key?(role.to_s)
          end
        end
      end
    end

    def mapping_problems(mapping, detected_candidates)
      problems = []
      REQUIRED_SINGLE_ROLES.each do |role|
        problems << "Select one #{role.humanize.downcase} column." unless mapping[role]
      end

      direct_amount = mapping["amount"].present?
      split_amount = mapping["debit"].present? && mapping["credit"].present?
      if direct_amount && (mapping["debit"].present? || mapping["credit"].present?)
        problems << "Select either one amount column or one debit and one credit column."
      elsif direct_amount == split_amount
        problems << "Select either one amount column or one debit and one credit column."
      end

      problems.uniq
    end

    def headers_in_order(headers)
      headers.sort_by(&:first).map(&:last)
    end

    def detection_metadata(rows, detected, mapping, problems)
      columns = sample_columns(rows, detected.fetch(:row_number), detected.fetch(:headers), detected.fetch(:role_candidates), mapping)
      {
        "header_row_number" => detected.fetch(:row_number),
        "data_start_row" => positive_integer(@mapping_override["data_start_row"]) || detected.fetch(:row_number) + 1,
        "mapping" => mapping,
        "suggested_mapping" => suggested_mapping(mapping),
        "problems" => problems,
        "columns" => columns,
        "preview_rows" => preview_rows(rows, detected.fetch(:row_number), columns.map { |column| column.fetch("source_column") })
      }
    end

    def sample_columns(rows, header_row_number, headers = {}, role_candidates = {}, mapping = {})
      column_numbers = rows.values.flat_map(&:keys).uniq.sort.first(MAX_COLUMNS)
      column_numbers.map do |column_number|
        roles = role_candidates.filter_map { |role, columns| role if columns.include?(column_number) }
        samples = rows.filter_map do |row_number, cells|
          next if header_row_number && row_number <= header_row_number

          cells[column_number].to_s.strip.presence
        end.first(SAMPLE_VALUES_PER_COLUMN)

        {
          "source_column" => column_number,
          "index" => column_number,
          "source_header" => headers[column_number].to_s,
          "header" => headers[column_number].to_s,
          "label" => "Column #{spreadsheet_column_name(column_number)}",
          "candidate_roles" => roles,
          "suggested_role" => mapping.key(column_number),
          "samples" => samples,
          "sample_values" => samples
        }
      end
    end

    def suggested_mapping(mapping)
      mapping.each_with_object({}) do |(role, source_column), suggestions|
        suggestions[source_column.to_s] = role
      end
    end

    def preview_rows(rows, header_row_number, column_numbers)
      rows.filter_map do |row_number, cells|
        next if header_row_number && row_number <= header_row_number

        values = column_numbers.map { |column_number| cells[column_number].to_s.strip }
        next if values.all?(&:blank?)

        { "row_number" => row_number, "values" => values }
      end.first(5)
    end

    def spreadsheet_column_name(one_based_column_number)
      number = one_based_column_number.to_i
      label = +""
      while number.positive?
        number, remainder = (number - 1).divmod(26)
        label.prepend((65 + remainder).chr)
      end
      label
    end

    def needs_mapping_result(sheet, detection, reader_metadata)
      Result.new(
        status: "needs_mapping",
        rows: [],
        sheet_name: sheet.name.to_s,
        header_row_number: detection[:header_row_number],
        data_start_row: detection[:data_start_row],
        original_headers: detection.fetch(:headers),
        column_mapping: detection.fetch(:mapping),
        metadata: reader_metadata.merge("column_detection" => detection.fetch(:metadata)),
        errors: detection.fetch(:problems)
      )
    end

    def extract_rows(rows, mapping, data_start_row)
      rows.filter_map do |row_number, cells|
        next if row_number < data_start_row

        description = cell_text(cells, mapping["description"])
        category = cell_text(cells, mapping["category"])
        # Keep uncoded transactions in the reference population so template
        # category coverage measures the workbook that the client actually
        # supplied. Dropping blank categories here would make every surviving
        # template look 100% coded and could incorrectly auto-approve it.
        next if description.blank?
        if category.blank? && BasTdk::TransactionFingerprint.call(description).template_keys.empty?
          next
        end

        amount = amount_from(cells, mapping)
        next if amount.nil?

        normalized_description = BasTdk::DescriptionNormalizer.call(description)
        gst = gst_from(cell_text(cells, mapping["gst"]), amount)
        snapshot = mapping.filter_map do |role, column_number|
          value = cell_text(cells, column_number)
          [ role, value ] if value.present?
        end.to_h

        ReferenceRow.new(
          source_row_number: row_number,
          description: description,
          normalized_description: normalized_description,
          category: category,
          amount: amount,
          direction: direction_for(amount),
          gst_amount: gst.fetch(:amount),
          gst_ratio: gst.fetch(:ratio),
          gst_treatment: gst.fetch(:treatment),
          snapshot: snapshot
        )
      end
    end

    def cell_text(cells, column_number)
      return "" if column_number.blank?

      cells[column_number].to_s.strip
    end

    def amount_from(cells, mapping)
      return parse_decimal(cell_text(cells, mapping["amount"])) if mapping["amount"]

      debit = parse_decimal(cell_text(cells, mapping["debit"]))
      credit = parse_decimal(cell_text(cells, mapping["credit"]))
      return if debit.nil? && credit.nil?

      credit.to_d.abs - debit.to_d.abs
    end

    def parse_decimal(value)
      text = value.to_s.strip
      return if text.blank?

      negative = text.match?(/\A\(.*\)\z/) || text.match?(/-\z/) || text.match?(/\bDR\z/i)
      positive_credit = text.match?(/\bCR\z/i)
      normalized = text.gsub(/[,$\s()]/, "").sub(/(?:CR|DR)\z/i, "").sub(/-\z/, "")
      return unless normalized.match?(/\A[+-]?\d+(?:\.\d+)?\z/)

      number = BigDecimal(normalized)
      number = -number.abs if negative
      number = number.abs if positive_credit
      number
    rescue ArgumentError
      nil
    end

    def gst_from(value, amount)
      text = value.to_s.strip
      return { amount: nil, ratio: nil, treatment: "unknown" } if text.blank?

      normalized = ActiveSupport::Inflector.transliterate(text).downcase.gsub(/[^a-z0-9]+/, " ").strip
      if normalized.match?(/\b(?:gst free|no gst|input taxed|bas excluded|not reportable|n t)\b/)
        treatment = if normalized.include?("input taxed")
          "input_taxed"
        elsif normalized.match?(/\b(?:bas excluded|not reportable)\b/)
          "bas_excluded"
        elsif normalized.include?("gst free")
          "gst_free"
        else
          "no_gst"
        end
        return { amount: BigDecimal("0"), ratio: BigDecimal("0"), treatment: treatment }
      end

      numeric = parse_decimal(text)
      gst_amount = if numeric
        numeric
      elsif normalized.match?(/\b(?:gst included|taxable|gst|10|1 11)\b/)
        amount / 11
      end
      return { amount: nil, ratio: nil, treatment: "needs_review" } unless gst_amount

      ratio = amount.zero? ? nil : gst_amount.abs / amount.abs
      treatment = gst_amount.zero? ? "no_gst" : "taxable"
      { amount: gst_amount, ratio: ratio, treatment: treatment }
    end

    def direction_for(amount)
      return "credit" if amount.positive?
      return "debit" if amount.negative?

      "zero"
    end

    def positive_integer(value)
      integer = value.to_s[/\A\d+\z/]&.to_i
      integer if integer&.positive?
    end
  end
end
