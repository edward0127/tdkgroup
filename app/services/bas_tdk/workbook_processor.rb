module BasTdk
  class WorkbookProcessor
    HEADER_SCAN_LIMIT = 20
    XLSX_CONTENT_TYPES = %w[
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    ].freeze
    HEADER_ALIASES = {
      date: [
        "date",
        "transaction date",
        "txn date",
        "trans date",
        "value date"
      ],
      amount: [
        "amount",
        "transaction amount",
        "debit",
        "credit",
        "withdrawal",
        "deposit",
        "paid in",
        "paid out"
      ],
      description: [
        "description",
        "details",
        "narration",
        "transaction description",
        "transaction details"
      ]
    }.freeze
    DATE_HEADER_ALIASES = HEADER_ALIASES.fetch(:date).freeze
    CATEGORY_ALIASES = %w[category categories].freeze
    GST_ALIASES = %w[gst gst-code gst code tax].freeze
    FRIENDLY_HEADER_ERROR = "Could not find a bank transaction table. Expected headers such as Date, Amount and Description.".freeze

    ParsedWorkbook = Struct.new(
      :sheet_name,
      :header_row_number,
      :original_headers,
      :processed_headers,
      :rows,
      keyword_init: true
    )

    def initialize(bas_job:, actor_username:, uploaded_file: nil, workbook: nil, source_path: nil)
      @bas_job = bas_job
      @uploaded_file = uploaded_file
      @actor_username = actor_username
      @workbook = workbook
      @source_path = source_path
    end

    def call
      workbook = @workbook || build_workbook
      mark_processing(workbook)

      return persist_failed(workbook, [ "Upload an XLSX bank statement file." ]) if source_blank?
      return persist_failed(workbook, [ "Only XLSX bank statement files are supported for the TDK Group BAS workflow." ]) unless xlsx_upload?

      parsed = parse_uploaded_workbook
      return persist_failed(workbook, [ FRIENDLY_HEADER_ERROR ]) if parsed.blank?

      persist_processed(workbook, parsed)
    rescue StandardError => e
      persist_failed(workbook, [ "Bank statement Excel could not be read. Please upload a valid XLSX file." ], exception: e)
    end

    private

    def build_workbook
      @bas_job.tdk_workbooks.build(
        status: "queued",
        source_filename: source_filename,
        version_number: next_version_number,
        processed_by: @actor_username,
        metadata: { "processor" => self.class.name }
      )
    end

    def source_filename
      @workbook&.source_filename.presence || @uploaded_file&.original_filename.to_s.presence || "uploaded-bank-statement.xlsx"
    end

    def next_version_number
      @bas_job.tdk_workbooks.maximum(:version_number).to_i + 1
    end

    def xlsx_upload?
      extension = File.extname(source_filename).downcase
      content_type = if @uploaded_file.respond_to?(:content_type)
        @uploaded_file.content_type.to_s
      elsif @workbook&.source_file&.attached?
        @workbook.source_file.blob.content_type.to_s
      else
        ""
      end

      extension == ".xlsx" || XLSX_CONTENT_TYPES.include?(content_type)
    end

    def parse_uploaded_workbook
      sheet = RawXlsxReader.new(uploaded_file_path).first_sheet
      sheet_name = sheet.name.to_s
      return nil if sheet_name.blank?

      header_row_number = detect_header_row(sheet)
      return nil if header_row_number.blank?

      build_parsed_workbook(sheet: sheet, sheet_name: sheet_name, header_row_number: header_row_number)
    end

    def uploaded_file_path
      if @source_path.present?
        @source_path
      elsif @uploaded_file.respond_to?(:path) && @uploaded_file.path.present?
        @uploaded_file.path
      elsif @uploaded_file.respond_to?(:tempfile)
        @uploaded_file.tempfile.path
      else
        raise ArgumentError, "uploaded file has no readable path"
      end
    end

    def detect_header_row(sheet)
      max_row = [ sheet.last_row.to_i, HEADER_SCAN_LIMIT ].min
      return if max_row.zero?

      candidates = (1..max_row).filter_map do |row_number|
        values = row_values(sheet, row_number, sheet.last_column.to_i)
        score = header_score(values)
        next if score.zero?

        [ row_number, score, values.count(&:present?) ]
      end

      candidates.max_by { |(_, score, populated_count)| [ score, populated_count ] }&.first
    end

    def header_score(values)
      normalized = values.map { |value| normalize_header(value) }.compact_blank
      return 0 unless HEADER_ALIASES.all? { |_, aliases| (normalized & aliases).any? }

      HEADER_ALIASES.sum { |_, aliases| (normalized & aliases).any? ? 10 : 0 } + normalized.size
    end

    def build_parsed_workbook(sheet:, sheet_name:, header_row_number:)
      last_column = sheet.last_column.to_i
      original_headers = row_values(sheet, header_row_number, last_column)
      source_rows = source_rows(sheet, header_row_number, last_column)
      mapped = map_headers(original_headers)
      detail_values_by_row = {}
      detail_header = nil

      rows = []
      source_rows.each do |(source_row_number, values)|
        named_values = mapped.fetch(:named_columns).each_with_object({}) do |column, data|
          header = column.fetch(:header)
          data[header] = display_value(values[column.fetch(:index)], header: header)
        end

        details = mapped.fetch(:blank_column_indices).filter_map { |index| display_value(values[index]).presence }
        if details.any?
          detail_header ||= details_header(mapped.fetch(:headers))
          detail_values_by_row[rows.length + 1] = details.join(" | ")
        end

        next if named_values.values.all?(&:blank?) && details.blank?

        rows << {
          position: rows.length + 1,
          source_row_number: source_row_number,
          data: named_values
        }
      end

      processed_headers = mapped.fetch(:headers)
      processed_headers = append_detail_header(processed_headers, detail_header) if detail_header.present?
      processed_headers = ensure_required_columns(processed_headers)

      rows.each do |row|
        if detail_header.present? && detail_values_by_row[row.fetch(:position)].present?
          row[:data][detail_header] = [
            row[:data][detail_header].presence,
            detail_values_by_row[row.fetch(:position)]
          ].compact.join(" | ")
        end
        processed_headers.each { |header| row[:data][header] = "" unless row[:data].key?(header) }
      end

      ParsedWorkbook.new(
        sheet_name: sheet_name,
        header_row_number: header_row_number,
        original_headers: original_headers,
        processed_headers: processed_headers,
        rows: rows
      )
    end

    def source_rows(sheet, header_row_number, last_column)
      return [] if sheet.last_row.to_i <= header_row_number

      ((header_row_number + 1)..sheet.last_row.to_i).map do |row_number|
        [ row_number, row_values(sheet, row_number, last_column) ]
      end
    end

    def map_headers(original_headers)
      used_headers = {}
      named_columns = []
      blank_column_indices = []

      original_headers.each_with_index do |header, index|
        header = header.to_s.strip
        if header.blank?
          blank_column_indices << index
          next
        end

        normalized = normalize_required_header(header)
        safe_header = unique_header(normalized, used_headers)
        named_columns << { index: index, header: safe_header }
      end

      {
        headers: named_columns.map { |column| column.fetch(:header) },
        named_columns: named_columns,
        blank_column_indices: blank_column_indices
      }
    end

    def normalize_required_header(header)
      normalized = normalize_header(header)
      return "Category" if CATEGORY_ALIASES.include?(normalized)
      return "GST" if GST_ALIASES.include?(normalized)

      header.to_s.strip
    end

    def details_header(existing_headers)
      return "Details" unless existing_headers.include?("Details")

      "Details"
    end

    def append_detail_header(headers, detail_header)
      return headers if headers.include?(detail_header)

      headers + [ detail_header ]
    end

    def ensure_required_columns(headers)
      processed = headers.dup

      unless header_present?(processed, CATEGORY_ALIASES)
        insert_after_header!(processed, "Category", HEADER_ALIASES.fetch(:date))
      end

      unless header_present?(processed, GST_ALIASES)
        insert_after_header!(processed, "GST", HEADER_ALIASES.fetch(:amount))
      end

      processed
    end

    def header_present?(headers, aliases)
      headers.any? { |header| aliases.include?(normalize_header(header)) }
    end

    def insert_after_header!(headers, new_header, anchor_aliases)
      anchor_index = headers.index { |header| anchor_aliases.include?(normalize_header(header)) }
      insertion_index = anchor_index ? anchor_index + 1 : headers.length
      headers.insert(insertion_index, new_header)
    end

    def unique_header(header, used_headers)
      base_header = header.presence || "Extra"
      count = used_headers[base_header].to_i
      used_headers[base_header] = count + 1
      return base_header if count.zero?

      "#{base_header} #{count + 1}"
    end

    def row_values(sheet, row_number, last_column)
      return [] if last_column.zero?

      (1..last_column).map { |column_number| raw_cell(sheet, row_number, column_number) }
    end

    def raw_cell(sheet, row_number, column_number)
      value = sheet.cell(row_number, column_number)
      display_value(value)
    end

    def display_value(value, header: nil)
      serial_date = excel_serial_date(value) if header.present? && date_header?(header)
      return serial_date.to_fs(:db) if serial_date.present?

      case value
      when nil
        ""
      when Date
        value.to_fs(:db)
      when Time, DateTime
        value.to_date.to_fs(:db)
      else
        BasTdk::WorkbookValues.clean_excel_decimal_noise(value.to_s.strip)
      end
    end

    def date_header?(header)
      DATE_HEADER_ALIASES.include?(normalize_header(header))
    end

    def excel_serial_date(value)
      return unless numeric_value?(value)

      Date.new(1899, 12, 30) + value.to_f.to_i
    end

    def numeric_value?(value)
      return true if value.is_a?(Numeric)

      value.to_s.match?(/\A-?\d+(?:\.\d+)?\z/)
    end

    def normalize_header(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end

    def persist_processed(workbook, parsed)
      BasTdkWorkbook.transaction do
        now = Time.current
        workbook.rows.delete_all if workbook.persisted?

        workbook.assign_attributes(
          sheet_name: parsed.sheet_name,
          header_row_number: parsed.header_row_number,
          original_headers: parsed.original_headers,
          processed_headers: parsed.processed_headers,
          row_count: parsed.rows.size,
          row_errors: [],
          processing_finished_at: nil,
          processed_at: nil
        )
        workbook.save! if workbook.new_record?

        parsed.rows.each do |row|
          workbook.rows.create!(
            position: row.fetch(:position),
            source_row_number: row.fetch(:source_row_number),
            row_data: row.fetch(:data)
          )
        end

        @bas_job.tdk_workbooks.processed.where.not(id: workbook.id).update_all(status: "superseded", superseded_at: now, updated_at: now)
        workbook.assign_attributes(
          status: "processed",
          processed_at: now,
          processing_finished_at: now,
          export_status: "not_started",
          export_error: nil,
          export_generated_at: nil,
          export_started_at: nil,
          export_finished_at: nil
        )
        workbook.save!
        attach_upload(workbook)
      end

      workbook
    end

    def persist_failed(workbook, messages, exception: nil)
      workbook.assign_attributes(
        status: "failed",
        row_count: 0,
        row_errors: messages,
        processing_finished_at: Time.current,
        processed_at: Time.current
      )
      workbook.metadata = workbook.metadata.merge(
        "exception_class" => exception.class.name,
        "exception_message" => exception.message.to_s
      ) if exception.present?
      workbook.save!
      attach_upload(workbook)
      workbook
    end

    def mark_processing(workbook)
      return if workbook.processing?

      workbook.assign_attributes(
        status: "processing",
        processing_started_at: Time.current,
        processing_finished_at: nil,
        processed_by: @actor_username
      )
      workbook.metadata = workbook.metadata.merge("processor" => self.class.name)
      workbook.save!
    end

    def source_blank?
      @source_path.blank? && @uploaded_file.blank? && !@workbook&.source_file&.attached?
    end

    def attach_upload(workbook)
      return if @uploaded_file.blank? || workbook.source_file.attached?

      workbook.source_file.attach(@uploaded_file)
    end
  end
end
