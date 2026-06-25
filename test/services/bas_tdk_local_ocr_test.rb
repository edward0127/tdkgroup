require "test_helper"
require "tmpdir"

class BasTdkLocalOcrTest < ActiveSupport::TestCase
  CommandStatus = Struct.new(:successful) do
    def success?
      successful
    end
  end

  test "disabled OCR returns structured failure without shelling out" do
    command_checked = false
    result = BasTdk::LocalOcr.new(
      path: "synthetic.pdf",
      env: { "TDK_LOCAL_OCR_ENABLED" => "false" },
      command_finder: ->(_command) {
        command_checked = true
        true
      },
      executor: ->(*_argv) { flunk "OCR command should not run when disabled" },
      logger: nil
    ).call

    refute result.success?
    refute result.attempted
    refute command_checked
    assert_equal "disabled", result.status
    assert_equal :disabled, result.error_code
    assert_equal BasTdk::LocalOcr::DISABLED_MESSAGE, result.message
  end

  test "missing OCR command returns structured failure without shelling out" do
    result = BasTdk::LocalOcr.new(
      path: "synthetic.pdf",
      env: { "TDK_LOCAL_OCR_ENABLED" => "true" },
      command_finder: ->(_command) { false },
      executor: ->(*_argv) { flunk "OCR command should not run when command is missing" },
      logger: nil
    ).call

    refute result.success?
    refute result.attempted
    assert_equal "missing_command", result.status
    assert_equal :missing_command, result.error_code
    assert_equal BasTdk::LocalOcr::MISSING_COMMAND_MESSAGE, result.message
  end

  test "successful OCR reads sidecar text and removes temporary files" do
    captured_argv = nil

    Dir.mktmpdir("tdk-local-ocr-test-parent-") do |parent|
      result = BasTdk::LocalOcr.new(
        path: "input.pdf",
        env: { "TDK_LOCAL_OCR_ENABLED" => "true" },
        command: "ocrmypdf",
        command_finder: ->(_command) { true },
        tmpdir_parent: parent,
        logger: nil,
        executor: ->(*argv) {
          captured_argv = argv
          sidecar_path = argv.fetch(argv.index("--sidecar") + 1)
          File.write(sidecar_path, "Date Description Withdrawals Deposits Running Balance\n18/05/2026 DEPOSIT SAMPLE VIC $2,000.00 -$66,187.25\n")
          [ "stdout should not be logged", "stderr should not be logged", CommandStatus.new(true) ]
        }
      ).call

      assert result.success?
      assert result.attempted
      assert_equal "succeeded", result.status
      assert_includes result.text, "Date Description Withdrawals Deposits Running Balance"
      assert_empty Dir.children(parent)
    end

    assert_kind_of Array, captured_argv
    assert_operator captured_argv.length, :>, 1
    assert_equal "ocrmypdf", captured_argv.first
    assert_includes captured_argv, "--sidecar"
    assert_includes captured_argv, "--skip-text"
    assert_includes captured_argv, "--rotate-pages"
    assert_includes captured_argv, "--deskew"
    assert_command_jobs captured_argv, "1"
    assert_command_psm captured_argv, "6"
    assert_includes captured_argv, "--output-type"
    assert_includes captured_argv, "input.pdf"
  end

  test "default OCR jobs are passed when env is missing" do
    captured_argv = successful_ocr_argv(
      env: { "TDK_LOCAL_OCR_ENABLED" => "true" }
    )

    assert_command_jobs captured_argv, "1"
  end

  test "default OCR page segmentation mode is passed when env is missing" do
    captured_argv = successful_ocr_argv(
      env: { "TDK_LOCAL_OCR_ENABLED" => "true" }
    )

    assert_command_psm captured_argv, "6"
  end

  test "configured OCR page segmentation modes are passed to ocrmypdf" do
    [ "4", "6" ].each do |psm|
      captured_argv = successful_ocr_argv(
        env: { "TDK_LOCAL_OCR_ENABLED" => "true", "TDK_LOCAL_OCR_PSM" => psm }
      )

      assert_command_psm captured_argv, psm
    end
  end

  test "invalid OCR page segmentation modes fall back to default" do
    [ "", "0", "-2", "not-a-number", "14" ].each do |invalid_psm|
      captured_argv = successful_ocr_argv(
        env: { "TDK_LOCAL_OCR_ENABLED" => "true", "TDK_LOCAL_OCR_PSM" => invalid_psm }
      )

      assert_command_psm captured_argv, "6", "expected default page segmentation mode for #{invalid_psm.inspect}"
    end
  end

  test "configured OCR jobs are passed to ocrmypdf" do
    captured_argv = successful_ocr_argv(
      env: { "TDK_LOCAL_OCR_ENABLED" => "true", "TDK_LOCAL_OCR_JOBS" => "2" }
    )

    assert_command_jobs captured_argv, "2"
  end

  test "invalid OCR jobs fall back to default" do
    [ "", "0", "-2", "not-a-number" ].each do |invalid_jobs|
      captured_argv = successful_ocr_argv(
        env: { "TDK_LOCAL_OCR_ENABLED" => "true", "TDK_LOCAL_OCR_JOBS" => invalid_jobs }
      )

      assert_command_jobs captured_argv, "1", "expected default jobs for #{invalid_jobs.inspect}"
    end
  end

  test "OCR command failure returns structured failure" do
    result = BasTdk::LocalOcr.new(
      path: "synthetic.pdf",
      env: { "TDK_LOCAL_OCR_ENABLED" => "true" },
      command_finder: ->(_command) { true },
      logger: nil,
      executor: ->(*_argv) { [ "", "", CommandStatus.new(false) ] }
    ).call

    refute result.success?
    assert result.attempted
    assert_equal "failed", result.status
    assert_equal :failed, result.error_code
    assert_equal BasTdk::LocalOcr::UNRELIABLE_MESSAGE, result.message
  end

  test "OCR timeout returns structured failure" do
    result = BasTdk::LocalOcr.new(
      path: "synthetic.pdf",
      env: { "TDK_LOCAL_OCR_ENABLED" => "true" },
      command_finder: ->(_command) { true },
      logger: nil,
      executor: ->(*_argv) { raise Timeout::Error }
    ).call

    refute result.success?
    assert result.attempted
    assert_equal "timeout", result.status
    assert_equal :timeout, result.error_code
    assert_equal BasTdk::LocalOcr::UNRELIABLE_MESSAGE, result.message
  end

  test "OCR logs omit command output and extracted text" do
    messages = []
    logger = Object.new
    logger.define_singleton_method(:info) { |message| messages << message }

    result = BasTdk::LocalOcr.new(
      path: "synthetic.pdf",
      env: { "TDK_LOCAL_OCR_ENABLED" => "true" },
      command_finder: ->(_command) { true },
      logger: logger,
      executor: ->(*argv) {
        sidecar_path = argv.fetch(argv.index("--sidecar") + 1)
        File.write(sidecar_path, "Sensitive account 123456 with private transaction text")
        [
          "stdout private document content",
          "stderr private document content",
          CommandStatus.new(true)
        ]
      }
    ).call

    assert result.success?
    joined_messages = messages.join("\n")
    assert_includes joined_messages, "status=attempted"
    assert_includes joined_messages, "status=succeeded"
    refute_includes joined_messages, "Sensitive account"
    refute_includes joined_messages, "private document content"
    refute_includes joined_messages, "synthetic.pdf"
  end

  private

  def successful_ocr_argv(env:)
    captured_argv = nil

    BasTdk::LocalOcr.new(
      path: "input.pdf",
      env: env,
      command: "ocrmypdf",
      command_finder: ->(_command) { true },
      logger: nil,
      executor: ->(*argv) {
        captured_argv = argv
        sidecar_path = argv.fetch(argv.index("--sidecar") + 1)
        File.write(sidecar_path, "Date Description Withdrawals Deposits Running Balance\n18/05/2026 DEPOSIT SAMPLE VIC $2,000.00 -$66,187.25\n")
        [ "", "", CommandStatus.new(true) ]
      }
    ).call.tap do |result|
      assert result.success?
    end

    captured_argv
  end

  def assert_command_jobs(argv, expected_jobs, message = nil)
    jobs_index = argv.index("--jobs")
    assert jobs_index, message
    assert_equal expected_jobs, argv[jobs_index + 1], message
  end

  def assert_command_psm(argv, expected_psm, message = nil)
    psm_index = argv.index("--tesseract-pagesegmode")
    assert psm_index, message
    assert_equal expected_psm, argv[psm_index + 1], message
  end
end
