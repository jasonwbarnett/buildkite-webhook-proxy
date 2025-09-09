require 'ipaddr'
require 'thread'
require_relative 'github_service'

class IpValidator
  CACHE_DURATION = 3600 # 1 hour in seconds

  @@mutex = Mutex.new
  @@cached_ips = []
  @@last_update = nil

  def self.valid_request?(request)
    client_ip = extract_client_ip(request)
    return false unless client_ip

    allowed_ips = fetch_github_ips
    ip_addr = IPAddr.new(client_ip)

    allowed_ips.any? do |allowed_range|
      begin
        IPAddr.new(allowed_range).include?(ip_addr)
      rescue IPAddr::InvalidAddressError
        false
      end
    end
  end

  def self.fetch_github_ips
    @@mutex.synchronize do
      if cache_expired?
        update_ip_cache
      end
      @@cached_ips.dup
    end
  end

  def self.github_ips_cached?
    @@mutex.synchronize do
      !@@cached_ips.empty? && !@@last_update.nil?
    end
  end

  private

  def self.extract_client_ip(request)
    # Check for Cloudflare-specific header first, then other proxy headers
    request.env['HTTP_CF_CONNECTING_IP'] ||
    request.env['HTTP_X_FORWARDED_FOR']&.split(',')&.first&.strip ||
    request.env['HTTP_X_REAL_IP'] ||
    request.env['REMOTE_ADDR']
  end

  def self.cache_expired?
    @@last_update.nil? || (Time.now - @@last_update) > CACHE_DURATION
  end

  def self.update_ip_cache
    begin
      meta_info = GitHubService.fetch_meta_info

      hooks_ips = meta_info.dig('hooks') || []
      actions_ips = meta_info.dig('actions') || []

      @@cached_ips = hooks_ips + actions_ips
      @@last_update = Time.now

      App.logger.info "Worker #{Process.pid}: Updated GitHub IP cache with #{@@cached_ips.length} IP ranges"
    rescue => e
      App.logger.error "Error updating GitHub IP cache: #{e.message}"
      # Keep using cached IPs if update fails
    end
  end
end
