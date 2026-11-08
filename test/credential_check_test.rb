# frozen_string_literal: true

# Behaviour specification bridge for the credential check.
#
# Bridged from features/credential-check.feature by the sanitized scenario title.

require 'minitest/autorun'
require 'yaml'

class CredentialCheckTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
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

  def test_the_check_runs_only_by_hand
    # Given: the credential check workflow
    workflow = YAML.safe_load(read('.github/workflows/check-credentials.yml'))

    # When: its triggers are read
    triggers = workflow.fetch(true)

    # Then: it runs on manual dispatch and on nothing else
    assert_equal ['workflow_dispatch'], triggers.keys
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
