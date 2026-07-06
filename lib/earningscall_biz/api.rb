# frozen_string_literal: true

require "json"
require "logger"
require "time"
require "date"
require "faraday"

module EarningsCallBiz
  class API
    DOMAIN = ENV.fetch("EARNINGSCALL_DOMAIN", "earningscall.biz")
    HOST = "https://v2.api.#{DOMAIN}/"

    JSON_CONTENT_TYPE = "application/json"

    RETRY_WAIT = 1
    MAX_RETRY = 6
    MAX_BACKOFF = 32
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 60
    attr_reader :apikey

    def initialize(apikey = nil)
      @apikey = apikey || ENV["EARNINGSCALLBIZ_API_KEY"] || ENV["EARNINGSCALL_API_KEY"] || ENV["ECALL_API_KEY"] || "demo"
    end

    def calendar(date)
      date = Date.parse(date.to_s) unless date.respond_to?(:year)
      request("calendar", year: date.year, month: date.month, day: date.day)
    end

    def events(exchange:, symbol:)
      request("events", exchange: exchange, symbol: symbol)
    end

    def transcript(exchange:, symbol:, year:, quarter:, level: 1)
      validate_quarter!(quarter)
      validate_level!(level)

      request(
        "transcript",
        exchange: exchange,
        symbol: symbol,
        year: year,
        quarter: quarter,
        level: level
      )
    end

    def symbols
      request_text("symbols-v2.txt", use_cache: true)
    end

    def sp500_symbols
      request_text("symbols/sp500.txt", use_cache: true)
    end

    def download_audio_file(exchange:, symbol:, year:, quarter:, file_name: nil)
      validate_quarter!(quarter)
      file_name ||= "#{exchange}_#{symbol}_#{year}_#{quarter}.mp3"
      download("audio", file_name, exchange: exchange, symbol: symbol, year: year, quarter: quarter)
    end

    def download_slide_deck(exchange:, symbol:, year:, quarter:, file_name: nil)
      validate_quarter!(quarter)
      file_name ||= "#{exchange}_#{symbol}_#{year}_#{quarter}_slides.pdf"
      download("slides", file_name, exchange: exchange, symbol: symbol, year: year, quarter: quarter)
    end

    # Escape hatch for endpoints added by EarningsCall.biz before this gem has a wrapper.
    def get(path, params = {})
      request(path, params)
    end

    private

      def request(path, params = {})
        response = perform_get(path, params)
        ensure_json_response!(response)
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise InvalidResponse, e.message
      end

      def request_text(path, params = {})
        perform_get(path, params).body
      end

      def download(path, file_name, params = {})
        response = perform_get(path, params)
        File.open(file_name, "wb") do |file|
          file.write(response.body)
        end
        file_name
      end

      def perform_get(path, params = {})
        retries = 0
        full_url = "#{HOST}#{path}"
        req_args = params.compact.merge(apikey: apikey)

        begin
          response = connection.get(full_url, req_args)
          return response if success?(response)

          handle_error_response!(response)
        rescue ServiceUnavailable => e
          if retries < MAX_RETRY
            retries += 1
            wait = backoff_sleep(e.retry_after, retries)
            logger.info("EarningsCall.biz unavailable for #{request_log_line(full_url, req_args)}: #{e.message}; retrying #{retries}/#{MAX_RETRY} in #{wait.round(1)}s")
            sleep wait
            retry
          end

          raise
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          if retries < MAX_RETRY
            retries += 1
            wait = backoff_sleep(nil, retries)
            logger.info("EarningsCall.biz connection error for #{request_log_line(full_url, req_args)}: #{e.class}: #{e.message}; retrying #{retries}/#{MAX_RETRY} in #{wait.round(1)}s")
            sleep wait
            retry
          end

          raise
        end
      end

      def success?(response)
        response.status == 200
      end

      def handle_error_response!(response)
        case response.status
        when 401
          raise InvalidApiKey, "Your EarningsCall.biz API key is invalid"
        when 403
          plan_name = response.headers["X-Plan-Name"] || response.headers["x-plan-name"] || "unknown"
          raise InsufficientApiAccess, "Your EarningsCall.biz plan (#{plan_name}) does not include this endpoint"
        when 404
          raise NotFound, error_message_from_body(response.body, response.status)
        when 429, 500..599
          raise ServiceUnavailable.new(
            error_message_from_body(response.body, response.status),
            http_status: response.status,
            retry_after: parse_retry_after(response)
          )
        else
          raise Error, error_message_from_body(response.body, response.status)
        end
      end

      def ensure_json_response!(response)
        content_type = response.headers["content-type"] || response.headers["Content-Type"]
        return if content_type&.include?(JSON_CONTENT_TYPE)

        raise InvalidResponse, "Expected JSON response, got #{content_type || "unknown"}"
      end

      def error_message_from_body(body, status)
        detail = parse_error_detail(body)
        detail.empty? ? "HTTP #{status}" : "#{status} #{detail}"
      end

      def parse_error_detail(body)
        return "" if body.nil?

        b = body.to_s
        return b.byteslice(0, 240) if b.strip.empty?

        json = JSON.parse(b)
        msg = json["Error Message"] || json["error"] || json["message"] || json["detail"]
        s = msg&.to_s
        s = b.byteslice(0, 240) if s.nil? || s.empty?
        s.byteslice(0, 240)
      rescue JSON::ParserError
        b.byteslice(0, 240)
      end

      def parse_retry_after(response)
        raw = response.headers["retry-after"] || response.headers["Retry-After"]
        return nil if raw.nil? || raw.to_s.strip.empty?

        s = raw.to_s.strip
        if /\A\d+\z/.match?(s)
          s.to_i.clamp(1, 3600)
        else
          seconds = (Time.httpdate(s) - Time.now).to_i
          seconds.clamp(1, 3600) if seconds.positive?
        end
      rescue ArgumentError, TypeError
        nil
      end

      def backoff_sleep(retry_after, retries)
        return [retry_after.to_f, 3600].min + jitter if retry_after

        [RETRY_WAIT * (2**(retries - 1)), MAX_BACKOFF].min + jitter
      end

      def jitter
        rand * 0.5
      end

      def validate_quarter!(quarter)
        return if (1..4).cover?(quarter.to_i)

        raise ArgumentError, "quarter must be one of: 1, 2, 3, or 4"
      end

      def validate_level!(level)
        return if (1..4).cover?(level.to_i)

        raise ArgumentError, "level must be one of: 1, 2, 3, or 4"
      end

      def request_log_line(full_url, args)
        visible = args.reject { |k, _| k.to_s == "apikey" }
        "#{full_url} #{visible.inspect}"
      end

      def connection
        @connection ||= Faraday.new do |f|
          f.options.open_timeout = OPEN_TIMEOUT
          f.options.timeout = READ_TIMEOUT
        end
      end

      def logger
        @logger ||= Logger.new($stdout)
      end
  end
end
