# Living documentation for the runtime of the GitHub Actions in this repository.
#
# Bridged to: test/ci_action_runtime_test.rb (classic Minitest). Each scenario maps
# to a test method named after the sanitized scenario title, with Given/When/Then
# comment anchors inside it.

Feature: CI action runtime
  As the maintainer of the build
  I want every workflow to use actions that run on Node.js 24
  So that removing Node.js 20 from the runners does not stop a deployment

  Scenario: Every workflow action runs on Node.js 24
    Given all workflows of this repository
    When their actions are compared with the first major version that runs on Node.js 24
    Then none of them is older

  Scenario: A workflow file ending in yaml is checked too
    Given a repository whose workflow file ends in .yaml and uses an older action
    When its workflows are read and their actions compared
    Then the action is reported

  Scenario: An action older than its Node.js 24 version is reported
    Given a workflow that uses an action below its first Node.js 24 version
    When its actions are compared
    Then the action is reported

  Scenario: An action with an unknown runtime is reported
    Given a workflow that uses an action nobody has checked
    When its actions are compared
    Then the action is reported, so that its runtime gets checked

  Scenario: The site artifact keeps its hidden files
    Given the deployment workflow
    When its artifact upload is read
    Then it includes hidden files, because the site carries a .htaccess
