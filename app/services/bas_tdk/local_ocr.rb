require "open3"
require "timeout"
require "tmpdir"

module BasTdk
  class LocalOcr
    DEFAULT_COMMAND = "ocrmypdf".freeze
    DEFAULT_TIMEOUT_SECONDS = 300
    DEFAULT_JOBS = 1
    TRUE_VALUES = %w[1 true t yes y on].freeze

    DISABLED_MESSAGE = "This PDF appears to be image-based, but local OCR is not enabled on this server. Please upload the original bank PDF with selectable text, or upload XLSX.".freeze
    MISSING_COMMAND_MESSAGE = "This PDF appears to be image-based, but local OCR is not installed on this server. Please upload the original bank PDF with selectable text, or upload XLSX.".freeze
    UNRELIABLE_MESSAGE = "This scanned PDF could not be read reliably by local OCR. Please upload the original bank PDF with selectable text, or upload an XLSX bank statement.".freeze

    Result = Struct.new(:success, :text, :status, :message, :attempted, :error_code, keyword_init: true) do
      def success?
        success == true
      end

      def failure?
        !success?
      end
    end

    def self.call(path:)
      new(path: path).call
    end

    def self.enabled?(env = ENV)
      TRUE_VALUES.include?(env["TDK_LOCAL_OCR_ENABLED"].to_s.strip.downcase)
    end

    def self.configured_command(env = ENV)
      env["TDK_LOCAL_OCR_COMMAND"].to_s.strip.presence || DEFAULT_COMMAND
    end

    def self.configured_timeout_seconds(env = ENV)
      Integer(env["TDK_LOCAL_OCR_TIMEOUT_SECONDS"].presence || DEFAULT_TIMEOUT_SECONDS)
    rescue ArgumentError, TypeError
      DEFAULT_TIMEOUT_SECONDS
    end

    def self.configured_jobs(env = ENV)
      value = Integer(env["TDK_LOCAL_OCR_JOBS"].presence || DEFAULT_JOBS)
      value >= 1 ? value : DEFAULT_JOBS
    rescue ArgumentError, TypeError
      DEFAULT_JOBS
    end

    def initialize(
      path:,
      env: ENV,
      command: nil,
      timeout_seconds: nil,
      command_finder: nil,
      executor: nil,
      tmpdir_parent: nil,
      logger: defined?(Rails) ? Rails.logger : nil
    )
      @path = path.to_s
      @env = env
      @command = command.to_s.strip.presence || self.class.configured_command(env)
      @timeout_seconds = timeout_seconds || self.class.configured_timeout_seconds(env)
      @jobs = self.class.configured_jobs(env)
      @command_finder = command_finder || ->(cmd) { self.class.executable_path(cmd, env: env).present? }
      @executor = executor || ->(*argv) { Open3.capture3(*argv) }
      @tmpdir_parent = tmpdir_parent
      @logger = logger
    end

    def call
      return disabled_result unless self.class.enabled?(env)
      return missing_command_result unless command_available?

      run_ocr
    rescue Timeout::Error
      timeout_result
    rescue Errno::ENOENT
      missing_command_result
    rescue StandardError
      failed_result
    end

    def self.executable_path(command, env: ENV)
      value = command.to_s.strip
      return if value.blank?

      return value if command_path?(value) && executable_file?(value)
      return if command_path?(value)

      executable_names(value, env: env).each do |name|
        env["PATH"].to_s.split(File::PATH_SEPARATOR).each do |directory|
          candidate = File.join(directory, name)
          return candidate if executable_file?(candidate)
        end
      end

      nil
    end

    def self.command_path?(command)
      command.include?("/") || command.include?("\\")
    end

    def self.executable_names(command, env: ENV)
      return [ command ] if File.extname(command).present?

      extensions = env["PATHEXT"].to_s.split(";").presence || %w[.EXE .BAT .CMD .COM]
      [ command, *extensions.map { |extension| "#{command}#{extension.downcase}" }, *extensions.map { |extension| "#{command}#{extension.upcase}" } ].uniq
    end

    def self.executable_file?(path)
      File.file?(path) && File.executable?(path)
    end

    private

    attr_reader :path, :env, :command, :timeout_seconds, :jobs, :command_finder, :executor, :tmpdir_parent, :logger

    def command_available?
      command_finder.call(command).present?
    end

    def run_ocr
      log_status("attempted", attempted: true)
      Dir.mktmpdir("tdk-local-ocr-", tmpdir_parent) do |directory|
        sidecar_path = File.join(directory, "ocr.txt")
        output_path = File.join(directory, "ocr.pdf")
        _stdout, _stderr, status = run_command(ocr_argv(sidecar_path: sidecar_path, output_path: output_path))

        return failed_result unless status&.success?
        return failed_result unless File.exist?(sidecar_path)

        extracted_text = File.read(sidecar_path).scrub
        return failed_result if extracted_text.squish.blank?

        log_status("succeeded", attempted: true)
        Result.new(
          success: true,
          text: extracted_text,
          status: "succeeded",
          message: nil,
          attempted: true,
          error_code: nil
        )
      end
    end

    def run_command(argv)
      Timeout.timeout(timeout_seconds) do
        executor.call(*argv)
      end
    end

    def ocr_argv(sidecar_path:, output_path:)
      [
        command,
        "--skip-text",
        "--rotate-pages",
        "--deskew",
        "--jobs", jobs.to_s,
        "--sidecar", sidecar_path,
        "--output-type", "pdf",
        path,
        output_path
      ]
    end

    def disabled_result
      log_status("disabled", attempted: false)
      failure_result(status: "disabled", message: DISABLED_MESSAGE, attempted: false, error_code: :disabled)
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

    def failure_result(status:, message:, attempted:, error_code:)
      Result.new(
        success: false,
        text: nil,
        status: status,
        message: message,
        attempted: attempted,
        error_code: error_code
      )
    end

    def log_status(status, attempted:)
      return if logger.blank?

      logger.info("BasTdk local OCR status=#{status} attempted=#{attempted}")
    end
  end
end
