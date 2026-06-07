require "test_helper"

class BasImportsTest < ActiveSupport::TestCase
  test "amount parser parses currency strings as BigDecimal" do
    amount = BasImports::AmountParser.parse("$1,234.56")

    assert_instance_of BigDecimal, amount
    assert_equal BigDecimal("1234.56"), amount
    assert_equal BigDecimal("-123.45"), BasImports::AmountParser.parse("(123.45)")
    assert_equal BigDecimal("-123.45"), BasImports::AmountParser.parse("-123.45")
    assert_nil BasImports::AmountParser.parse("")
    assert_nil BasImports::AmountParser.parse(nil)
  end

  test "amount parser raises clear error for invalid amount" do
    error = assert_raises(BasImports::AmountParser::ParseError) do
      BasImports::AmountParser.parse!("not money")
    end

    assert_equal "invalid amount", error.message
  end

  test "date parser parses common AU dates and invalid dates safely" do
    assert_equal Date.new(2026, 1, 31), BasImports::DateParser.parse("31/01/2026")
    assert_equal Date.new(2026, 1, 1), BasImports::DateParser.parse("1/1/2026")
    assert_equal Date.new(2026, 1, 31), BasImports::DateParser.parse("2026-01-31")
    assert_equal Date.new(2026, 1, 31), BasImports::DateParser.parse("31-01-2026")
    assert_nil BasImports::DateParser.parse("31/02/2026")
  end

  test "file reader reads synthetic CSV upload" do
    result = BasImports::FileReader.read(bas_document("bas_bank_statement.csv", "bank_statement"))

    assert_equal [ "Date", "Description", "Debit", "Credit", "Balance" ], result.headers
    assert_equal 2, result.rows.size
    assert_equal "Synthetic debit", result.rows.first.fetch("data").fetch("Description")
  end

  test "previewer creates previewed import run without imported records" do
    job = bas_job
    document = bas_document("bas_bank_statement.csv", "bank_statement", job: job)

    assert_difference "BasImportRun.count", 1 do
      assert_no_difference "BasBankTransaction.count" do
        @import_run = BasImports::Previewer.new(
          bas_job: job,
          bas_document: document,
          import_type: "bank_statement",
          actor_username: "phase2"
        ).call
      end
    end

    assert_equal "previewed", @import_run.status
    assert_equal 2, @import_run.row_count
    assert_equal "Date", @import_run.column_mapping.fetch("transaction_date")
    assert_equal "bas_import_previewed", BasAuditEvent.last.event_type
  end

  test "importer imports bank statement rows" do
    import_run = preview_import("bas_bank_statement.csv", "bank_statement", "bank_statement")

    assert_difference "BasBankTransaction.count", 2 do
      BasImports::Importer.new(
        import_run: import_run,
        column_mapping: import_run.column_mapping,
        actor_username: "phase2"
      ).call
    end

    import_run.reload
    assert_equal "imported", import_run.status
    assert_equal 2, import_run.imported_count
    assert_equal 0, import_run.error_count
    assert_equal BigDecimal("-12.34"), BasBankTransaction.order(:source_row_number).first.amount
    assert_equal "bas_import_completed", BasAuditEvent.last.event_type
  end

  test "importer imports invoice summary rows" do
    import_run = preview_import("bas_invoice_summary.csv", "invoice_summary", "invoice_summary")

    assert_difference "BasInvoice.count", 2 do
      BasImports::Importer.new(
        import_run: import_run,
        column_mapping: import_run.column_mapping,
        actor_username: "phase2"
      ).call
    end

    invoice = BasInvoice.find_by!(invoice_number: "INV-001")
    assert_equal "sale", invoice.direction
    assert_equal BigDecimal("100.00"), invoice.net_amount
    assert_equal "taxable", invoice.gst_code
  end

  test "importer imports cash transaction rows" do
    import_run = preview_import("bas_cash_transactions.csv", "cash_transaction_list", "cash_transactions")

    assert_difference "BasCashTransaction.count", 2 do
      BasImports::Importer.new(
        import_run: import_run,
        column_mapping: import_run.column_mapping,
        actor_username: "phase2"
      ).call
    end

    assert_equal "cash_receipt", BasCashTransaction.order(:source_row_number).first.direction
  end

  test "importer imports payroll summary rows" do
    import_run = preview_import("bas_payroll_summary.csv", "payroll_summary", "payroll_summary")

    assert_difference "BasPayrollSummary.count", 1 do
      BasImports::Importer.new(
        import_run: import_run,
        column_mapping: import_run.column_mapping,
        actor_username: "phase2"
      ).call
    end

    assert_equal BigDecimal("1000.00"), BasPayrollSummary.last.gross_wages
  end

  test "importer records row errors without crashing whole import" do
    import_run = preview_import("bas_bank_statement_with_error.csv", "bank_statement", "bank_statement")

    assert_difference "BasBankTransaction.count", 1 do
      BasImports::Importer.new(
        import_run: import_run,
        column_mapping: import_run.column_mapping,
        actor_username: "phase2"
      ).call
    end

    import_run.reload
    assert_equal "imported", import_run.status
    assert_equal 1, import_run.imported_count
    assert_equal 1, import_run.error_count
    assert_match "Transaction date is invalid", import_run.import_errors.first.fetch("message")
  end

  test "reverter removes only records from selected import run" do
    first_import = preview_import("bas_bank_statement.csv", "bank_statement", "bank_statement")
    second_import = preview_import("bas_bank_statement.csv", "bank_statement", "bank_statement", job: first_import.bas_job)

    BasImports::Importer.new(import_run: first_import, column_mapping: first_import.column_mapping, actor_username: "phase2").call
    BasImports::Importer.new(import_run: second_import, column_mapping: second_import.column_mapping, actor_username: "phase2").call

    assert_equal 4, BasBankTransaction.count

    assert_difference "BasBankTransaction.count", -2 do
      BasImports::Reverter.new(import_run: first_import, actor_username: "phase2").call
    end

    assert_equal "reverted", first_import.reload.status
    assert_equal 2, BasBankTransaction.where(bas_import_run: second_import).count
    assert_equal "bas_import_reverted", BasAuditEvent.last.event_type
  end

  private

  def preview_import(filename, document_type, import_type, job: bas_job)
    document = bas_document(filename, document_type, job: job)
    BasImports::Previewer.new(
      bas_job: job,
      bas_document: document,
      import_type: import_type,
      actor_username: "phase2"
    ).call
  end

  def bas_job
    client = BasClient.create!(legal_name: "Synthetic Client Pty Ltd")
    BasJob.create!(
      bas_client: client,
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    )
  end

  def bas_document(filename, document_type, job: bas_job)
    document = job.documents.build(
      title: filename.titleize,
      document_type: document_type,
      uploaded_by: "phase2"
    )
    document.file.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/#{filename}"))),
      filename: filename,
      content_type: "text/csv"
    )
    document.save!
    document
  end
end
