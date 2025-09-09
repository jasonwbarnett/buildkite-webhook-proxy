require 'thread'
require 'singleton'

class GitHubCache
  include Singleton

  EMAIL_CACHE_DURATION = 3600 # 1 hour in seconds
  BRANCH_CACHE_DURATION = 3600 # 1 hour in seconds
  INSTALLATION_CACHE_DURATION = 3600 # 1 hour in seconds

  def initialize
    @email_mutex = Mutex.new
    @email_cache = {}
    @email_cache_timestamps = {}

    @branch_mutex = Mutex.new
    @branch_cache = {}
    @branch_cache_timestamps = {}

    @installation_mutex = Mutex.new
    @installation_cache = {}
    @installation_cache_timestamps = {}
  end

  def get_user_email(username)
    @email_mutex.synchronize do
      if @email_cache.key?(username) && !email_cache_expired?(username)
        return @email_cache[username]
      end
      nil
    end
  end

  def set_user_email(username, email)
    @email_mutex.synchronize do
      @email_cache[username] = email
      @email_cache_timestamps[username] = Time.now
    end
  end

  def get_repository_branch(repo_key)
    @branch_mutex.synchronize do
      if @branch_cache.key?(repo_key) && !branch_cache_expired?(repo_key)
        return @branch_cache[repo_key]
      end
      nil
    end
  end

  def set_repository_branch(repo_key, branch)
    @branch_mutex.synchronize do
      @branch_cache[repo_key] = branch
      @branch_cache_timestamps[repo_key] = Time.now
    end
  end

  def get_installation_id(repo_key)
    @installation_mutex.synchronize do
      if @installation_cache.key?(repo_key) && !installation_cache_expired?(repo_key)
        return @installation_cache[repo_key]
      end
      nil
    end
  end

  def set_installation_id(repo_key, installation_id)
    @installation_mutex.synchronize do
      @installation_cache[repo_key] = installation_id
      @installation_cache_timestamps[repo_key] = Time.now
    end
  end

  private

  def email_cache_expired?(username)
    return true unless @email_cache_timestamps.key?(username)
    (Time.now - @email_cache_timestamps[username]) > EMAIL_CACHE_DURATION
  end

  def branch_cache_expired?(repo_key)
    return true unless @branch_cache_timestamps.key?(repo_key)
    (Time.now - @branch_cache_timestamps[repo_key]) > BRANCH_CACHE_DURATION
  end

  def installation_cache_expired?(repo_key)
    return true unless @installation_cache_timestamps.key?(repo_key)
    (Time.now - @installation_cache_timestamps[repo_key]) > INSTALLATION_CACHE_DURATION
  end
end
