# Buildkite Webhook Proxy

A minimal Sinatra web application that forwards GitHub webhooks to Buildkite with payload transformation capabilities. Built with Puma web server for production-ready performance.

## Motivation

While Buildkite provides excellent CI/CD capabilities, it has limited support for certain GitHub webhook event types. This proxy serves as a bridge, allowing you to trigger Buildkite builds from GitHub events that aren't natively supported by transforming them into supported event types.

**Key Use Case**: Transform `issue_comment` events into `push` events so Buildkite can respond to PR comments, discussions, and other GitHub activities that would otherwise be ignored.

This pattern can be extended to support any GitHub event type by transforming the payload structure and event headers to match what Buildkite expects.

## Features

- 🔄 **Event Transformation**: Convert `issue_comment` events to `push` events for Buildkite compatibility
- 🔒 **Security**: IP validation using GitHub's published IP ranges + configurable host authorization
- ⚡ **Performance**: Thread-safe caching of GitHub IPs, user emails, repository default branches, and installation IDs (1-hour TTL)
- 🚀 **Production Ready**: Puma web server with clustering and worker management
- 📝 **Logging**: Structured logging with configurable levels
- 🔍 **Health Check**: `/health` endpoint for monitoring and load balancers
- 🤖 **Auto-Discovery**: Automatically discovers GitHub App installations based on repository information

## Quick Start

1. **Install dependencies:**
   ```bash
   git clone https://github.com/jasonwbarnett/buildkite-webhook-proxy.git
   cd buildkite-webhook-proxy
   bundle install
   ```

2. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your GitHub App credentials (no installation ID needed)
   ```

3. **Run the application:**
   ```bash
   bundle exec puma -C config/puma.rb
   ```

4. **Configure GitHub webhook:**
   - Point your GitHub webhook to: `https://your-domain.com/webhook/<buildkite-webhook-id>`
   - Select "issue_comment" event type

## Configuration

### Required Environment Variables

```bash
# GitHub App Configuration
GITHUB_APP_ID=your_app_id_here
GITHUB_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----..."

# Server Configuration
RACK_ENV=production
ALLOWED_HOSTS=your-domain.com,localhost:4567
LOG_LEVEL=INFO
```

**Note:** The `GITHUB_INSTALLATION_ID` environment variable is no longer required. The application automatically discovers the correct installation ID based on the repository information from incoming webhooks.

### Optional Environment Variables

```bash
PORT=4567                    # Server port (default: 4567)
BIND_HOST=127.0.0.1         # Bind address (use 0.0.0.0 for external access)
WEB_CONCURRENCY=2           # Puma workers (production)
RAILS_MAX_THREADS=5         # Threads per worker
```

### GitHub App Setup

Create a GitHub App with these permissions:

**Required Permissions:**
- **Repository permissions**: Metadata (read) - for repository info and default branch
- **Account permissions**: Email addresses (read) - for user email resolution

**Optional Enhancement:**
- **Organization permissions**: Members (read) - for better email resolution in organizations

**Installation Discovery:**
The application automatically discovers which GitHub App installation to use based on the repository information in webhook payloads. This eliminates the need to configure installation IDs manually and allows the same proxy instance to handle webhooks from multiple GitHub organizations/repositories.

**Benefits of Auto-Discovery:**
- **Zero Configuration**: No need to manually find and configure installation IDs
- **Multi-Organization Support**: Single proxy can handle webhooks from multiple GitHub organizations
- **Automatic Scaling**: Works seamlessly as you install the GitHub App on new repositories
- **Error Resilience**: Graceful handling when installations are not found

**Webhook Configuration:**
- **Webhook URL**: `https://your-domain.com/webhook/<buildkite-webhook-id>`
- **Events**: Select "Issue comments" (or any events you want to transform)

## Usage

### Basic Workflow

1. **GitHub sends webhook** → Your proxy at `/webhook/<buildkite-id>`
2. **Proxy validates** → Request comes from GitHub IPs
3. **Proxy transforms** → `issue_comment` becomes `push` event
4. **Proxy forwards** → Transformed webhook to Buildkite
5. **Buildkite processes** → Treats as push event and triggers build

### Payload Transformation

For `issue_comment` events, the proxy:
- Preserves original payload in `original_payload` field
- Sets `ref` to repository's default branch
- Creates `head_commit` structure with user email from GitHub API
- Changes `X-GitHub-Event` header from `issue_comment` to `push`

**Example transformation:**
```json
{
  "original_payload": { ... },
  "ref": "refs/heads/main",
  "repository": { ... },
  "head_commit": {
    "id": "HEAD",
    "message": "GitHub issue_comment event",
    "author": { "email": "user@example.com" },
    "committer": { "email": "user@example.com" }
  }
}
```

## Production Deployment

### Security Configuration

**Host Authorization:**
```bash
# Development
ALLOWED_HOSTS=localhost:4567,127.0.0.1:4567

# Production
ALLOWED_HOSTS=webhook.yourdomain.com,api.yourapp.com
```

- Always configure `ALLOWED_HOSTS` in production
- Use comma-separated values for multiple hosts
- Include port numbers for non-standard ports

**IP Protection:**
- Automatically validates requests from GitHub's IP ranges
- IPs refreshed every hour with mutex-protected caching
- Provides additional security beyond host authorization

### Running in Production

**With systemd:**
```ini
[Unit]
Description=Buildkite Webhook Proxy
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/opt/webhook-proxy
Environment=RACK_ENV=production
ExecStart=/usr/local/bin/bundle exec puma -C config/puma.rb
Restart=always

[Install]
WantedBy=multi-user.target
```

**With Docker:**
```dockerfile
FROM ruby:3.4-alpine
WORKDIR /app
COPY Gemfile* ./
RUN bundle install --without development test
COPY . .
EXPOSE 4567
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

### Monitoring

**Health Check:**
```bash
curl https://your-domain.com/health
# Returns: {"status":"healthy","github_ips_cached":true,"timestamp":"2025-01-09T12:34:56Z"}
```

**Logs:**
- Application logs: `log/puma_access.log`, `log/puma_error.log`
- Structured logging with timestamps and levels
- Configure log rotation for production

**Performance Monitoring:**
- Monitor GitHub IP cache hit rates
- Track user email cache effectiveness
- Monitor repository default branch cache performance
- Track installation ID cache effectiveness
- Watch for GitHub API rate limits

## Development

**Run with auto-reload:**
```bash
bundle exec rerun -- puma -C config/puma.rb
```

**Debug logging:**
```bash
LOG_LEVEL=DEBUG bundle exec puma -C config/puma.rb
```

**Test locally:**
```bash
# Health check
curl http://localhost:4567/health

# Test webhook (bypasses IP validation in development)
curl -X POST http://localhost:4567/webhook/test-id \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: issue_comment" \
  -d '{"action":"created","comment":{"user":{"login":"testuser"}}}'
```

## API Reference

### Endpoints

- `GET /health` - Health check with cache status
- `POST /webhook/<id>` - Webhook proxy endpoint

### GitHub APIs Used

- `GET /meta` - GitHub IP ranges (no auth required)
- `GET /users/{username}` - User profiles and emails (cached for 1 hour)
- `GET /repos/{owner}/{repo}` - Repository metadata and default branch (cached for 1 hour)
- `GET /repos/{owner}/{repo}/installation` - GitHub App installation discovery (cached for 1 hour)

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is available as open source under the terms of the MIT License.
