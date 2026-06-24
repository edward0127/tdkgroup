require "caxlsx"

module BasTdk
  class WorkbookExporter
    XLSX_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze
    DATE_FORMAT = "dd/mm/yyyy".freeze
    AMOUNT_FORMAT = "#,##0.00;[Red](#,##0.00)".freeze
    MINIMUM_HEADER_ROW_NUMBER = 4
    METADATA_COLUMN_COUNT = 6
    METADATA_COLUMN_WIDTHS = [ 16, 20, 12, 34, 12, 20 ].freeze
    PREFERRED_HEADER_ORDER = [ "Date", "Category", "Amount", "GST", "Description", "Details" ].freeze

    def initialize(workbook:)
      @workbook = workbook
    end

    def call
      package = Axlsx::Package.new
      build_workbook(package.workbook)
      package.to_stream.read
    end

    private

    def build_workbook(xlsx)
      styles = export_styles(xlsx)
      headers = export_headers
      rows = @workbook.rows.ordered.to_a
      header_row_number = export_header_row_number

      xlsx.add_worksheet(name: worksheet_name) do |sheet|
        add_metadata_rows(sheet, styles)
        sheet.add_row(headers, style: Array.new(headers.length, styles.fetch(:header)), types: Array.new(headers.length, :string))

        rows.each do |row|
          cells = headers.map { |header| export_cell(header, row.row_data[header], styles) }
          sheet.add_row(
            cells.map { |cell| cell.fetch(:value) },
            style: cells.map { |cell| cell.fetch(:style) },
            types: cells.map { |cell| cell.fetch(:type) }
          )
        end

        freeze_header_row(sheet, header_row_number)
        apply_filter(sheet, headers.length, header_row_number, rows.length)
        sheet.column_widths(*column_widths(headers, rows))
      end
    end

    def export_styles(xlsx)
      {
        metadata_title: xlsx.styles.add_style(b: true, sz: 14, fg_color: "0F3A54", alignment: { vertical: :center }),
        metadata_label: xlsx.styles.add_style(b: true, fg_color: "475569", alignment: { vertical: :center }),
        metadata_value: xlsx.styles.add_style(alignment: { wrap_text: true, vertical: :center }),
        header: xlsx.styles.add_style(b: true, bg_color: "E7F6FB", fg_color: "0F3A54", border: { style: :thin, color: "C8D6E5" }),
        text: xlsx.styles.add_style(alignment: { wrap_text: true, vertical: :top }),
        date: xlsx.styles.add_style(format_code: DATE_FORMAT),
        amount: xlsx.styles.add_style(format_code: AMOUNT_FORMAT, alignment: { horizontal: :right }),
        blank: xlsx.styles.add_style
      }
    end

    def add_metadata_rows(sheet, styles)
      sheet.add_row(
        [ metadata_title_text, "", "", "", "", "" ],
        style: Array.new(METADATA_COLUMN_COUNT, styles.fetch(:metadata_title)),
        types: Array.new(METADATA_COLUMN_COUNT, :string),
        height: 22
      )
      sheet.merge_cells("A1:F1")

      sheet.add_row(
        metadata_detail_values,
        style: metadata_detail_styles(styles),
        types: Array.new(METADATA_COLUMN_COUNT, :string),
        height: 24
      )

      sheet.add_row(
        Array.new(METADATA_COLUMN_COUNT, ""),
        style: Array.new(METADATA_COLUMN_COUNT, styles.fetch(:blank)),
        types: Array.new(METADATA_COLUMN_COUNT, :string),
        height: 8
      )
    end

    def metadata_title_text
      @workbook.bas_job.bas_client.primary_name.to_s.presence || "TDK bank statement"
    end

    def metadata_detail_values
      [
        "BAS period",
        @workbook.bas_job.period_label,
        "Source file",
        @workbook.source_filename.to_s.presence || "Not recorded",
        "Exported",
        Time.current.strftime("%d/%m/%Y %H:%M")
      ]
    end

    def metadata_detail_styles(styles)
      [
        styles.fetch(:metadata_label),
        styles.fetch(:metadata_value),
        styles.fetch(:metadata_label),
        styles.fetch(:metadata_value),
        styles.fetch(:metadata_label),
        styles.fetch(:metadata_value)
      ]
    end

    def export_cell(header, value, styles)
      if BasTdk::WorkbookValues.date_header?(header)
        date = BasTdk::WorkbookValues.parse_date(value)
        return { value: date, type: :date, style: styles.fetch(:date) } if date.present?
      end

      if BasTdk::WorkbookValues.amount_header?(header)
        amount = BasTdk::WorkbookValues.rounded_amount(value)
        return { value: amount.to_f, type: :float, style: styles.fetch(:amount) } if amount.present?
      end

      text = safe_text(value)
      { value: text, type: :string, style: styles.fetch(:text) }
    end

    def worksheet_name
      name = @workbook.sheet_name.to_s.gsub(/[\\\/\?\*\[\]:]/, " ").squish.presence || "TDK Workbook"
      name.first(31)
    end

    def export_header_row_number
      MINIMUM_HEADER_ROW_NUMBER
    end

    def export_headers
      headers = @workbook.processed_headers
      ordered_headers = PREFERRED_HEADER_ORDER.filter_map do |preferred_header|
        headers.find { |header| BasTdk::WorkbookValues.normalize_header(header) == BasTdk::WorkbookValues.normalize_header(preferred_header) }
      end

      ordered_headers + (headers - ordered_headers)
    end

    def safe_text(value)
      text = BasTdk::WorkbookValues.clean_excel_decimal_noise(value)
      return "'#{text}" if text.start_with?("=", "+", "-", "@")

      text
    end

    def freeze_header_row(sheet, header_row_number)
      sheet.sheet_view.pane do |pane|
        pane.state = :frozen
        pane.y_split = header_row_number
        pane.top_left_cell = "A#{header_row_number + 1}"
        pane.active_pane = :bottom_left
      end
    rescue NoMethodError
      nil
    end

    def apply_filter(sheet, column_count, header_row_number, row_count)
      return if column_count.zero?

      last_row = [ header_row_number + row_count, header_row_number ].max
      sheet.auto_filter = "A#{header_row_number}:#{column_name(column_count)}#{last_row}"
    end

    def column_widths(headers, rows)
      data_widths = headers.map do |header|
        if BasTdk::WorkbookValues.date_header?(header)
          13
        elsif BasTdk::WorkbookValues.amount_header?(header)
          14
        elsif BasTdk::WorkbookValues.normalize_header(header).include?("category")
          18
        elsif BasTdk::WorkbookValues.normalize_header(header).include?("description")
          36
        elsif BasTdk::WorkbookValues.normalize_header(header).match?(/\b(details|narration|reference|memo)\b/)
          40
        else
          values = rows.first(100).map { |row| row.row_data[header].to_s.length }
          [ [ header.to_s.length, *values ].max + 2, 12 ].max.clamp(12, 34)
        end
      end

      METADATA_COLUMN_WIDTHS.each_with_index do |width, index|
        data_widths[index] = [ data_widths[index].to_i, width ].max
      end

      data_widths
    end

    def column_name(index)
      name = +""
      while index.positive?
        index -= 1
        name.prepend((65 + (index % 26)).chr)
        index /= 26
      end
      name
    end
  end
end
