module BasQueries
  class EmailDraftBuilder
    Result = Data.define(:subject, :body, :queries, :groups, :recipient_email, :client_name, :period_label)
    Group = Data.define(:key, :title, :instruction, :queries)

    DEFAULT_SECTION = {
      key: "other",
      title: "Other items to confirm",
      instruction: "Please confirm the following item or send through any supporting details."
    }.freeze

    SECTION_DEFINITIONS = {
      "missing_invoice" => {
        key: "missing_documents",
        title: "Missing invoices or receipts",
        instruction: "Please provide the invoice or receipt for the following transaction."
      },
      "missing_receipt" => {
        key: "missing_documents",
        title: "Missing invoices or receipts",
        instruction: "Please provide the invoice or receipt for the following transaction."
      },
      "supporting_document_missing" => {
        key: "missing_documents",
        title: "Missing invoices or receipts",
        instruction: "Please provide the invoice or receipt for the following transaction."
      },
      "unmatched_bank_transaction" => {
        key: "bank_transactions",
        title: "Bank transactions to confirm",
        instruction: "Please confirm what the following bank transaction relates to and provide supporting documents if available."
      },
      "unmatched_invoice" => {
        key: "invoice_payment_status",
        title: "Invoices to confirm payment status",
        instruction: "Please confirm whether the following invoice was paid during the BAS period and how it was paid."
      },
      "amount_mismatch" => {
        key: "amount_differences",
        title: "Amount differences to confirm",
        instruction: "The amount in the invoice and bank transaction appear different. Please confirm the correct amount or provide supporting documents."
      },
      "gst_treatment_unclear" => {
        key: "gst_treatment",
        title: "GST treatment to confirm",
        instruction: "Please confirm whether GST applies to the following item, or provide the tax invoice if available."
      },
      "unreviewed_gst_code" => {
        key: "gst_treatment",
        title: "GST treatment to confirm",
        instruction: "Please confirm whether GST applies to the following item, or provide the tax invoice if available."
      },
      "invoice_direction_unclear" => {
        key: "invoice_type",
        title: "Invoice type to confirm",
        instruction: "Please confirm whether the following invoice is a sales invoice or supplier invoice."
      },
      "cash_transaction_direction_unclear" => {
        key: "cash_transactions",
        title: "Cash transactions to confirm",
        instruction: "Please confirm whether the following cash transaction is cash received or cash paid, and provide supporting documents if available."
      },
      "cash_transaction_unclear" => {
        key: "cash_transactions",
        title: "Cash transactions to confirm",
        instruction: "Please confirm whether the following cash transaction is cash received or cash paid, and provide supporting documents if available."
      },
      "payroll_unclear" => {
        key: "payroll",
        title: "Payroll information required",
        instruction: "Please provide the payroll summary/STP report for the BAS period."
      },
      "import_error" => {
        key: "spreadsheet_rows",
        title: "Spreadsheet rows to check",
        instruction: "Some rows in the uploaded spreadsheet could not be imported clearly. Please check and resend the file or confirm the details."
      },
      "private_use_unclear" => {
        key: "business_use",
        title: "Business use to confirm",
        instruction: "Please confirm the business use for the following item."
      },
      "possible_duplicate" => {
        key: "possible_duplicates",
        title: "Possible duplicate items to confirm",
        instruction: "Please confirm whether the following item has already been provided or should be included once."
      }
    }.freeze

    def initialize(bas_job:)
      @bas_job = bas_job
    end

    def call
      Result.new(
        subject: subject,
        body: body,
        queries: queries,
        groups: groups,
        recipient_email: client.contact_email.presence,
        client_name: client.display_name,
        period_label: period_label
      )
    end

    private

    attr_reader :bas_job

    def client
      bas_job.bas_client
    end

    def period_label
      bas_job.period_label
    end

    def subject
      "BAS information required - #{client.display_name} - #{period_label}"
    end

    def body
      lines = [
        greeting,
        "",
        "We are preparing your BAS for #{period_label} and need a few items clarified before we can finalise it."
      ]

      if queries.any?
        lines += [
          "",
          "Could you please send through the following documents/details?",
          ""
        ]
        lines += grouped_query_lines
        lines += [
          "",
          "If any item does not apply, please let us know."
        ]
      else
        lines += [
          "",
          "There are currently no open client queries for this BAS job."
        ]
      end

      lines += [
        "",
        "Kind regards,",
        "TDK Group"
      ]

      lines.join("\n")
    end

    def greeting
      return "Hi #{sanitize_text(client.contact_name)}," if client.contact_name.present?

      "Hi,"
    end

    def grouped_query_lines
      groups.flat_map.with_index do |group, index|
        lines = []
        lines << "" if index.positive?
        lines << group.title
        lines << group.instruction
        lines += group.queries.flat_map.with_index(1) { |query, number| query_lines(query, number, group.instruction) }
        lines
      end
    end

    def query_lines(query, number, instruction)
      lines = [
        "#{number}. #{sanitize_text(query.display_title)}"
      ]

      details = sanitize_text(query.details)
      lines << "   Details: #{details}" if details.present?

      related_summary = source_summary_for(query)
      lines << "   Related: #{related_summary}" if related_summary.present?
      lines << "   Requested action: #{instruction}"
      lines
    end

    def groups
      @groups ||= queries.group_by { |query| section_for(query).fetch(:key) }.map do |_key, group_queries|
        section = section_for(group_queries.first)
        Group.new(
          key: section.fetch(:key),
          title: section.fetch(:title),
          instruction: section.fetch(:instruction),
          queries: group_queries
        )
      end
    end

    def queries
      @queries ||= bas_job.queries.open_items.order(:query_type, :title, :id).to_a
    end

    def section_for(query)
      SECTION_DEFINITIONS.fetch(query.query_type, DEFAULT_SECTION)
    end

    def source_summary_for(query)
      source = query.source_record
      return query.source_summary if source.blank?

      parts = case source
      when BasBankTransaction
        [
          formatted_date("Date", source.transaction_date),
          safe_part("Description", source.description),
          formatted_money("Amount", source.amount)
        ]
      when BasInvoice
        [
          safe_part("Invoice", source.invoice_number),
          formatted_date("Date", source.issue_date),
          safe_part("Party", source.party_name),
          formatted_money("Amount", source.total_amount)
        ]
      when BasCashTransaction
        [
          formatted_date("Date", source.transaction_date),
          safe_part("Party", source.party_name),
          safe_part("Description", source.description),
          formatted_money("Amount", source.total_amount)
        ]
      when BasPayrollSummary
        [
          formatted_money("Gross wages", source.gross_wages),
          formatted_money("PAYG withheld", source.payg_withheld)
        ]
      when BasImportRun
        [
          safe_part("Import type", source.import_type&.humanize),
          safe_part("Document", source.bas_document&.title)
        ]
      else
        []
      end

      parts.compact.join("; ").presence
    end

    def safe_part(label, value)
      text = sanitize_text(value)
      "#{label}: #{text}" if text.present?
    end

    def formatted_date(label, value)
      "#{label}: #{value.to_fs(:db)}" if value.present?
    end

    def formatted_money(label, value)
      return nil if value.blank?

      amount = BigDecimal(value.to_s).round(2)
      sign = amount.negative? ? "-" : ""
      integer_part, decimal_part = amount.abs.to_s("F").split(".", 2)
      "#{label}: #{sign}$#{integer_part}.#{decimal_part.to_s.ljust(2, '0')[0, 2]}"
    end

    def sanitize_text(value)
      value.to_s.squish.truncate(220, separator: " ").presence
    end
  end
end
