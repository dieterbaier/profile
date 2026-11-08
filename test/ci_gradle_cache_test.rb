# frozen_string_literal: true

# Behaviour specification bridge for the CI Gradle cache.
#
# Bridged from features/ci-gradle-cache.feature by the sanitized scenario title.

require 'minitest/autorun'
require 'yaml'

class CiGradleCacheTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def workflow
    YAML.safe_load(File.read(File.join(ROOT, '.github/workflows/update-profile.yml')))
  end

  def cache_paths(job)
    job.fetch('steps')
       .select { |step| step['uses'].to_s.start_with?('actions/cache@') }
       .flat_map { |step| step.dig('with', 'path').to_s.lines.map(&:strip).reject(&:empty?) }
  end

  def gradle_jobs
    workflow.fetch('jobs').select do |_, job|
      job.fetch('steps', []).any? { |step| step['run'].to_s.match?(%r{\./(build\.sh|gradlew)\b}) }
    end
  end

  def test_every_cache_path_resolves
    # Given: the deployment workflow
    jobs = workflow.fetch('jobs')

    # When: the paths of its cache steps are read
    paths = jobs.values.flat_map { |job| cache_paths(job) }

    # Then: no path uses an environment variable, because actions/cache does not expand one
    refute_empty paths
    assert_empty paths.select { |path| path.include?('$') }
  end

  def test_every_gradle_job_caches_the_wrapper_distribution
    # Given: the deployment workflow
    # When: the jobs that run the build are read
    jobs = gradle_jobs

    # Then: each of them caches the Gradle wrapper distribution
    refute_empty jobs
    jobs.each do |name, job|
      assert_includes cache_paths(job), '~/.gradle/wrapper', "#{name} downloads Gradle on every run"
    end
  end

  def test_the_wrapper_waits_for_a_slow_download
    # Given: the Gradle wrapper properties
    properties = File.read(File.join(ROOT, 'gradle/wrapper/gradle-wrapper.properties'))

    # When: the network timeout is read
    timeout = properties[/^networkTimeout=(\d+)$/, 1]

    # Then: the wrapper waits 60 seconds instead of the default 10
    assert_equal '60000', timeout
  end
end
