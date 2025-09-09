# Puma configuration file

# Load environment variables from .env file
require 'dotenv/load'

# The directory to operate out of
directory '.'

# Use "path" as the file to store the server info state. This is
# used by "pumactl" to query and control the server.
state_path 'tmp/pids/server.state'

# Redirect STDOUT and STDERR to files
stdout_redirect 'log/puma_access.log', 'log/puma_error.log', true

# Bind to localhost for development, 0.0.0.0 for production
host = ENV.fetch('BIND_HOST', '127.0.0.1')
bind "tcp://#{host}:#{ENV.fetch('PORT', 4567)}"

# === Cluster mode ===

# How many worker processes to run. The default is "0".
workers ENV.fetch('WEB_CONCURRENCY', 2)

# Code to run in each worker process after it boots
on_worker_boot do
  # Pre-warm GitHub IP cache in each worker
  Thread.new do
    begin
      App.logger.info "Worker #{Process.pid}: Pre-warming GitHub IP cache..."
      IpValidator.fetch_github_ips
      App.logger.info "Worker #{Process.pid}: GitHub IP cache pre-warmed successfully"
    rescue => e
      App.logger.error "Worker #{Process.pid}: Failed to pre-warm GitHub IP cache: #{e.message}"
    end
  end
end

# === Threading ===

# The minimum and maximum number of threads to use to answer requests.
threads_count = ENV.fetch('RAILS_MAX_THREADS', 5)
threads threads_count, threads_count

# === Puma control rack ===

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart

# Enable serving static files
# static_file_middleware ENV['RACK_ENV'] != 'production'

# Set up socket activation
# socket_activation

# Preload the application
preload_app!

# Allow workers to reload bundler context when master process does.
prune_bundler

# Use the `preload_app!` option when specifying a `worker_timeout`.
# This enables a master process to respawn a worker process that
# has been deemed stuck.
worker_timeout 30 if ENV.fetch('RAILS_ENV', 'development') == 'production'

# Specifies the `environment` that Puma will run in.
environment ENV.fetch('RACK_ENV', 'development')

# Pidfile
pidfile ENV.fetch('PIDFILE', 'tmp/pids/server.pid')

# === Development mode ===

if ENV.fetch('RACK_ENV', 'development') == 'development'
  # Reload code in development
  # plugin :auto_reload

  # Reduce worker count for development
  workers 0

  # Increase thread count for development
  threads 1, 5
end
