require "test_helper"

class BasDocumentTest < ActiveSupport::TestCase
  test "requires an attached file" do
    document = BasDocument.new(bas_job: bas_job, title: "Bank statement")

    assert_not document.valid?
    assert_includes document.errors[:file], "must be attached"
  end

  test "accepts supported financial document types" do
    document = BasDocument.new(bas_job: bas_job, title: "Bank statement", document_type: "bank_statement")
    document.file.attach(
      io: StringIO.new("date,amount\n2026-01-01,12.34\n"),
      filename: "bank.csv",
      content_type: "text/csv",
      identify: false
    )

    assert document.valid?, document.errors.full_messages.to_sentence
    assert_equal "bank.csv", document.source_filename
  end

  test "allows octet stream only for safe recognised extensions" do
    document = BasDocument.new(bas_job: bas_job, title: "Spreadsheet")
    document.file.attach(
      io: StringIO.new("synthetic spreadsheet placeholder"),
      filename: "summary.xlsx",
      content_type: "application/octet-stream",
      identify: false
    )

    assert document.valid?, document.errors.full_messages.to_sentence

    document.file.detach
    document.file.attach(
      io: StringIO.new("synthetic executable placeholder"),
      filename: "summary.exe",
      content_type: "application/octet-stream",
      identify: false
    )

    assert_not document.valid?
    assert_includes document.errors[:file], "must be a CSV, XLS, XLSX, PDF, JPEG, PNG or WebP file"
  end

  test "rejects unsupported file type and oversize file" do
    document = BasDocument.new(bas_job: bas_job, title: "Bad file")
    document.file.attach(
      io: StringIO.new("plain text"),
      filename: "notes.txt",
      content_type: "text/plain",
      identify: false
    )

    assert_not document.valid?
    assert_includes document.errors[:file], "must be a CSV, XLS, XLSX, PDF, JPEG, PNG or WebP file"

    document.file.detach
    document.file.attach(
      io: StringIO.new("x" * (BasDocument::MAX_FILE_SIZE + 1)),
      filename: "large.pdf",
      content_type: "application/pdf",
      identify: false
    )

    assert_not document.valid?
    assert_includes document.errors[:file], "must be smaller than 25 MB"
  end

  private

  def bas_job
    @bas_job ||= BasJob.create!(
      bas_client: BasClient.create!(legal_name: "Synthetic Client Pty Ltd"),
      period_start: Date.new(2026, 1, 1),
      period_end: Date.new(2026, 3, 31)
    )
  end
end
