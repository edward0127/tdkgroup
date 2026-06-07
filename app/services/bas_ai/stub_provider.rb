module BasAi
  class StubProvider < Provider
    def review_job(job_summary)
      Result.new(
        ok?: true,
        summary: "Synthetic AI review created for admin testing.",
        suggestions: [
          summary_suggestion(job_summary),
          query_suggestion(job_summary),
          gst_code_suggestion(job_summary)
        ].compact,
        error_message: nil
      )
    end

    def extract_document(document_summary)
      Result.new(
        ok?: true,
        summary: "Synthetic document extraction suggestion created.",
        suggestions: [
          {
            "suggestion_type" => "invoice_extraction",
            "source_type" => "BasDocument",
            "source_id" => document_summary.fetch("bas_document_id"),
            "confidence" => 82,
            "explanation" => "Synthetic extraction for admin review.",
            "suggested_data" => {
              "document_type" => "supplier_invoice",
              "invoice_number" => "SYN-AI-001",
              "issue_date" => document_summary.fetch("period_start", nil),
              "supplier_or_customer_name" => "Synthetic AI Supplier",
              "abn_if_found" => "",
              "total_amount" => "110.00",
              "gst_amount" => "10.00",
              "currency" => "AUD",
              "suggested_gst_code" => "taxable",
              "payment_method" => "unknown",
              "confidence" => 82,
              "missing_fields" => [],
              "needs_review" => true,
              "explanation" => "Synthetic extraction requires accountant review."
            }
          }
        ],
        error_message: nil
      )
    end

    private

    def summary_suggestion(job_summary)
      {
        "suggestion_type" => "summary",
        "confidence" => 75,
        "explanation" => "Synthetic job review summary.",
        "suggested_data" => {
          "summary" => "Synthetic BAS job review summary for admin testing.",
          "unresolved_risks" => job_summary.fetch("open_query_count", 0).to_i.positive? ? [ "Open query items remain." ] : [],
          "suggested_admin_actions" => [ "Review imported records before approval." ],
          "confidence" => 75
        }
      }
    end

    def query_suggestion(job_summary)
      return nil unless job_summary.fetch("unmatched_bank_transaction_count", 0).to_i.positive?

      {
        "suggestion_type" => "query",
        "confidence" => 70,
        "explanation" => "Synthetic query suggestion for unmatched bank transactions.",
        "suggested_data" => {
          "query_type" => "unmatched_bank_transaction",
          "title" => "Review unmatched bank transactions",
          "details" => "Synthetic AI suggestion: unmatched bank transactions need admin review.",
          "related_source_type" => "BasJob",
          "related_source_id" => job_summary.fetch("bas_job_id"),
          "confidence" => 70
        }
      }
    end

    def gst_code_suggestion(job_summary)
      invoice = Array(job_summary["invoices"]).find { |item| item["gst_code"].in?(%w[unknown needs_review]) }
      return nil if invoice.blank?

      {
        "suggestion_type" => "gst_code",
        "source_type" => "BasInvoice",
        "source_id" => invoice.fetch("id"),
        "confidence" => 68,
        "explanation" => "Synthetic GST code suggestion requires review.",
        "suggested_data" => {
          "source_type" => "BasInvoice",
          "source_id" => invoice.fetch("id"),
          "suggested_gst_code" => "needs_review",
          "confidence" => 68,
          "needs_review" => true,
          "explanation" => "Synthetic GST code suggestion requires accountant review."
        }
      }
    end
  end
end
