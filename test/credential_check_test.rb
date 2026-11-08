# frozen_string_literal: true

# Behaviour specification bridge for the credential check.
#
# Bridged from features/credential-check.feature by the sanitized scenario title.

require 'minitest/autorun'
require 'yaml'

require_relative '../scripts/check-token-expiry'

class CredentialCheckTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  NOW = Time.utc(2026, 11, 7, 12)
  # Plain values: they carry no access and cannot expire.
  VALUE_SECRETS = /\ASITE_/.freeze

  def read(path)
    File.read(File.join(ROOT, path))
  end

  # Both GitHub expression syntaxes: secrets.NAME and secrets['NAME'].
  SECRET_REFERENCE = /\bsecrets(?:\.([A-Za-z0-9_]+)|\[\s*['"]([A-Za-z0-9_]+)['"]\s*\])/.freeze

  def secrets_in(workflow)
    workflow.scan(SECRET_REFERENCE).flatten.compact.uniq.reject { |name| name.match?(VALUE_SECRETS) }
  end

  def expiring_in(days)
    (NOW + (days * TokenExpiry::SECONDS_PER_DAY)).strftime('%F %T UTC')
  end

  def test_a_token_far_from_its_expiry_date_passes
    # Given: a token that GitHub accepts and that expires in 30 days
    expiry = expiring_in(30)

    # When: its expiry is checked
    result = TokenExpiry.verdict(status: 200, expiry: expiry, now: NOW)

    # Then: the check passes and names the expiry date
    assert result.ok
    assert_includes result.message, '2026-12-07'
  end

  def test_a_token_close_to_its_expiry_date_fails_early
    # Given: a token that GitHub accepts and that expires in 13 days
    expiry = expiring_in(13)

    # When: its expiry is checked
    result = TokenExpiry.verdict(status: 200, expiry: expiry, now: NOW)

    # Then: the check fails and names the expiry date
    refute result.ok
    assert_includes result.message, '2026-11-20'
  end

  def test_a_token_without_an_expiry_date_passes
    # Given: a token that GitHub accepts and for which it reports no expiry date
    expiry = nil

    # When: its expiry is checked
    result = TokenExpiry.verdict(status: 200, expiry: expiry, now: NOW)

    # Then: the check passes
    assert result.ok
  end

  def test_a_rejected_token_fails
    # Given: a token that GitHub rejects
    status = 401

    # When: its expiry is checked
    result = TokenExpiry.verdict(status: status, expiry: nil, now: NOW)

    # Then: the check fails and names the HTTP status
    refute result.ok
    assert_includes result.message, '401'
  end

  def test_the_check_runs_weekly_and_by_hand
    # Given: the credential check workflow
    workflow = YAML.safe_load(read('.github/workflows/check-credentials.yml'))

    # When: its triggers are read
    triggers = workflow.fetch(true)

    # Then: it runs on a schedule and on manual dispatch
    assert triggers.key?('workflow_dispatch')
    refute_empty triggers.fetch('schedule')
  end

  def test_every_deployment_credential_is_checked
    # Given: the deployment workflow and the credential check workflow
    deployment = read('.github/workflows/update-profile.yml')
    check = read('.github/workflows/check-credentials.yml')

    # When: the credentials of both are compared
    unchecked = secrets_in(deployment) - secrets_in(check)

    # Then: every credential the deployment uses is also checked
    refute_empty secrets_in(deployment)
    assert_empty unchecked
  end

  def test_a_manual_deployment_deploys_every_target
    # Given: the deployment workflow
    workflow = YAML.safe_load(read('.github/workflows/update-profile.yml'))

    # When: it is dispatched by hand
    triggers = workflow.fetch(true)
    targets = workflow.dig('jobs', 'detect-changes', 'outputs')

    # Then: every target counts as changed, whatever the last commit touched
    assert triggers.key?('workflow_dispatch')
    refute_empty targets
    targets.each do |target, value|
      assert value.start_with?("${{ github.event_name == 'workflow_dispatch' || "), "#{target} depends on the last commit"
    end
  end

  def test_a_credential_is_recognized_in_every_reference_syntax
    # Given: a workflow that references credentials by property, by index, and with digits in their names
    workflow = <<~'YAML'
      env:
        A: ${{ secrets.DEPLOY_TOKEN_V2 }}
        B: ${{ secrets['NEW_DEPLOY_TOKEN'] }}
        C: ${{ secrets[ "OTHER_TOKEN" ] }}
        D: ${{ secrets.SITE_CITY }}
    YAML

    # When: its credentials are read
    credentials = secrets_in(workflow)

    # Then: every credential is found with its full name, and plain values are left out
    assert_equal %w[DEPLOY_TOKEN_V2 NEW_DEPLOY_TOKEN OTHER_TOKEN], credentials
  end

  def test_the_check_changes_nothing_at_a_target
    # Given: the credential check workflow and its write access script
    commands = read('.github/workflows/check-credentials.yml') + read('scripts/check-git-write-access.sh')

    # When: their commands are read
    pushes = commands.lines.select { |line| line.match?(/\bgit\b.*\bpush\b/) }

    # Then: every push is a dry run and nothing is uploaded
    refute_empty pushes
    assert(pushes.all? { |line| line.include?('--dry-run') })
    refute_match(/\b(mirror|put|rm)\b/, commands.sub(/rm -rf "\$workdir"/, ''))
  end
end
