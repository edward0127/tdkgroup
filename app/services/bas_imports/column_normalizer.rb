module BasImports
  class ColumnNormalizer
    SYNONYMS = {
      "transaction_date" => [
        "date", "transaction date", "trans date", "transactiondate", "posted date", "posting date"
      ],
      "description" => [
        "description", "narration", "merchant", "memo", "transaction description"
      ],
      "details" => [ "details", "detail", "particulars", "transaction details" ],
      "reference" => [ "reference", "ref", "reference number", "transaction id" ],
      "debit" => [ "debit", "debits", "withdrawal", "withdrawals", "money out", "payment" ],
      "credit" => [ "credit", "credits", "deposit", "deposits", "money in", "receipt" ],
      "amount" => [ "amount", "transaction amount", "value" ],
      "balance" => [ "balance", "running balance", "closing balance" ],
      "bank_account_name" => [ "account", "account name", "bank account", "bank account name" ],
      "direction" => [ "direction", "type", "invoice type", "sale purchase", "receipt payment" ],
      "invoice_number" => [ "invoice number", "invoice no", "invoice", "bill number", "reference" ],
      "issue_date" => [ "issue date", "invoice date", "date" ],
      "paid_date" => [ "paid date", "payment date", "date paid" ],
      "party_name" => [ "party", "party name", "customer", "supplier", "contact", "name" ],
      "total_amount" => [ "total", "total amount", "amount", "gross", "gross amount" ],
      "gst_amount" => [ "gst", "gst amount", "tax", "tax amount" ],
      "net_amount" => [ "net", "net amount", "subtotal", "exclusive amount" ],
      "payment_method" => [ "payment method", "method", "paid by" ],
      "gst_code" => [ "gst code", "tax code", "code", "tax type" ],
      "gross_wages" => [ "gross wages", "gross", "wages", "gross pay" ],
      "payg_withheld" => [ "payg", "payg withheld", "withheld", "tax withheld", "paye" ],
      "super_amount" => [ "super", "superannuation", "super amount", "sgc" ]
    }.freeze

    IMPORT_FIELDS = {
      "bank_statement" => %w[
        transaction_date description details reference debit credit amount balance bank_account_name
      ],
      "invoice_summary" => %w[
        direction invoice_number issue_date paid_date party_name description total_amount gst_amount
        net_amount payment_method gst_code
      ],
      "cash_transactions" => %w[
        transaction_date direction party_name description total_amount gst_amount gst_code
      ],
      "payroll_summary" => %w[
        gross_wages payg_withheld super_amount
      ]
    }.freeze

    def self.normalize(value)
      new.normalize(value)
    end

    def self.suggest_mapping(headers, import_type)
      new.suggest_mapping(headers, import_type)
    end

    def normalize(value)
      value.to_s
        .delete_prefix("\uFEFF")
        .downcase
        .strip
        .gsub(/[^a-z0-9]+/, " ")
        .squeeze(" ")
        .strip
    end

    def suggest_mapping(headers, import_type)
      available_headers = Array(headers).compact_blank
      normalized_headers = available_headers.to_h { |header| [ normalize(header), header ] }

      IMPORT_FIELDS.fetch(import_type.to_s, []).each_with_object({}) do |field, mapping|
        candidate = ([ field.tr("_", " ") ] + SYNONYMS.fetch(field, [])).map { |value| normalize(value) }
        matched_normalized_header = candidate.find { |synonym| normalized_headers.key?(synonym) }
        mapping[field] = normalized_headers[matched_normalized_header] if matched_normalized_header.present?
      end
    end
  end
end
