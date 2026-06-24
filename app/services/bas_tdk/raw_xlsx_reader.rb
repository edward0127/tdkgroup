require "nokogiri"
require "pathname"
require "zip"

module BasTdk
  class RawXlsxReader
    class ReadError < StandardError; end

    Sheet = Struct.new(:name, :cells_by_row, keyword_init: true) do
      def last_row
        cells_by_row.keys.max.to_i
      end

      def last_column
        cells_by_row.values.filter_map { |row| row.keys.max }.max.to_i
      end

      def cell(row_number, column_number)
        cells_by_row.dig(row_number, column_number)
      end
    end

    def initialize(path)
      @path = path
    end

    def first_sheet
      Zip::File.open(@path) do |zip|
        workbook_doc = xml_doc(read_required_entry(zip, "xl/workbook.xml"))
        rels_doc = xml_doc(read_required_entry(zip, "xl/_rels/workbook.xml.rels"))
        sheet_node = workbook_doc.at_xpath("//sheets/sheet")
        raise ReadError, "workbook has no worksheets" if sheet_node.blank?

        worksheet_path = worksheet_path_for(sheet_node, rels_doc)
        shared_strings = read_shared_strings(zip)

        Sheet.new(
          name: sheet_node["name"].to_s,
          cells_by_row: read_sheet_cells(zip, worksheet_path, shared_strings)
        )
      end
    rescue Zip::Error, Nokogiri::XML::SyntaxError, Errno::ENOENT => e
      raise ReadError, e.message
    end

    private

    def read_required_entry(zip, name)
      entry = zip.find_entry(name)
      raise ReadError, "missing #{name}" if entry.blank?

      entry.get_input_stream { |stream| stream.read }
    end

    def read_optional_entry(zip, name)
      entry = zip.find_entry(name)
      entry&.get_input_stream { |stream| stream.read }
    end

    def xml_doc(content)
      Nokogiri::XML(content) { |config| config.strict.noblanks }.tap(&:remove_namespaces!)
    end

    def worksheet_path_for(sheet_node, rels_doc)
      relationship_id = sheet_node["id"] || sheet_node["r:id"]
      relationship = rels_doc.xpath("//Relationship").find { |node| node["Id"] == relationship_id }
      raise ReadError, "worksheet relationship not found" if relationship.blank?

      normalize_zip_path("xl/workbook.xml", relationship["Target"].to_s)
    end

    def normalize_zip_path(base_path, target)
      target = target.delete_prefix("/")
      return target if target.start_with?("xl/")

      Pathname.new(File.join(File.dirname(base_path), target)).cleanpath.to_s.tr("\\", "/")
    end

    def read_shared_strings(zip)
      content = read_optional_entry(zip, "xl/sharedStrings.xml")
      return [] if content.blank?

      xml_doc(content).xpath("//si").map do |node|
        node.xpath(".//t").map(&:text).join
      end
    end

    def read_sheet_cells(zip, worksheet_path, shared_strings)
      doc = xml_doc(read_required_entry(zip, worksheet_path))
      cells_by_row = {}
      fallback_row_number = 0

      doc.xpath("//sheetData/row").each do |row_node|
        fallback_row_number += 1
        row_number = positive_integer(row_node["r"]) || fallback_row_number
        last_column_number = 0

        row_node.xpath("./c").each do |cell_node|
          column_number = column_number_for(cell_node, last_column_number + 1)
          last_column_number = column_number
          value = cell_value(cell_node, shared_strings)
          next if value.nil?

          cells_by_row[row_number] ||= {}
          cells_by_row[row_number][column_number] = value
        end
      end

      cells_by_row
    end

    def cell_value(cell_node, shared_strings)
      type = cell_node["t"].to_s

      case type
      when "s"
        shared_string_value(value_node_text(cell_node), shared_strings)
      when "inlineStr"
        cell_node.xpath("./is//t").map(&:text).join
      when "b"
        value_node_text(cell_node) == "1" ? "TRUE" : "FALSE"
      else
        value_node_text(cell_node)
      end
    end

    def value_node_text(cell_node)
      cell_node.at_xpath("./v")&.text
    end

    def shared_string_value(index_value, shared_strings)
      index = index_value.to_s[/\A\d+\z/]&.to_i
      return "" if index.nil?

      shared_strings[index].to_s
    end

    def column_number_for(cell_node, fallback)
      reference = cell_node["r"].to_s
      letters = reference[/\A[A-Z]+/i]
      return fallback if letters.blank?

      letters.upcase.chars.reduce(0) { |total, char| (total * 26) + char.ord - 64 }
    end

    def positive_integer(value)
      integer = value.to_s[/\A\d+\z/]&.to_i
      integer if integer&.positive?
    end
  end
end
