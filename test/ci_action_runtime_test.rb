# frozen_string_literal: true

# Behaviour specification bridge for the CI action runtime.
#
# Bridged from features/ci-action-runtime.feature by the sanitized scenario title.

require 'minitest/autorun'
require 'yaml'

class CiActionRuntimeTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  # First major version whose action.yml says node24. Read from each action's
  # action.yml on 2026-11-09. A new action belongs here once its runtime is checked.
  FIRST_NODE24_MAJOR = {
    'actions/cache' => 5,
    'actions/checkout' => 5,
    'actions/download-artifact' => 7,
    'actions/upload-artifact' => 6,
    'dorny/paths-filter' => 4
  }.freeze

  def actions_in(workflow)
    workflow.fetch('jobs').values.flat_map { |job| job.fetch('steps', []) }.filter_map { |step| step['uses'] }
  end

  def outdated(actions)
    actions.uniq.reject do |action|
      name, version = action.split('@', 2)
      minimum = FIRST_NODE24_MAJOR[name]
      minimum && version.to_s[/\Av(\d+)/, 1].to_i >= minimum
    end
  end

  def workflow_from(action)
    { 'jobs' => { 'job' => { 'steps' => [{ 'uses' => action }] } } }
  end

  def test_every_workflow_action_runs_on_node_js_24
    # Given: all workflows of this repository
    workflows = Dir[File.join(ROOT, '.github/workflows/*.yml')].map { |path| YAML.safe_load(File.read(path)) }
    refute_empty workflows

    # When: their actions are compared with the first major version that runs on Node.js 24
    actions = workflows.flat_map { |workflow| actions_in(workflow) }

    # Then: none of them is older
    refute_empty actions
    assert_empty outdated(actions)
  end

  def test_an_action_older_than_its_node_js_24_version_is_reported
    # Given: a workflow that uses an action below its first Node.js 24 version
    workflow = workflow_from('actions/checkout@v4')

    # When: its actions are compared
    reported = outdated(actions_in(workflow))

    # Then: the action is reported
    assert_equal ['actions/checkout@v4'], reported
  end

  def test_an_action_with_an_unknown_runtime_is_reported
    # Given: a workflow that uses an action nobody has checked
    workflow = workflow_from('someone/unknown-action@v9')

    # When: its actions are compared
    reported = outdated(actions_in(workflow))

    # Then: the action is reported, so that its runtime gets checked
    assert_equal ['someone/unknown-action@v9'], reported
  end

  def test_the_site_artifact_keeps_its_hidden_files
    # Given: the deployment workflow
    workflow = YAML.safe_load(File.read(File.join(ROOT, '.github/workflows/update-profile.yml')))

    # When: its artifact upload is read
    steps = workflow.fetch('jobs').values.flat_map { |job| job.fetch('steps', []) }
    upload = steps.find { |step| step['uses'].to_s.start_with?('actions/upload-artifact@') }

    # Then: it includes hidden files, because the site carries a .htaccess
    refute_nil upload
    assert_equal true, upload.dig('with', 'include-hidden-files')
  end
end
