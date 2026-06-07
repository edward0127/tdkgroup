module BasAi
  class SuggestionBuilder
    def initialize(run:, validated_suggestions:, actor_username:)
      @run = run
      @validated_suggestions = validated_suggestions
      @actor_username = actor_username
      @created_suggestions = []
    end

    def call
      validated_suggestions.each do |attributes|
        suggestion = run.ai_suggestions.create!(
          bas_job: run.bas_job,
          suggestion_type: attributes.fetch("suggestion_type"),
          status: "proposed",
          confidence: attributes["confidence"],
          source_type: attributes["source_type"],
          source_id: attributes["source_id"],
          suggested_data: attributes.fetch("suggested_data"),
          explanation: attributes["explanation"]
        )
        created_suggestions << suggestion
        create_audit_event(suggestion)
      end

      created_suggestions
    end

    private

    attr_reader :run, :validated_suggestions, :actor_username, :created_suggestions

    def create_audit_event(suggestion)
      BasAuditEvent.create!(
        bas_job: run.bas_job,
        auditable: suggestion,
        event_type: "bas_ai_suggestion_created",
        actor_username: actor_username,
        metadata: {
          bas_ai_extraction_run_id: run.id,
          bas_ai_suggestion_id: suggestion.id,
          suggestion_type: suggestion.suggestion_type,
          status: suggestion.status,
          confidence: suggestion.confidence&.to_s,
          provider: run.provider,
          model_name: run.ai_model_name
        }
      )
    end
  end
end
