module BasImports
  class Importer
    class LockedJobError < StandardError; end
    class RowError < StandardError
      attr_reader :messages

      def initialize(messages)
        @messages = Array(messages)
        super(@messages.join(", "))
      end
    end

    REQUIRED_MAPPING_GROUPS = {
      "bank_statement" => [
        [ "transaction_date" ],
        %w[description details reference],
        %w[amount debit credit]
      ],
      "invoice_summary" => [
        [ "total_amount" ],
        %w[party_name invoice_number description]
      ],
      "cash_transactions" => [
        [ "transaction_date" ],
        [ "total_amount" ]
      ],
      "payroll_summary" => [
        %w[gross_wages payg_withheld super_amount]
      ]
    }.freeze

    def initialize(import_run:, column_mapping:, actor_username:, file_reader: BasImports::FileReader)
      @import_run = import_run
      @bas_job = import_run.bas_job
      @column_mapping = normalize_mapping(column_mapping)
      @actor_username = actor_username
      @file_reader = file_reader
    end

    def call
      raise LockedJobError, "locked BAS jobs cannot be imported" if bas_job.locked?

      create_audit_event("bas_import_started")
      bas_job.update!(status: "importing") unless bas_job.status.in?(%w[locked cancelled])

      result = file_reader.read(import_run.bas_document)
      mapping_errors = mapping_errors_for(column_mapping)

      if mapping_errors.any?
        finalize_import(status: "failed", rows: result.rows, imported_count: 0, row_errors: mapping_errors)
        return import_run
      end

      imported_count = 0
      row_errors = []

      result.rows.each do |row|
        import_row(row)
        imported_count += 1
      rescue RowError => e
        row_errors << { "row_number" => row.fetch("row_number"), "message" => e.messages.join(", ") }
      rescue ActiveRecord::RecordInvalid => e
        row_errors << { "row_number" => row.fetch("row_number"), "message" => e.record.errors.full_messages.to_sentence }
      end

      status = imported_count.positive? ? "imported" : "failed"
      finalize_import(status: status, rows: result.rows, imported_count: imported_count, row_errors: row_errors)
      import_run
    rescue FileReader::ReadError, FileReader::UnsupportedFileError => e
      finalize_import(status: "failed", rows: [], imported_count: 0, row_errors: [
        { "row_number" => nil, "message" => e.message }
      ])
      import_run
    end

    private

    attr_reader :import_run, :bas_job, :column_mapping, :actor_username, :file_reader

    def normalize_mapping(mapping)
      hash =
        if mapping.blank?
          {}
        elsif mapping.respond_to?(:to_unsafe_h)
          mapping.to_unsafe_h
        else
          mapping.to_h
        end
      hash.transform_keys(&:to_s).transform_values { |value| value.to_s.presence }
    end

    def mapping_errors_for(mapping)
      REQUIRED_MAPPING_GROUPS.fetch(import_run.import_type).filter_map do |group|
        next if group.any? { |field| mapping[field].present? }

        { "row_number" => nil, "message" => "Missing mapping for #{group.join(' or ')}" }
      end
    end

    def import_row(row)
      data = row.fetch("data")

      case import_run.import_type
      when "bank_statement"
        BasBankTransaction.create!(bank_transaction_attributes(row, data))
      when "invoice_summary"
        BasInvoice.create!(invoice_attributes(row, data))
      when "cash_transactions"
        BasCashTransaction.create!(cash_transaction_attributes(row, data))
      when "payroll_summary"
        BasPayrollSummary.create!(payroll_summary_attributes(row, data))
      else
        raise RowError, "Unsupported import type"
      end
    end

    def bank_transaction_attributes(row, data)
      transaction_date = required_date(data, "transaction_date")
      debit = amount(data, "debit")
      credit = amount(data, "credit")
      mapped_amount = amount(data, "amount")
      derived_amount = mapped_amount || derived_bank_amount(debit, credit)
      raise RowError, "amount or debit/credit is required" if derived_amount.nil?

      description = text(data, "description")
      details = text(data, "details")
      reference = text(data, "reference")
      raise RowError, "description, details or reference is required" if [ description, details, reference ].all?(&:blank?)

      {
        bas_job: bas_job,
        bas_import_run: import_run,
        transaction_date: transaction_date,
        description: description,
        details: details,
        reference: reference,
        debit: debit,
        credit: credit,
        amount: derived_amount,
        balance: amount(data, "balance"),
        bank_account_name: text(data, "bank_account_name"),
        source_row_number: row.fetch("row_number")
      }
    end

    def invoice_attributes(row, data)
      total_amount = required_amount(data, "total_amount")
      gst_amount = amount(data, "gst_amount")
      net_amount = amount(data, "net_amount")
      net_amount ||= total_amount - gst_amount if total_amount.present? && gst_amount.present?

      invoice_number = text(data, "invoice_number")
      party_name = text(data, "party_name")
      description = text(data, "description")
      raise RowError, "party name, invoice number or description is required" if [ party_name, invoice_number, description ].all?(&:blank?)

      {
        bas_job: bas_job,
        bas_import_run: import_run,
        direction: normalized_allowed_value(text(data, "direction"), BasInvoice::DIRECTION_VALUES, "unknown", sale_synonyms: true),
        invoice_number: invoice_number,
        issue_date: date(data, "issue_date"),
        paid_date: date(data, "paid_date"),
        party_name: party_name,
        description: description,
        total_amount: total_amount,
        gst_amount: gst_amount,
        net_amount: net_amount,
        payment_method: normalized_allowed_value(text(data, "payment_method"), BasInvoice::PAYMENT_METHOD_VALUES, "unknown"),
        gst_code: normalized_allowed_value(text(data, "gst_code"), BasInvoice::GST_CODE_VALUES, "unknown"),
        source_row_number: row.fetch("row_number")
      }
    end

    def cash_transaction_attributes(row, data)
      {
        bas_job: bas_job,
        bas_import_run: import_run,
        transaction_date: required_date(data, "transaction_date"),
        direction: normalized_allowed_value(text(data, "direction"), BasCashTransaction::DIRECTION_VALUES, "unknown", cash_synonyms: true),
        party_name: text(data, "party_name"),
        description: text(data, "description"),
        total_amount: required_amount(data, "total_amount"),
        gst_amount: amount(data, "gst_amount"),
        gst_code: normalized_allowed_value(text(data, "gst_code"), BasCashTransaction::GST_CODE_VALUES, "unknown"),
        source_row_number: row.fetch("row_number")
      }
    end

    def payroll_summary_attributes(row, data)
      {
        bas_job: bas_job,
        bas_import_run: import_run,
        gross_wages: amount(data, "gross_wages"),
        payg_withheld: amount(data, "payg_withheld"),
        super_amount: amount(data, "super_amount"),
        source_row_number: row.fetch("row_number")
      }
    end

    def derived_bank_amount(debit, credit)
      return nil if debit.nil? && credit.nil?

      credit_value = credit || BigDecimal("0")
      debit_value = debit || BigDecimal("0")
      credit_value.abs - debit_value.abs
    end

    def mapped_value(data, field)
      header = column_mapping[field.to_s]
      return nil if header.blank?

      data[header]
    end

    def text(data, field)
      mapped_value(data, field).to_s.strip.presence
    end

    def amount(data, field)
      AmountParser.parse!(mapped_value(data, field))
    rescue AmountParser::ParseError
      raise RowError, "#{field.humanize} is invalid"
    end

    def required_amount(data, field)
      parsed_amount = amount(data, field)
      raise RowError, "#{field.humanize} is required" if parsed_amount.nil?

      parsed_amount
    end

    def date(data, field)
      DateParser.parse!(mapped_value(data, field))
    rescue DateParser::ParseError
      raise RowError, "#{field.humanize} is invalid"
    end

    def required_date(data, field)
      parsed_date = date(data, field)
      raise RowError, "#{field.humanize} is required" if parsed_date.nil?

      parsed_date
    end

    def normalized_allowed_value(value, allowed_values, default, sale_synonyms: false, cash_synonyms: false)
      normalized = value.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      normalized = "sale" if sale_synonyms && normalized.in?(%w[sales income customer])
      normalized = "purchase" if sale_synonyms && normalized.in?(%w[purchases expense supplier bill])
      normalized = "cash_receipt" if cash_synonyms && normalized.in?(%w[receipt received income])
      normalized = "cash_payment" if cash_synonyms && normalized.in?(%w[payment paid expense])
      normalized = "no_gst" if normalized == "nogst"

      allowed_values.include?(normalized) ? normalized : default
    end

    def finalize_import(status:, rows:, imported_count:, row_errors:)
      import_run.column_mapping = column_mapping
      import_run.row_count = rows.size
      import_run.imported_count = imported_count
      import_run.error_count = row_errors.size
      import_run.import_errors = row_errors
      import_run.status = status
      import_run.imported_at = Time.current
      import_run.imported_by = actor_username
      import_run.save!

      import_run.bas_document.update!(
        processing_status: status == "imported" && row_errors.empty? ? "processed" : "needs_review"
      )

      bas_job.update!(status: "review_ready") if status == "imported" && !bas_job.locked?

      create_audit_event(status == "imported" ? "bas_import_completed" : "bas_import_failed")
    end

    def create_audit_event(event_type)
      BasAuditEvent.create!(
        bas_job: bas_job,
        auditable: import_run,
        event_type: event_type,
        actor_username: actor_username,
        metadata: {
          bas_import_run_id: import_run.id,
          bas_document_id: import_run.bas_document_id,
          import_type: import_run.import_type,
          status: import_run.status,
          row_count: import_run.row_count,
          imported_count: import_run.imported_count,
          error_count: import_run.error_count,
          filename: import_run.bas_document.safe_filename
        }
      )
    end
  end
end
