require 'dotenv/load'
require 'sinatra/base'
require 'json'
require 'faraday'
require 'jwt'
require 'ipaddr'
require 'thread'
require 'logger'

require_relative 'lib/github_service'
require_relative 'lib/ip_validator'
require_relative 'lib/payload_transformer'

class App < Sinatra::Base
  configure do
    set :port, ENV.fetch('PORT', 4567)
    set :bind, ENV.fetch('BIND_HOST', '127.0.0.1')

    # Configure logger
    log_level = ENV.fetch('LOG_LEVEL', 'INFO').upcase
    logger = Logger.new(STDOUT)
    logger.level = Logger.const_get(log_level)
    logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end
    set :logger, logger

    # Add access logging middleware
    access_logger = Logger.new('log/access.log')
    access_logger.formatter = proc do |severity, datetime, progname, msg|
      "#{msg}\n"
    end
    use Rack::CommonLogger, access_logger

    # Configure allowed hosts for security
    allowed_hosts = ENV.fetch('ALLOWED_HOSTS', '').split(',').map(&:strip).reject(&:empty?)
    unless allowed_hosts.empty?
      set :protection, host_authorization: { permitted_hosts: allowed_hosts }
    end

    # Pre-warm GitHub IP cache after server starts
    configure :production do
      # In production with workers, pre-warm in each worker after fork
    end

    configure :development do
      # In development, pre-warm immediately
      Thread.new do
        begin
          logger.info "Pre-warming GitHub IP cache..."
          IpValidator.fetch_github_ips
          logger.info "GitHub IP cache pre-warmed successfully"
        rescue => e
          logger.error "Failed to pre-warm GitHub IP cache: #{e.message}"
        end
      end
    end
  end

  get '/health' do
    content_type :json

    github_ips_cached = IpValidator.github_ips_cached?
    status = github_ips_cached ? 'healthy' : 'unhealthy'

    {
      status: status,
      github_ips_cached: github_ips_cached,
      timestamp: Time.now.iso8601
    }.to_json
  end

  post '/webhook/:id' do |id|
    halt 403, 'Forbidden' unless IpValidator.valid_request?(request)

    original_payload = request.body.read
    request.body.rewind

    github_event = request.env['HTTP_X_GITHUB_EVENT']
    transformed_payload = PayloadTransformer.transform(original_payload, github_event)

    status, headers, body = forward_to_buildkite(id, transformed_payload, request, github_event)

    # Return the original response from Buildkite
    [status, headers, body]
  end

  private

  def forward_to_buildkite(id, payload, original_request, github_event)
    headers = extract_headers(original_request)

    # Override X-GitHub-Event to "push" for issue_comment events
    if github_event == 'issue_comment'
      headers['X-Github-Event'] = 'push'
    end

    # Log the request we're about to send
    logger.debug "Forwarding to Buildkite URL: https://webhook.buildkite.com/deliver/#{id}"
    logger.debug "Headers being sent: #{headers.inspect}"
    logger.debug "Payload size: #{payload.bytesize} bytes"
    logger.debug "Payload preview: #{payload[0..200]}"

    conn = Faraday.new(url: 'https://webhook.buildkite.com') do |faraday|
      faraday.options.timeout = 30
      faraday.options.open_timeout = 10
    end

    begin
      response = conn.post("/deliver/#{id}") do |req|
        headers.each { |key, value| req.headers[key] = value }
        req.body = payload
      end

      # Log the response we got back
      logger.info "Buildkite response: status=#{response.status}"
      logger.debug "Buildkite response headers: #{response.headers.to_h.inspect}"
      logger.debug "Buildkite response body: #{response.body}"

    rescue => e
      logger.error "Error forwarding to Buildkite: #{e.class}: #{e.message}"
      logger.debug "Backtrace: #{e.backtrace.first(5).join(', ')}"
      return [500, {}, "Proxy error: #{e.message}"]
    end

    [response.status, response.headers.to_h, response.body]
  end

  def extract_headers(request)
    # Only forward specific headers needed by Buildkite
    allowed_headers = [
      'Accept',
      'Content-Type',
      'User-Agent',
      'X-Github-Delivery',
      'X-Github-Event',
      'X-Github-Hook-Id',
      'X-Github-Hook-Installation-Target-Id',
      'X-Github-Hook-Installation-Target-Type'
    ]

    headers = {}
    request.env.each do |key, value|
      if key.start_with?('HTTP_')
        header_name = key[5..-1].split('_').map(&:capitalize).join('-')
        if allowed_headers.include?(header_name)
          headers[header_name] = value
        end
      end
    end

    # Also check for Content-Type which might not have HTTP_ prefix
    if request.content_type
      headers['Content-Type'] = request.content_type
    end

    headers
  end
end
