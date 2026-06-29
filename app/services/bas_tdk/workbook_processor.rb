module BasTdk
  class WorkbookProcessor
    HEADER_SCAN_LIMIT = 20
    HEADERLESS_SAMPLE_LIMIT = 20
    HEADERLESS_REQUIRED_COLUMN_COUNT = 3
    HEADERLESS_MIN_CONFIDENT_ROWS = 3
    HEADERLESS_MIN_CONFIDENT_RATIO = 0.6
    HEADERLESS_HEADERS = [ "Date", "Amount", "Description" ].freeze
    XLSX_CONTENT_TYPES = %w[
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    ].freeze
    PDF_CONTENT_TYPES = %w[
      application/pdf
    ].freeze
    CSV_CONTENT_TYPES = BasTdk::BankStatementImporter::CSV_CONTENT_TYPES
    SUPPORTED_UPLOAD_ERROR = BasTdk::BankStatementImporter::SUPPORTED_UPLOAD_ERROR
    HEADER_ALIASES = {
      date: [
        "date",
        "transaction date",
        "txn date",
        "trans date",
        "value date",
        "posting date",
        "posted date"
      ],
      amount: [
        "amount",
        "transaction amount",
        "debit",
        "debit amount",
        "debits",
        "credit",
        "credit amount",
        "credits",
        "withdrawal",
        "withdrawal amount",
        "withdrawals",
        "deposit",
        "deposit amount",
        "deposits",
        "paid in",
        "paid out"
      ],
      description: [
        "description",
        "transaction",
        "details",
        "narration",
        "transaction description",
        "transaction details"
      ]
    }.freeze
    DATE_HEADER_ALIASES = HEADER_ALIASES.fetch(:date).freeze
    DIRECT_AMOUNT_ALIASES = [
      "amount",
      "transaction amount"
    ].freeze
    DEBIT_AMOUNT_ALIASES = [
      "debit",
      "debits",
      "debit amount",
      "withdrawal",
      "withdrawals",
      "withdrawal amount",
      "paid out"
    ].freeze
    CREDIT_AMOUNT_ALIASES = [
      "credit",
      "credits",
      "credit amount",
      "deposit",
      "deposits",
      "deposit amount",
      "paid in"
    ].freeze
    CATEGORY_ALIASES = %w[category categories].freeze
    GST_ALIASES = %w[gst gst-code gst code tax].freeze
    FRIENDLY_HEADER_ERROR = "Could not find a bank transaction table. Expected headers such as Date, Amount and Description, or a headerless CSV where the first three columns are Date, Amount and Description.".freeze
    READABLE_PDF_UNRELIABLE_MESSAGE = "This readable PDF could not be parsed reliably. Please upload an XLSX export or a clearer bank statement PDF.".freeze
    LOCAL_PDF_TEXT_MODES = %i[layout layout_nopgbrk raw table fixed].freeze
    PDF_AMOUNT_COVERAGE_MINIMUM = 0.95
    PDF_BALANCE_COVERAGE_MINIMUM = 0.90
    PDF_RECONCILIATION_QUALITY_ROW_MINIMUM = 3

    ParsedWorkbook = Struct.new(
      :sheet_name,
      :header_row_number,
      :original_headers,
      :processed_headers,
      :rows,
      keyword_init: true
    )
    HeaderlessCandidate = Struct.new(
      :data_start_row,
      :sample_row_count,
      :confident_row_count,
      :detected_column_count,
      :ignored_column_count,
      keyword_init: true
    )
    PdfParseCandidate = Struct.new(:strategy, :parsed, :error, keyword_init: true) do
      def success?
        parsed.present?
      end

      def metadata
        parsed&.metadata || {}
      end

      def row_count
        metadata.fetch("row_count", parsed&.rows.to_a.size).to_i
      end

      def candidate_count
        metadata.fetch("candidate_transaction_count", 0).to_i
      end

      def quality
        metadata.fetch("quality", "good").to_s
      end

      def quality_score
        metadata.fetch("quality_score", row_count).to_f
      end

      def low_recall?
        quality == "low_recall"
      end

      def poor_balance_continuity?
        quality == "poor_balance_continuity"
      end

      def statement_reconciliation_quality_failure?
        statement_reconciliation_status == "mismatch" && row_count >= PDF_RECONCILIATION_QUALITY_ROW_MINIMUM
      end

      def reliable?
        success? &&
          row_count.positive? &&
          !low_recall? &&
          !poor_balance_continuity? &&
          !statement_reconciliation_quality_failure? &&
          amount_coverage >= PDF_AMOUNT_COVERAGE_MINIMUM &&
          balance_coverage_high?
      end

      def balance_continuity_mismatch_count
        metadata.fetch("balance_continuity_mismatch_count", 0).to_i
      end

      def balance_continuity_mismatch_ratio
        metadata.fetch("balance_continuity_mismatch_ratio", 0.0).to_f
      end

      def balance_continuity_coverage
        metadata.fetch("balance_continuity_coverage", 0.0).to_f
      end

      def amount_coverage
        metadata.fetch("amount_coverage", 1.0).to_f
      end

      def balance_coverage
        metadata.fetch("balance_coverage", 1.0).to_f
      end

      def balance_coverage_high?
        !balance_expected? || balance_coverage >= PDF_BALANCE_COVERAGE_MINIMUM
      end

      def balance_expected?
        parsed&.processed_headers.to_a.include?("Balance") || metadata.key?("balance_coverage")
      end

      def statement_reconciliation_status
        metadata.fetch("statement_reconciliation_status", "not_available").to_s
      end

      def statement_reconciliation_rank
        case statement_reconciliation_status
        when "matched" then 2
        when "not_available" then 1
        else 0
        end
      end

      def recall_ratio
        return 1.0 unless candidate_count.positive?

        [ row_count.to_f / candidate_count, 1.0 ].min
      end

      def footer_header_contamination_count
        metadata.fetch("footer_header_contamination_count", 0).to_i
      end
    end

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

      return persist_failed(workbook, [ "Upload a bank statement Excel, CSV or PDF file." ]) if source_blank?
      return persist_failed(workbook, [ SUPPORTED_UPLOAD_ERROR ]) unless supported_upload?

      parsed = parse_uploaded_statement
      return persist_failed(workbook, [ FRIENDLY_HEADER_ERROR ]) if parsed.blank?

      persist_processed(workbook, parsed)
    rescue BasTdk::PdfStatementParser::ParseError => e
      persist_failed(workbook, [ e.message ])
    rescue BasTdk::RawXlsxReader::ReadError => e
      persist_failed(workbook, [ "Bank statement Excel could not be read. Please upload a valid XLSX file." ], exception: e)
    rescue BasTdk::RawCsvReader::ReadError => e
      persist_failed(workbook, [ "Bank statement CSV could not be read. Please upload a valid CSV file." ], exception: e)
    rescue StandardError => e
      persist_failed(workbook, [ "Bank statement file could not be read. Please upload a valid Excel, CSV or bank statement PDF." ], exception: e)
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
      @workbook&.source_filename.presence || @uploaded_file&.original_filename.to_s.presence || "uploaded-bank-statement"
    end

    def next_version_number
      @bas_job.tdk_workbooks.maximum(:version_number).to_i + 1
    end

    def supported_upload?
      source_type.present?
    end

    def source_type
      @source_type ||= BasTdk::BankStatementImporter.source_type(
        filename: source_filename,
        content_type: source_content_type
      )
    end

    def source_content_type
      if @uploaded_file.respond_to?(:content_type)
        @uploaded_file.content_type.to_s
      elsif @workbook&.source_file&.attached?
        @workbook.source_file.blob.content_type.to_s
      else
        ""
      end
    end

    def parse_uploaded_statement
      BasTdk::BankStatementImporter.new(
        source_type: source_type,
        xlsx_parser: -> { parse_uploaded_workbook },
        pdf_parser: -> { parse_uploaded_pdf_statement },
        csv_parser: -> { parse_uploaded_csv }
      ).call
    end

    def parse_uploaded_pdf_statement
      @ocr_metadata = { "ocr_attempted" => false }
      @pdf_parse_metadata = {}
      reader_candidate = parse_pdf_candidate("pdf_reader") do
        BasTdk::PdfStatementParser.new(path: uploaded_file_path).call
      end
      record_pdf_parse_candidate_metadata(reader_candidate)

      local_text_candidates = local_pdf_text_parse_candidates
      candidates = [ reader_candidate, *local_text_candidates ].compact
      best_candidate = best_pdf_parse_candidate(candidates)

      if best_candidate&.success? && acceptable_pdf_parse_candidate?(best_candidate)
        select_pdf_parse_candidate(best_candidate)
        return best_candidate.parsed
      end

      if candidates.any?(&:success?)
        return parse_uploaded_pdf_statement_with_ocr(reader_candidate.error) if reader_candidate.error&.ocr_eligible?

        select_pdf_parse_candidate(best_candidate)
        raise BasTdk::PdfStatementParser::ParseError.new(READABLE_PDF_UNRELIABLE_MESSAGE, code: :no_transaction_table)
      end

      parse_uploaded_pdf_statement_with_ocr(reader_candidate.error || local_text_candidates.find(&:error)&.error)
    end

    def parse_pdf_candidate(strategy)
      parsed = yield
      PdfParseCandidate.new(strategy: strategy, parsed: parsed)
    rescue BasTdk::PdfStatementParser::ParseError => e
      PdfParseCandidate.new(strategy: strategy, error: e)
    end

    def local_pdf_text_parse_candidates
      LOCAL_PDF_TEXT_MODES.filter_map do |mode|
        result = BasTdk::LocalPdfTextExtractor.new(path: uploaded_file_path, mode: mode).call
        record_local_pdf_text_extraction_metadata(result, mode: mode)
        next unless result.success?

        parse_pdf_candidate("pdf_text_#{mode}") do
          BasTdk::PdfStatementParser.new(text: result.text, source_name: "PDF text #{mode}").call
        end.tap do |candidate|
          record_pdf_parse_candidate_metadata(candidate)
        end
      end
    end

    def best_pdf_parse_candidate(candidates)
      candidates.select(&:success?).max_by do |candidate|
        [
          candidate.reliable? ? 1 : 0,
          candidate.quality == "good" ? 1 : 0,
          candidate.statement_reconciliation_rank,
          -candidate.balance_continuity_mismatch_count,
          -candidate.balance_continuity_mismatch_ratio,
          candidate.balance_continuity_coverage,
          candidate.amount_coverage,
          candidate.balance_coverage,
          candidate.recall_ratio,
          -candidate.footer_header_contamination_count,
          candidate.quality_score,
          candidate.row_count,
          candidate.candidate_count
        ]
      end
    end

    def acceptable_pdf_parse_candidate?(candidate)
      candidate.success? && candidate.reliable?
    end

    def record_local_pdf_text_extraction_metadata(result, mode:)
      metadata_prefix = "pdf_text_#{mode}"
      metadata = {
        "local_pdf_text_command" => result.command,
        "#{metadata_prefix}_attempted" => result.attempted,
        "#{metadata_prefix}_status" => result.status,
        "#{metadata_prefix}_line_count" => result.line_count,
        "#{metadata_prefix}_byte_count" => result.byte_count
      }
      metadata["local_pdf_text_command_resolved"] = result.command_resolved if result.command_resolved.present?
      metadata["#{metadata_prefix}_sha256"] = result.text_sha256 if result.text_sha256.present?

      @pdf_parse_metadata = @pdf_parse_metadata.merge(metadata.compact)
    end

    def record_pdf_parse_candidate_metadata(candidate)
      prefix = pdf_parse_candidate_metadata_prefix(candidate.strategy)
      metadata = { "#{prefix}_parse_status" => candidate.success? ? "parsed" : "failed" }

      if candidate.success?
        metadata.merge!(
          "#{prefix}_row_count" => candidate.row_count,
          "#{prefix}_candidate_count" => candidate.candidate_count,
          "#{prefix}_quality" => candidate.quality,
          "#{prefix}_quality_score" => candidate.quality_score,
          "#{prefix}_amount_coverage" => candidate.amount_coverage,
          "#{prefix}_balance_coverage" => candidate.balance_coverage,
          "#{prefix}_balance_continuity_mismatch_count" => candidate.balance_continuity_mismatch_count,
          "#{prefix}_balance_continuity_mismatch_ratio" => candidate.balance_continuity_mismatch_ratio,
          "#{prefix}_statement_reconciliation_status" => candidate.statement_reconciliation_status,
          "#{prefix}_statement_reconciliation_delta_mismatch" => candidate.metadata["statement_reconciliation_delta_mismatch"],
          "#{prefix}_footer_header_contamination_count" => candidate.footer_header_contamination_count
        )
      elsif candidate.error.present?
        metadata["#{prefix}_parse_error_code"] = candidate.error.code.to_s
      end

      @pdf_parse_metadata = @pdf_parse_metadata.merge(metadata)
    end

    def pdf_parse_candidate_metadata_prefix(strategy)
      strategy
    end

    def select_pdf_parse_candidate(candidate)
      return if candidate.blank? || !candidate.success?

      @pdf_parse_metadata = @pdf_parse_metadata.merge(
        "pdf_parse_strategy" => candidate.strategy,
        "pdf_parse_row_count" => candidate.row_count,
        "pdf_parse_candidate_count" => candidate.candidate_count,
        "pdf_parse_quality" => candidate.quality,
        "pdf_parse_quality_score" => candidate.quality_score,
        "pdf_parse_amount_coverage" => candidate.amount_coverage,
        "pdf_parse_balance_coverage" => candidate.balance_coverage,
        "pdf_parse_balance_continuity_mismatch_count" => candidate.balance_continuity_mismatch_count,
        "pdf_parse_balance_continuity_mismatch_ratio" => candidate.balance_continuity_mismatch_ratio,
        "pdf_parse_statement_reconciliation_status" => candidate.statement_reconciliation_status,
        "pdf_parse_statement_reconciliation_delta_mismatch" => candidate.metadata["statement_reconciliation_delta_mismatch"],
        "pdf_parse_footer_header_contamination_count" => candidate.footer_header_contamination_count
      )
    end

    def parse_uploaded_pdf_statement_with_ocr(parse_error)
      unless parse_error&.ocr_eligible?
        raise parse_error if parse_error.present?

        raise BasTdk::PdfStatementParser::ParseError.new(READABLE_PDF_UNRELIABLE_MESSAGE, code: :no_transaction_table)
      end

      ocr_result = BasTdk::LocalOcr.new(path: uploaded_file_path).call
      @ocr_metadata = {
        "ocr_attempted" => ocr_result.attempted,
        "ocr_status" => ocr_result.status,
        "ocr_parser" => "local_ocr"
      }

      unless ocr_result.success?
        raise BasTdk::PdfStatementParser::ParseError.new(ocr_result.message, code: parse_error.code)
      end

      begin
        parsed = BasTdk::PdfStatementParser.new(text: ocr_result.text, source_name: "OCR text").call
        ocr_candidate = PdfParseCandidate.new(strategy: "ocr", parsed: parsed)
        unless acceptable_pdf_parse_candidate?(ocr_candidate)
          @ocr_metadata = @ocr_metadata.merge("ocr_status" => "failed")
          select_pdf_parse_candidate(ocr_candidate)
          raise BasTdk::PdfStatementParser::ParseError.new(BasTdk::LocalOcr::UNRELIABLE_MESSAGE, code: :no_transaction_table)
        end

        select_pdf_parse_candidate(ocr_candidate)
        @ocr_metadata = @ocr_metadata.merge(
          "ocr_status" => "succeeded",
          "ocr_row_count" => parsed.rows.size
        )
        parsed
      rescue BasTdk::PdfStatementParser::ParseError
        @ocr_metadata = @ocr_metadata.merge("ocr_status" => "failed")
        raise BasTdk::PdfStatementParser::ParseError.new(BasTdk::LocalOcr::UNRELIABLE_MESSAGE, code: :no_transaction_table)
      end
    end

    def parse_uploaded_workbook
      sheet = RawXlsxReader.new(uploaded_file_path).first_sheet
      sheet_name = sheet.name.to_s
      parse_statement_sheet(sheet: sheet, sheet_name: sheet_name, metadata_prefix: "xlsx")
    end

    def parse_uploaded_csv
      reader = RawCsvReader.new(uploaded_file_path)
      sheet = reader.first_sheet
      @csv_parse_metadata = reader.metadata
      parse_statement_sheet(sheet: sheet, sheet_name: sheet.name.to_s, metadata_prefix: "csv")
    end

    def parse_statement_sheet(sheet:, sheet_name:, metadata_prefix:)
      return nil if sheet_name.blank?

      header_row_number = detect_header_row(sheet)
      if header_row_number.present?
        record_headered_sheet_metadata(metadata_prefix, header_row_number)
        return build_parsed_workbook(sheet: sheet, sheet_name: sheet_name, header_row_number: header_row_number)
      end

      build_headerless_first_three_columns_workbook(sheet: sheet, sheet_name: sheet_name, metadata_prefix: metadata_prefix)
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

    def record_headered_sheet_metadata(metadata_prefix, header_row_number)
      metadata = {
        "#{metadata_prefix}_header_strategy" => "detected_header"
      }

      if metadata_prefix == "csv"
        metadata.merge!(
          "csv_header_row_number" => header_row_number,
          "csv_data_start_row" => header_row_number + 1
        )
      end

      merge_sheet_parse_metadata(metadata_prefix, metadata)
    end

    def record_headerless_sheet_metadata(metadata_prefix, candidate)
      metadata = {
        "#{metadata_prefix}_header_strategy" => "headerless_first_three_columns",
        "#{metadata_prefix}_headerless_data_start_row" => candidate.data_start_row,
        "#{metadata_prefix}_headerless_sample_row_count" => candidate.sample_row_count,
        "#{metadata_prefix}_headerless_confident_row_count" => candidate.confident_row_count,
        "#{metadata_prefix}_headerless_ignored_column_count" => candidate.ignored_column_count,
        "#{metadata_prefix}_headerless_detected_column_count" => candidate.detected_column_count
      }

      if metadata_prefix == "csv"
        metadata.merge!(
          "csv_data_start_row" => candidate.data_start_row,
          "csv_ignored_column_count" => candidate.ignored_column_count,
          "csv_detected_column_count" => candidate.detected_column_count
        )
      end

      merge_sheet_parse_metadata(metadata_prefix, metadata)
    end

    def merge_sheet_parse_metadata(metadata_prefix, metadata)
      if metadata_prefix == "csv"
        @csv_parse_metadata = (@csv_parse_metadata || {}).merge(metadata)
      else
        @xlsx_parse_metadata = (@xlsx_parse_metadata || {}).merge(metadata)
      end
    end

    def build_parsed_workbook(sheet:, sheet_name:, header_row_number:)
      last_column = sheet.last_column.to_i
      original_headers = row_values(sheet, header_row_number, last_column)
      source_rows = source_rows(sheet, header_row_number, last_column)
      mapped = map_headers(original_headers)
      split_amount_mapping = split_amount_mapping(mapped.fetch(:named_columns))
      named_columns = headered_named_columns(mapped.fetch(:named_columns), split_amount_mapping)
      detail_values_by_row = {}
      detail_header = nil

      rows = []
      source_rows.each do |(source_row_number, values)|
        named_values = named_columns.each_with_object({}) do |column, data|
          header = column.fetch(:header)
          data[header] = display_value(values[column.fetch(:index)], header: header)
        end
        named_values["Amount"] = split_amount_value(values, split_amount_mapping) if split_amount_mapping.present?

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

      processed_headers = headered_processed_headers(mapped.fetch(:headers), split_amount_mapping)
      processed_headers = append_detail_header(processed_headers, detail_header) if detail_header.present?
      processed_headers = ensure_required_columns(processed_headers)
      processed_headers = standard_transaction_header_order(processed_headers) if split_amount_mapping.present?

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

    def build_headerless_first_three_columns_workbook(sheet:, sheet_name:, metadata_prefix: "xlsx")
      candidate = headerless_first_three_columns_candidate(sheet)
      return if candidate.blank?

      processed_headers = ensure_required_columns(HEADERLESS_HEADERS.dup)
      rows = []

      (candidate.data_start_row..sheet.last_row.to_i).each do |row_number|
        values = row_values(sheet, row_number, HEADERLESS_REQUIRED_COLUMN_COUNT)
        next if values.all?(&:blank?)
        next unless headerless_transaction_row?(values)

        data = {
          "Date" => headerless_date_value(values[0]),
          "Amount" => headerless_amount_value(values[1]),
          "Description" => display_value(values[2])
        }
        processed_headers.each { |header| data[header] = "" unless data.key?(header) }

        rows << {
          position: rows.length + 1,
          source_row_number: row_number,
          data: data
        }
      end

      return if rows.blank?

      record_headerless_sheet_metadata(metadata_prefix, candidate)

      ParsedWorkbook.new(
        sheet_name: sheet_name,
        header_row_number: nil,
        original_headers: HEADERLESS_HEADERS.dup,
        processed_headers: processed_headers,
        rows: rows
      )
    end

    def headerless_first_three_columns_candidate(sheet)
      detected_column_count = sheet.last_column.to_i
      return if detected_column_count < HEADERLESS_REQUIRED_COLUMN_COUNT

      data_start_row = headerless_data_start_row(sheet)
      return if data_start_row.blank?

      sample_rows = headerless_sample_rows(sheet, data_start_row)
      sample_row_count = sample_rows.size
      confident_row_count = sample_rows.count { |(_, values)| headerless_transaction_row?(values) }
      return unless headerless_confident_sample?(sample_row_count, confident_row_count)

      HeaderlessCandidate.new(
        data_start_row: data_start_row,
        sample_row_count: sample_row_count,
        confident_row_count: confident_row_count,
        detected_column_count: detected_column_count,
        ignored_column_count: [ detected_column_count - HEADERLESS_REQUIRED_COLUMN_COUNT, 0 ].max
      )
    end

    def headerless_data_start_row(sheet)
      max_row = [ sheet.last_row.to_i, HEADER_SCAN_LIMIT ].min
      return if max_row.zero?

      (1..max_row).find do |row_number|
        values = row_values(sheet, row_number, HEADERLESS_REQUIRED_COLUMN_COUNT)
        headerless_transaction_row?(values)
      end
    end

    def headerless_sample_rows(sheet, data_start_row)
      rows = []

      (data_start_row..sheet.last_row.to_i).each do |row_number|
        values = row_values(sheet, row_number, HEADERLESS_REQUIRED_COLUMN_COUNT)
        next if values.all?(&:blank?)

        rows << [ row_number, values ]
        break if rows.size >= HEADERLESS_SAMPLE_LIMIT
      end

      rows
    end

    def headerless_confident_sample?(sample_row_count, confident_row_count)
      return false if sample_row_count.zero?
      return true if confident_row_count >= HEADERLESS_MIN_CONFIDENT_ROWS

      confident_row_count.to_f / sample_row_count >= HEADERLESS_MIN_CONFIDENT_RATIO
    end

    def headerless_transaction_row?(values)
      first_three = Array(values).first(HEADERLESS_REQUIRED_COLUMN_COUNT)
      return false if first_three.size < HEADERLESS_REQUIRED_COLUMN_COUNT

      headerless_date_like?(first_three[0]) &&
        headerless_amount_like?(first_three[1]) &&
        headerless_description_like?(first_three[2])
    end

    def headerless_date_like?(value)
      BasTdk::WorkbookValues.parse_date(value).present?
    end

    def headerless_amount_like?(value)
      BasTdk::WorkbookValues.parse_amount(value).present?
    end

    def headerless_description_like?(value)
      text = display_value(value)
      text.present? && text.match?(/[[:alpha:]]/)
    end

    def headerless_date_value(value)
      BasTdk::WorkbookValues.iso_date_value(value).presence || display_value(value, header: "Date")
    end

    def headerless_amount_value(value)
      decimal = BasTdk::WorkbookValues.parse_amount(value)
      return display_value(value, header: "Amount") if decimal.blank?

      BasTdk::WorkbookValues.fixed_decimal(decimal.round(2), 2)
    end

    def source_rows(sheet, header_row_number, last_column)
      return [] if sheet.last_row.to_i <= header_row_number

      ((header_row_number + 1)..sheet.last_row.to_i).map do |row_number|
        [ row_number, row_values(sheet, row_number, last_column) ]
      end
    end

    def split_amount_mapping(named_columns)
      return if named_columns.any? { |column| direct_amount_header?(column.fetch(:header)) }

      debit_columns = named_columns.select { |column| debit_amount_header?(column.fetch(:header)) }
      credit_columns = named_columns.select { |column| credit_amount_header?(column.fetch(:header)) }
      return if debit_columns.blank? && credit_columns.blank?

      source_columns = debit_columns + credit_columns
      {
        debit_columns: debit_columns,
        credit_columns: credit_columns,
        source_indices: source_columns.map { |column| column.fetch(:index) },
        source_headers: source_columns.map { |column| column.fetch(:header) }
      }
    end

    def headered_named_columns(named_columns, split_amount_mapping)
      return named_columns if split_amount_mapping.blank?

      split_indices = split_amount_mapping.fetch(:source_indices)
      named_columns.reject { |column| split_indices.include?(column.fetch(:index)) }
    end

    def headered_processed_headers(headers, split_amount_mapping)
      return headers if split_amount_mapping.blank?

      split_headers = split_amount_mapping.fetch(:source_headers)
      amount_inserted = false

      headers.each_with_object([]) do |header, processed|
        if split_headers.include?(header)
          unless amount_inserted
            processed << "Amount"
            amount_inserted = true
          end
        else
          processed << header
        end
      end
    end

    def split_amount_value(values, split_amount_mapping)
      credit = first_present_amount(values, split_amount_mapping.fetch(:credit_columns))
      debit = first_present_amount(values, split_amount_mapping.fetch(:debit_columns))
      decimal = if credit.present? && debit.present?
        credit.abs - debit.abs
      elsif credit.present?
        credit.abs
      elsif debit.present?
        -debit.abs
      end
      return "" if decimal.blank?

      BasTdk::WorkbookValues.fixed_decimal(decimal.round(2), 2)
    end

    def first_present_amount(values, columns)
      columns.each do |column|
        value = values[column.fetch(:index)]
        next if display_value(value).blank?

        decimal = BasTdk::WorkbookValues.parse_amount(value)
        return decimal if decimal.present?
      end

      nil
    end

    def direct_amount_header?(header)
      DIRECT_AMOUNT_ALIASES.include?(normalize_header(header))
    end

    def debit_amount_header?(header)
      DEBIT_AMOUNT_ALIASES.include?(normalize_header(header))
    end

    def credit_amount_header?(header)
      CREDIT_AMOUNT_ALIASES.include?(normalize_header(header))
    end

    def standard_transaction_header_order(headers)
      priority = [
        ->(header) { date_header?(header) },
        ->(header) { CATEGORY_ALIASES.include?(normalize_header(header)) },
        ->(header) { normalize_header(header) == "amount" },
        ->(header) { GST_ALIASES.include?(normalize_header(header)) },
        ->(header) { HEADER_ALIASES.fetch(:description).include?(normalize_header(header)) },
        ->(header) { normalize_header(header) == "balance" },
        ->(header) { normalize_header(header) == "details" }
      ]

      remaining_headers = headers.each_with_index.to_a
      ordered_headers = []

      priority.each do |matcher|
        matching_headers, other_headers = remaining_headers.partition { |(header, _index)| matcher.call(header) }
        ordered_headers.concat(matching_headers.map(&:first))
        remaining_headers = other_headers
      end

      ordered_headers.concat(remaining_headers.map(&:first))
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
      if header.present? && date_header?(header)
        date_value = BasTdk::WorkbookValues.iso_date_value(value)
        return date_value if date_value.present?
      end

      if header.present? && BasTdk::WorkbookValues.amount_header?(header)
        amount_value = BasTdk::WorkbookValues.parse_amount(value)
        return BasTdk::WorkbookValues.fixed_decimal(amount_value.round(2), 2) if amount_value.present?
      end

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
          processed_at: nil,
          metadata: workbook.metadata.merge(processing_metadata)
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
        processed_at: Time.current,
        metadata: workbook.metadata.merge(processing_metadata)
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
      workbook.metadata = workbook.metadata.merge("source_type" => source_type.to_s) if source_type.present?
      workbook.save!
    end

    def processing_metadata
      metadata = {}
      metadata["source_type"] = source_type.to_s if source_type.present?
      metadata.merge!(@xlsx_parse_metadata) if @xlsx_parse_metadata.present?
      metadata.merge!(@csv_parse_metadata) if @csv_parse_metadata.present?
      metadata.merge!(@pdf_parse_metadata) if @pdf_parse_metadata.present?
      metadata.merge!(@ocr_metadata) if @ocr_metadata.present?
      metadata
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
