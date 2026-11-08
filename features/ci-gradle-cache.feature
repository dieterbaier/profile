# Living documentation for reusing the Gradle distribution in CI.
#
# Bridged to: test/ci_gradle_cache_test.rb (classic Minitest). Each scenario maps
# to a test method named after the sanitized scenario title, with Given/When/Then
# comment anchors inside it.

Feature: CI Gradle cache
  As the maintainer of the build
  I want CI to reuse the Gradle distribution
  So that a slow download server does not fail a build

  Scenario: Every cache path resolves
    Given the deployment workflow
    When the paths of its cache steps are read
    Then no path uses an environment variable, because actions/cache does not expand one

  Scenario: Every Gradle job caches the wrapper distribution
    Given the deployment workflow
    When the jobs that run the build are read
    Then each of them caches the Gradle wrapper distribution

  Scenario: The wrapper waits for a slow download
    Given the Gradle wrapper properties
    When the network timeout is read
    Then the wrapper waits 60 seconds instead of the default 10
