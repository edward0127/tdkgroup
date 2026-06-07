module Admin
  module Bas
    class ClientsController < Admin::BaseController
      before_action :set_client, only: [ :show, :edit, :update ]

      def index
        @clients = BasClient.ordered
      end

      def show
        @jobs = @client.bas_jobs.includes(:documents, :queries).order(period_end: :desc, id: :desc)
      end

      def new
        @client = BasClient.new
      end

      def create
        @client = BasClient.new(client_params)

        if @client.save
          BasAuditEvent.create!(
            auditable: @client,
            event_type: "bas_client_created",
            actor_username: current_admin_identifier,
            metadata: { bas_client_id: @client.id }
          )
          redirect_to admin_bas_client_path(@client), notice: "BAS client created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        @client.assign_attributes(client_params)
        changed_fields = @client.changed - %w[notes]

        if @client.save
          BasAuditEvent.create!(
            auditable: @client,
            event_type: "bas_client_updated",
            actor_username: current_admin_identifier,
            metadata: { bas_client_id: @client.id, changed_fields: changed_fields }
          )
          redirect_to admin_bas_client_path(@client), notice: "BAS client updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_client
        @client = BasClient.find(params[:id])
      end

      def client_params
        params.require(:bas_client).permit(
          :legal_name,
          :trading_name,
          :abn,
          :contact_name,
          :contact_email,
          :contact_phone,
          :default_gst_basis,
          :reporting_frequency,
          :default_reporting_method,
          :notes,
          :archived
        )
      end
    end
  end
end
