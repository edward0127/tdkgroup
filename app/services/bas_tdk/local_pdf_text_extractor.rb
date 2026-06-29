require "open3"
require "timeout"
require "digest"

module BasTdk
  class LocalPdfTextExtractor
    DEFAULT_COMMAND = "pdftotext".freeze
    DEFAULT_TIMEOUT_SECONDS = 120
    DEFAULT_MODES = %i[layout layout_nopgbrk raw table fixed].freeze
    MODE_ARGUMENTS = {
      layout: [ "-layout" ],
      layout_nopgbrk: [ "-layout", "-nopgbrk" ],
      raw: [ "-raw" ],
      table: [ "-table" ],
      fixed: [ "-fixed", "4" ]
    }.freeze

    MISSING_COMMAND_MESSAGE = "Local PDF text extraction is not installed on this server.".freeze
    UNRELIABLE_MESSAGE = "This readable PDF could not be parsed reliably. Please upload an XLSX export or a clearer bank statement PDF.".freeze

    Result = Struct.new(
      :success,
      :text,
      :status,
      :message,
      :attempted,
      :error_code,
      :mode,
      :command,
      :command_resolved,
      :line_count,
      :byte_count,
      :text_sha256,
      keyword_init: true
    ) do
      def success?
        success == true
      end

      def failure?
        !success?
      end

      def sha256
        text_sha256
      end
    end

    def self.extract_candidates(path:, modes: DEFAULT_MODES, **kwargs)
      modes.map do |mode|
        new(path: path, mode: mode, **kwargs).call
      end
    end

    def self.configured_command(env = ENV)
      env["TDK_LOCAL_PDF_TEXT_COMMAND"].to_s.strip.presence || DEFAULT_COMMAND
    end

    def self.configured_timeout_seconds(env = ENV)
      Integer(env["TDK_LOCAL_PDF_TEXT_TIMEOUT_SECONDS"].presence || DEFAULT_TIMEOUT_SECONDS)
    rescue ArgumentError, TypeError
      DEFAULT_TIMEOUT_SECONDS
    end

    def initialize(
      path:,
      mode: :layout,
      env: ENV,
      command: nil,
      timeout_seconds: nil,
      command_finder: nil,
      executor: nil,
      logger: defined?(Rails) ? Rails.logger : nil
    )
      @path = path.to_s
      @mode = normalize_mode(mode)
      @env = env
      @command = command.to_s.strip.presence || self.class.configured_command(env)
      @timeout_seconds = timeout_seconds || self.class.configured_timeout_seconds(env)
      @command_finder = command_finder || ->(cmd) { BasTdk::LocalOcr.executable_path(cmd, env: env) }
      @executor = executor || ->(*argv) { Open3.capture3(*argv) }
      @logger = logger
    end

    def call
      return missing_command_result unless command_available?

      run_extraction
    rescue Timeout::Error
      timeout_result
    rescue Errno::ENOENT
      missing_command_result
    rescue StandardError
      failed_result
    end

    private

    attr_reader :path, :mode, :env, :command, :timeout_seconds, :command_finder, :executor, :logger

    def command_available?
      command_lookup.present?
    end

    def command_lookup
      return @command_lookup if defined?(@command_lookup)

      @command_lookup = command_finder.call(command)
    end

    def command_resolved
      lookup = command_lookup
      return lookup.to_s if lookup.is_a?(String) && lookup.present?

      BasTdk::LocalOcr.executable_path(command, env: env)
    rescue StandardError
      nil
    end

    def run_extraction
      log_status("attempted", attempted: true)
      stdout, stderr, status = run_command(extraction_argv)
      return unsupported_result if unsupported_mode?(stderr)
      return failed_result unless status&.success?

      extracted_text = stdout.to_s.scrub
      return failed_result if extracted_text.squish.blank?

      log_status("succeeded", attempted: true)
      text_metadata = safe_text_metadata(extracted_text)
      Result.new(
        success: true,
        text: extracted_text,
        status: "succeeded",
        message: nil,
        attempted: true,
        error_code: nil,
        mode: mode,
        command: command,
        command_resolved: command_resolved,
        line_count: text_metadata.fetch(:line_count),
        byte_count: text_metadata.fetch(:byte_count),
        text_sha256: text_metadata.fetch(:text_sha256)
      )
    end

    def run_command(argv)
      Timeout.timeout(timeout_seconds) do
        executor.call(*argv)
      end
    end

    def extraction_argv
      [
        command_resolved.presence || command,
        *MODE_ARGUMENTS.fetch(mode),
        "-enc", "UTF-8",
        path,
        "-"
      ]
    end

    def normalize_mode(value)
      candidate = value.to_s.strip.downcase.to_sym
      return candidate if MODE_ARGUMENTS.key?(candidate)

      :layout
    end

    def safe_text_metadata(extracted_text)
      {
        line_count: extracted_text.lines.count,
        byte_count: extracted_text.bytesize,
        text_sha256: Digest::SHA256.hexdigest(extracted_text)
      }
    end

    def unsupported_mode?(stderr)
      stderr.to_s.match?(/\b(?:unknown|unsupported|illegal|invalid)\s+(?:option|argument)\b/i)
    end

    def missing_command_result
      log_status("missing_command", attempted: false)
      failure_result(status: "missing_command", message: MISSING_COMMAND_MESSAGE, attempted: false, error_code: :missing_command)
    end

    def timeout_result
      log_status("timeout", attempted: true)
      failure_result(status: "timeout", message: UNRELIABLE_MESSAGE, attempted: true, error_code: :timeout)
    end

    def failed_result
      log_status("failed", attempted: true)
      failure_result(status: "failed", message: UNRELIABLE_MESSAGE, attempted: true, error_code: :failed)
    end

    def unsupported_result
      log_status("unsupported", attempted: true)
      failure_result(status: "unsupported", message: UNRELIABLE_MESSAGE, attempted: true, error_code: :unsupported)
    end

    def failure_result(status:, message:, attempted:, error_code:)
      Result.new(
        success: false,
        text: nil,
        status: status,
        message: message,
        attempted: attempted,
        error_code: error_code,
        mode: mode,
        command: command,
        command_resolved: command_resolved,
        line_count: 0,
        byte_count: 0,
        text_sha256: nil
      )
    end

    def log_status(status, attempted:)
      return if logger.blank?

      logger.info("BasTdk local PDF text extraction mode=#{mode} status=#{status} attempted=#{attempted}")
    end
  end
end
