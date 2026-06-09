module Admin
  module Bas
    module ReportSnapshotsHelper
      def bas_breakdown_source_link(job, row)
        label = row["source_label"].presence || "#{row['source_type_label']} ##{row['source_id']}"

        case row["source"]
        when "BasInvoice"
          link_to label, admin_bas_job_invoice_path(job, row["source_id"]), class: "text-link"
        when "BasBankTransaction"
          link_to label, admin_bas_job_bank_transaction_path(job, row["source_id"]), class: "text-link"
        when "BasCashTransaction"
          link_to label, admin_bas_job_cash_transaction_path(job, row["source_id"]), class: "text-link"
        else
          label
        end
      end

      def bas_breakdown_match_link(job, match_id)
        return nil if match_id.blank?

        link_to "Match ##{match_id}", admin_bas_job_match_path(job, match_id), class: "text-link"
      end

      def bas_breakdown_query_link(job, query)
        return nil if query["id"].blank?

        link_to "Query ##{query['id']}", admin_bas_job_query_path(job, query["id"]), class: "text-link"
      end

      def bas_breakdown_linked_records(job, row)
        linked_records = Array(row["linked_records"])
        return "No accepted match" if linked_records.blank?

        safe_join(
          linked_records.map do |record|
            safe_join([
              bas_breakdown_source_link(job, record),
              " via ",
              bas_breakdown_match_link(job, record["match_id"])
            ].compact)
          end,
          tag.br
        )
      end

      def bas_breakdown_related_queries(job, row)
        queries = Array(row["related_queries"])
        return "None" if queries.blank?

        safe_join(
          queries.map do |query|
            safe_join([
              bas_breakdown_query_link(job, query),
              " ",
              content_tag(:span, query["status"].to_s.humanize, class: "admin-muted")
            ].compact)
          end,
          tag.br
        )
      end
    end
  end
end
