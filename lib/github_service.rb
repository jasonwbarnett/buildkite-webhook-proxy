require 'faraday'
require 'jwt'
require 'json'
require 'openssl'
require 'thread'
require_relative 'github_cache'

class GitHubService
  API_BASE_URL = 'https://api.github.com'

  def initialize(installation_id = nil)
    @app_id = ENV['GITHUB_APP_ID']
    @installation_id = installation_id || ENV['GITHUB_INSTALLATION_ID']
    @private_key = OpenSSL::PKey::RSA.new(ENV['GITHUB_PRIVATE_KEY'])
  end

  def self.find_installation_by_repository(owner, repo)
    repo_key = "#{owner}/#{repo}"
    cache = GitHubCache.instance

    # Check if we have a cached installation ID that's still valid
    cached_id = cache.get_installation_id(repo_key)
    return cached_id if cached_id

    # Fetch from API using JWT (App-level authentication)
    installation_id = fetch_installation_from_api(owner, repo)

    # Cache the result
    cache.set_installation_id(repo_key, installation_id)
    installation_id
  end

  def fetch_meta_info
    response = make_request('/meta')
    raise "Failed to fetch GitHub meta info: #{response.status}" unless response.success?

    JSON.parse(response.body)
  end

  def self.fetch_meta_info
    # Public endpoint - no authentication required
    conn = Faraday.new(url: API_BASE_URL) do |faraday|
      faraday.headers['Accept'] = 'application/vnd.github+json'
      faraday.headers['X-GitHub-Api-Version'] = '2022-11-28'
    end

    response = conn.get('/meta')
    raise "Failed to fetch GitHub meta info: #{response.status}" unless response.success?

    JSON.parse(response.body)
  end

  def fetch_user_email(username)
    cache = GitHubCache.instance

    # Check if we have a cached email that's still valid
    cached_email = cache.get_user_email(username)
    return cached_email if cached_email

    # Handle bot users - they don't have email addresses
    if username&.end_with?('[bot]')
      email = "#{username}@users.noreply.github.com"
      cache.set_user_email(username, email)
      return email
    end

    # Fetch from API
    email = fetch_user_email_from_api(username)

    # Cache the result (including nil values to avoid repeated API calls for users without public emails)
    cache.set_user_email(username, email)
    email
  end

  def fetch_repository_default_branch(owner, repo)
    repo_key = "#{owner}/#{repo}"
    cache = GitHubCache.instance

    # Check if we have a cached branch that's still valid
    cached_branch = cache.get_repository_branch(repo_key)
    return cached_branch if cached_branch

    # Fetch from API
    branch = fetch_repository_default_branch_from_api(owner, repo)

    # Cache the result
    cache.set_repository_branch(repo_key, branch)
    branch
  end

  private

  def make_request(path)
    conn = Faraday.new(url: API_BASE_URL) do |faraday|
      faraday.headers['Authorization'] = "Bearer #{access_token}"
      faraday.headers['Accept'] = 'application/vnd.github+json'
      faraday.headers['X-GitHub-Api-Version'] = '2022-11-28'
    end

    conn.get(path)
  end

  def access_token
    @access_token ||= fetch_access_token
  end

  def fetch_access_token
    jwt_token = generate_jwt

    conn = Faraday.new(url: API_BASE_URL) do |faraday|
      faraday.headers['Authorization'] = "Bearer #{jwt_token}"
      faraday.headers['Accept'] = 'application/vnd.github+json'
    end

    response = conn.post("/app/installations/#{@installation_id}/access_tokens")

    raise "Failed to get access token: #{response.status}" unless response.success?

    token_data = JSON.parse(response.body)
    token_data['token']
  end

  def generate_jwt
    now = Time.now.to_i
    payload = {
      iat: now - 60,
      exp: now + (10 * 60),
      iss: @app_id
    }

    JWT.encode(payload, @private_key, 'RS256')
  end

  def self.generate_app_jwt
    app_id = ENV['GITHUB_APP_ID']
    private_key = OpenSSL::PKey::RSA.new(ENV['GITHUB_PRIVATE_KEY'])

    now = Time.now.to_i
    payload = {
      iat: now - 60,
      exp: now + (10 * 60),
      iss: app_id
    }

    JWT.encode(payload, private_key, 'RS256')
  end

  def self.fetch_installation_from_api(owner, repo)
    jwt_token = generate_app_jwt

    conn = Faraday.new(url: API_BASE_URL) do |faraday|
      faraday.headers['Authorization'] = "Bearer #{jwt_token}"
      faraday.headers['Accept'] = 'application/vnd.github+json'
      faraday.headers['X-GitHub-Api-Version'] = '2022-11-28'
    end

    response = conn.get("/repos/#{owner}/#{repo}/installation")

    if response.success?
      installation_data = JSON.parse(response.body)
      installation_data['id']
    else
      App.logger.error "Failed to find installation for #{owner}/#{repo}: #{response.status}"
      raise "Installation not found for repository #{owner}/#{repo}"
    end
  rescue => e
    App.logger.error "Error finding installation for #{owner}/#{repo}: #{e.message}"
    raise
  end

  def fetch_user_email_from_api(username)
    response = make_request("/users/#{username}")
    return nil unless response.success?

    user_data = JSON.parse(response.body)
    user_data['email']
  end

  def fetch_repository_default_branch_from_api(owner, repo)
    response = make_request("/repos/#{owner}/#{repo}")
    return 'main' unless response.success?

    repo_data = JSON.parse(response.body)
    repo_data.dig('default_branch') || 'main'
  end

end
