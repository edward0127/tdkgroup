module BasQueries
  class SourceResolutionSync
    RESOLUTION_NOTE = "Automatically resolved because the source item was ignored/excluded/matched.".freeze

    def initialize(source:, actor_username:)
      @source = source
      @actor_username = actor_username
      @resolved_count = 0
    end

    def call
      return 0 unless source_resolved?

      related_queries.find_each do |query|
        query.update!(
          status: "resolved",
          resolution_notes: RESOLUTION_NOTE,
          updated_by: actor_username
        )
        create_audit_event(query)
        @resolved_count += 1
      end

      resolved_count
    end

    private

    attr_reader :source, :actor_username, :resolved_count

    def related_queries
      BasQuery.open_items
        .where(
          bas_job_id: source.bas_job_id,
          source_type: source.class.name,
          source_id: source.id,
          auto_generated: true,
          resolution_notes: [ nil, "" ]
        )
    end

    def source_resolved?
      return true if source.respond_to?(:status) && source.status.in?(%w[ignored matched])
      return true if source.respond_to?(:gst_code) && source.gst_code == "bas_excluded"
      return true if source.respond_to?(:matches) && source.matches.accepted.exists?

      false
    end

    def create_audit_event(query)
      BasAuditEvent.create!(
        bas_job: query.bas_job,
        auditable: query,
        event_type: "bas_query_auto_resolved",
        actor_username: actor_username,
        metadata: {
          bas_query_id: query.id,
          source_type: source.class.name,
          source_id: source.id,
          source_status: source.respond_to?(:status) ? source.status : nil,
          source_gst_code: source.respond_to?(:gst_code) ? source.gst_code : nil
        }
      )
    end
  end
end
