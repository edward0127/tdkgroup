module BasReports
  class SnapshotBuilder
    class LockedJobError < StandardError; end
    class ApprovalBlockedError < StandardError
      attr_reader :blockers

      def initialize(blockers)
        @blockers = blockers
        super(blockers.to_sentence)
      end
    end

    def initialize(bas_job:, actor_username:)
      @bas_job = bas_job
      @actor_username = actor_username
    end

    def create_draft!(notes: nil)
      raise LockedJobError, "locked BAS jobs cannot be recalculated" if bas_job.locked?

      calculation = BasReports::Calculator.new(bas_job: bas_job).call
      blockers = BasReports::ApprovalValidator.new(
        bas_job: bas_job,
        calculation_result: calculation
      ).call

      snapshot = bas_job.report_snapshots.create!(
        status: "draft",
        totals: calculation.totals,
        validation_errors: blockers,
        generated_at: Time.current,
        generated_by: actor_username,
        notes: notes
      )

      bas_job.update!(status: job_status_for(blockers))
      create_audit_event("bas_calculation_generated", snapshot, validation_error_count: blockers.size)
      create_audit_event("bas_report_snapshot_generated", snapshot, validation_error_count: blockers.size)
      snapshot
    end

    def approve!(snapshot:)
      raise LockedJobError, "locked BAS jobs cannot approve report snapshots" if bas_job.locked?

      blockers = BasReports::ApprovalValidator.new(
        bas_job: bas_job,
        snapshot: snapshot,
        require_snapshot: true
      ).call
      raise ApprovalBlockedError, blockers if blockers.any?

      now = Time.current
      snapshot.update!(
        status: "final",
        approved_at: now,
        approved_by: actor_username
      )
      bas_job.update!(
        status: "approved",
        approved_at: now,
        approved_by: actor_username
      )

      create_audit_event("bas_report_approved", snapshot)
      snapshot
    end

    def lock!(snapshot:)
      raise LockedJobError, "BAS job must be approved before locking" unless bas_job.status == "approved"
      raise LockedJobError, "only final report snapshots can be locked" unless snapshot.final?

      now = Time.current
      snapshot.update!(locked_at: now, locked_by: actor_username)
      bas_job.update!(
        status: "locked",
        locked_at: now,
        locked_by: actor_username
      )

      create_audit_event("bas_job_locked", snapshot)
      snapshot
    end

    private

    attr_reader :bas_job, :actor_username

    def job_status_for(blockers)
      return "report_ready" if blockers.blank?
      return "queries_open" if bas_job.queries.open_items.exists?

      "review_ready"
    end

    def create_audit_event(event_type, snapshot, metadata = {})
      BasAuditEvent.create!(
        bas_job: bas_job,
        auditable: snapshot,
        event_type: event_type,
        actor_username: actor_username,
        metadata: metadata.merge(
          bas_report_snapshot_id: snapshot.id,
          status: snapshot.status,
          totals_keys: snapshot.totals.keys
        )
      )
    end
  end
end
