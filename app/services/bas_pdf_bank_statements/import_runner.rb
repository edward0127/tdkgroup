module BasPdfBankStatements
  class ImportRunner
    class ImportError < StandardError; end

    Result = Data.define(:conversion_run, :import_run, :imported_count)

    def initialize(conversion_run:, actor_username:)
      @conversion_run = conversion_run
      @bas_job = conversion_run.bas_job
      @actor_username = actor_username
    end

    def call
      raise ImportError, "Locked BAS jobs cannot import PDF bank statement conversions." if bas_job.locked?
      raise ImportError, "Only previewed PDF bank statement conversions can be imported." unless conversion_run.status == "previewed"
      raise ImportError, "No preview rows are available to import." if importable_rows.blank?
      raise ImportError, "Resolve PDF conversion row errors before importing." if conversion_run.row_errors.present?

      import_run = BasImportRun.create!(
        bas_job: bas_job,
        bas_document: conversion_run.source_bas_document,
        import_type: "bank_statement",
        status: "pending",
        column_mapping: column_mapping,
        preview_rows: reader.rows.first(BasImports::Previewer::PREVIEW_LIMIT),
        row_count: importable_rows.size
      )

      BasImports::Importer.new(
        import_run: import_run,
        column_mapping: column_mapping,
        actor_username: actor_username,
        file_reader: reader
      ).call

      conversion_run.update!(
        bas_import_run: import_run,
        status: import_run.status == "imported" ? "imported" : "failed",
        converted_count: import_run.imported_count,
        error_count: import_run.error_count,
        row_errors: import_run.import_errors,
        imported_at: Time.current,
        imported_by: actor_username
      )
      create_audit_event("bas_pdf_bank_statement_imported", import_run)

      Result.new(conversion_run: conversion_run, import_run: import_run, imported_count: import_run.imported_count)
    end

    private

    attr_reader :conversion_run, :bas_job, :actor_username

    def importable_rows
      @importable_rows ||= Array(conversion_run.preview_rows)
    end

    def reader
      @reader ||= PreviewRowsReader.new(importable_rows)
    end

    def column_mapping
      @column_mapping ||= BasImports::ColumnNormalizer.suggest_mapping(CsvBuilder::HEADERS, "bank_statement")
    end

    def create_audit_event(event_type, import_run)
      BasAuditEvent.create!(
        bas_job: bas_job,
        auditable: conversion_run,
        event_type: event_type,
        actor_username: actor_username,
        metadata: {
          source_bas_document_id: conversion_run.source_bas_document_id,
          bas_document_conversion_run_id: conversion_run.id,
          bas_import_run_id: import_run.id,
          row_count: conversion_run.row_count,
          imported_count: import_run.imported_count,
          error_count: conversion_run.error_count,
          status: conversion_run.status,
          detected_bank_name: conversion_run.detected_bank_name
        }.compact
      )
    end

    class PreviewRowsReader
      attr_reader :rows

      def initialize(preview_rows)
        @preview_rows = preview_rows
        @rows = preview_rows.map.with_index(2) do |row, row_number|
          {
            "row_number" => row_number,
            "data" => CsvBuilder::HEADERS.to_h do |header|
              [ header, row[CsvBuilder::FIELD_BY_HEADER.fetch(header)].to_s ]
            end
          }
        end
      end

      def read(_document)
        BasImports::FileReader::Result.new(headers: CsvBuilder::HEADERS, rows: rows)
      end
    end
  end
end
