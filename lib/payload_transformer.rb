require 'json'

class PayloadTransformer
  def self.transform(payload_body, github_event)
    return payload_body unless github_event == 'issue_comment'

    begin
      original_payload = JSON.parse(payload_body)
      transform_issue_comment(original_payload, github_event).to_json
    rescue JSON::ParserError => e
      App.logger.error "Error parsing JSON payload: #{e.message}"
      payload_body
    rescue => e
      App.logger.error "Error transforming payload: #{e.message}"
      payload_body
    end
  end

  private

  def self.transform_issue_comment(original_payload, github_event)
    repository = original_payload['repository']
    comment_user_login = original_payload.dig('comment', 'user', 'login')

    return original_payload unless repository && comment_user_login

    # Look up installation ID dynamically based on repository
    owner = repository['owner']['login']
    repo_name = repository['name']

    begin
      installation_id = GitHubService.find_installation_by_repository(owner, repo_name)
      github_service = GitHubService.new(installation_id)
    rescue => e
      App.logger.error "Failed to find installation for #{owner}/#{repo_name}: #{e.message}"
      return original_payload
    end

    default_branch = fetch_default_branch(github_service, repository)
    user_email = fetch_user_email(github_service, comment_user_login)

    {
      'original_payload' => original_payload,
      'ref' => "refs/heads/#{default_branch}",
      'repository' => repository,
      'head_commit' => {
        'id' => 'HEAD',
        'message' => "GitHub #{github_event} event",
        'author' => {
          'email' => user_email
        },
        'committer' => {
          'email' => user_email
        },
        'added' => [],
        'removed' => [],
        'modified' => []
      }
    }
  end

  def self.fetch_default_branch(github_service, repository)
    owner = repository['owner']['login']
    repo_name = repository['name']

    github_service.fetch_repository_default_branch(owner, repo_name)
  rescue => e
    App.logger.error "Error fetching default branch: #{e.message}"
    'main'
  end

  def self.fetch_user_email(github_service, username)
    github_service.fetch_user_email(username)
  rescue => e
    App.logger.error "Error fetching user email: #{e.message}"
    "#{username}@users.noreply.github.com"
  end
end
