require "test_helper"

class BasTdkLocalPdfTextExtractorTest < ActiveSupport::TestCase
  CommandStatus = Struct.new(:successful) do
    def success?
      successful
    end
  end

  test "missing pdftotext command returns structured failure without shelling out" do
    result = BasTdk::LocalPdfTextExtractor.new(
      path: "synthetic.pdf",
      command_finder: ->(_command) { false },
      executor: ->(*_argv) { flunk "pdftotext should not run when command is missing" },
      logger: nil
    ).call

    refute result.success?
    refute result.attempted
    assert_equal "missing_command", result.status
    assert_equal :missing_command, result.error_code
    assert_equal BasTdk::LocalPdfTextExtractor::MISSING_COMMAND_MESSAGE, result.message
  end

  test "successful extraction returns stdout text and uses layout arguments" do
    captured_argv = nil
    result = BasTdk::LocalPdfTextExtractor.new(
      path: "input.pdf",
      mode: :layout,
      command: "pdftotext",
      command_finder: ->(_command) { true },
      logger: nil,
      executor: ->(*argv) {
        captured_argv = argv
        [ "Date Transaction Debit Credit Balance\n01 Apr SAMPLE $1.00 $1.00\n", "", CommandStatus.new(true) ]
      }
    ).call

    assert result.success?
    assert result.attempted
    assert_equal "succeeded", result.status
    assert_includes result.text, "Date Transaction Debit Credit Balance"
    assert_equal [ "pdftotext", "-layout", "-enc", "UTF-8", "input.pdf", "-" ], captured_argv
    assert_equal :layout, result.mode
    assert_equal 2, result.line_count
    assert_operator result.byte_count, :positive?
    assert_match(/\A[0-9a-f]{64}\z/, result.text_sha256)
    assert_equal result.text_sha256, result.sha256
  end

  test "raw mode builds raw argv" do
    captured_argv = nil
    result = BasTdk::LocalPdfTextExtractor.new(
      path: "input.pdf",
      mode: :raw,
      command: "pdftotext",
      command_finder: ->(_command) { true },
      logger: nil,
      executor: ->(*argv) {
        captured_argv = argv
        [ "Date Transaction Debit Credit Balance\n01 Apr SAMPLE $1.00 $1.00\n", "", CommandStatus.new(true) ]
      }
    ).call

    assert result.success?
    assert_equal :raw, result.mode
    assert_equal [ "pdftotext", "-raw", "-enc", "UTF-8", "input.pdf", "-" ], captured_argv
  end

  test "table mode unsupported failure is captured without raising" do
    result = BasTdk::LocalPdfTextExtractor.new(
      path: "input.pdf",
      mode: :table,
      command: "pdftotext",
      command_finder: ->(_command) { true },
      logger: nil,
      executor: ->(*_argv) { [ "", "Unknown option: -table", CommandStatus.new(false) ] }
    ).call

    refute result.success?
    assert result.attempted
    assert_equal :table, result.mode
    assert_equal "unsupported", result.status
    assert_equal :unsupported, result.error_code
  end

  test "fixed mode builds fixed width argv" do
    captured_argv = nil
    result = BasTdk::LocalPdfTextExtractor.new(
      path: "input.pdf",
      mode: :fixed,
      command: "pdftotext",
      command_finder: ->(_command) { true },
      logger: nil,
      executor: ->(*argv) {
        captured_argv = argv
        [ "Date Transaction Debit Credit Balance\n01 Apr SAMPLE $1.00 $1.00\n", "", CommandStatus.new(true) ]
      }
    ).call

    assert result.success?
    assert_equal :fixed, result.mode
    assert_equal [ "pdftotext", "-fixed", "4", "-enc", "UTF-8", "input.pdf", "-" ], captured_argv
  end

  test "extract candidates attempts each requested mode" do
    captured_modes = []
    results = BasTdk::LocalPdfTextExtractor.extract_candidates(
      path: "input.pdf",
      modes: %i[layout raw],
      command: "pdftotext",
      command_finder: ->(_command) { true },
      logger: nil,
      executor: ->(*argv) {
        captured_modes << argv[1]
        [ "Date Transaction Debit Credit Balance\n01 Apr SAMPLE $1.00 $1.00\n", "", CommandStatus.new(true) ]
      }
    )

    assert_equal %i[layout raw], results.map(&:mode)
    assert_equal [ "-layout", "-raw" ], captured_modes
  end

  test "command failure and blank output return structured failure" do
    failed = BasTdk::LocalPdfTextExtractor.new(
      path: "synthetic.pdf",
      command_finder: ->(_command) { true },
      logger: nil,
      executor: ->(*_argv) { [ "", "", CommandStatus.new(false) ] }
    ).call
    refute failed.success?
    assert failed.attempted
    assert_equal "failed", failed.status

    blank = BasTdk::LocalPdfTextExtractor.new(
      path: "synthetic.pdf",
      command_finder: ->(_command) { true },
      logger: nil,
      executor: ->(*_argv) { [ "   ", "", CommandStatus.new(true) ] }
    ).call
    refute blank.success?
    assert blank.attempted
    assert_equal "failed", blank.status
  end

  test "timeout returns structured failure" do
    result = BasTdk::LocalPdfTextExtractor.new(
      path: "synthetic.pdf",
      command_finder: ->(_command) { true },
      logger: nil,
      executor: ->(*_argv) { raise Timeout::Error }
    ).call

    refute result.success?
    assert result.attempted
    assert_equal "timeout", result.status
    assert_equal :timeout, result.error_code
    assert_equal BasTdk::LocalPdfTextExtractor::UNRELIABLE_MESSAGE, result.message
  end

  test "logs omit command output and extracted text" do
    messages = []
    logger = Object.new
    logger.define_singleton_method(:info) { |message| messages << message }

    result = BasTdk::LocalPdfTextExtractor.new(
      path: "synthetic.pdf",
      command_finder: ->(_command) { true },
      logger: logger,
      executor: ->(*_argv) {
        [ "Sensitive account 123456 with private transaction text", "private stderr", CommandStatus.new(true) ]
      }
    ).call

    assert result.success?
    joined_messages = messages.join("\n")
    assert_includes joined_messages, "status=attempted"
    assert_includes joined_messages, "status=succeeded"
    refute_includes joined_messages, "Sensitive account"
    refute_includes joined_messages, "private stderr"
    refute_includes joined_messages, "synthetic.pdf"
  end
end
