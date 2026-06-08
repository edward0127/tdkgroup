module BasMatching
  class Matcher
    class LockedJobError < StandardError; end

    def initialize(bas_job:, actor_username:)
      @bas_job = bas_job
      @actor_username = actor_username
      @created_count = 0
    end

    def call
      raise LockedJobError, "locked BAS jobs cannot run matching" if bas_job.locked?

      bas_job.update!(status: "matching")

      CandidateFinder.new(bas_job: bas_job).candidates.each do |candidate|
        create_proposed_match(candidate)
      end

      update_job_status
      create_audit_event("bas_matching_run", created_count: created_count)
      created_count
    end

    private

    attr_reader :bas_job, :actor_username, :created_count

    def create_proposed_match(candidate)
      return if duplicate_candidate?(candidate)

      scored = score_candidate(candidate)
      match = BasMatch.create!(
        bas_job: bas_job,
        match_type: candidate.match_type,
        status: "proposed",
        confidence: scored.confidence,
        matched_amount: candidate.matched_amount,
        explanation: scored.explanation,
        created_by_rule: candidate.rule
      )

      candidate.invoices.each do |invoice|
        match.items.create!(matchable: invoice, amount: invoice.total_amount)
      end
      payment_amount = candidate.payment_record.respond_to?(:amount) ? candidate.payment_record.amount : candidate.payment_record.total_amount
      match.items.create!(matchable: candidate.payment_record, amount: payment_amount)

      @created_count += 1
      create_audit_event("bas_match_proposed", bas_match_id: match.id, rule: candidate.rule)
    end

    def score_candidate(candidate)
      if candidate.confidence.present? && candidate.explanation.present?
        return BasMatching::ConfidenceScorer::Result.new(
          confidence: candidate.confidence,
          explanation: candidate.explanation
        )
      end

      if candidate.invoices.one?
        ConfidenceScorer.score(invoice: candidate.invoices.first, payment_record: candidate.payment_record)
      else
        BasMatching::ConfidenceScorer::Result.new(
          confidence: 75,
          explanation: "invoice group total matches payment amount"
        )
      end
    end

    def duplicate_candidate?(candidate)
      candidate_ids = (candidate.invoices + [ candidate.payment_record ]).map { |record| "#{record.class.name}:#{record.id}" }.sort

      bas_job.matches.where(match_type: candidate.match_type).where.not(status: "rejected").includes(:items).any? do |match|
        match.items.map { |item| "#{item.matchable_type}:#{item.matchable_id}" }.sort == candidate_ids
      end
    end

    def update_job_status
      if bas_job.queries.open_items.exists?
        bas_job.update!(status: "queries_open")
      elsif bas_job.matches.proposed.exists?
        bas_job.update!(status: "matching")
      else
        bas_job.update!(status: "review_ready")
      end
    end

    def create_audit_event(event_type, metadata)
      BasAuditEvent.create!(
        bas_job: bas_job,
        event_type: event_type,
        actor_username: actor_username,
        metadata: metadata.merge(status: bas_job.status)
      )
    end
  end
end
