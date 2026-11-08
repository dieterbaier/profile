# Living documentation for checking deployment credentials without deploying.
#
# Bridged to: test/credential_check_test.rb (classic Minitest). Each scenario maps
# to a test method named after the sanitized scenario title, with Given/When/Then
# comment anchors inside it.

Feature: Credential check
  As the operator of the site
  I want to check all deployment credentials without deploying
  So that a wrongly renewed token shows up before it blocks a deployment

  Scenario: The check runs only by hand
    Given the credential check workflow
    When its triggers are read
    Then it runs on manual dispatch and on nothing else

  Scenario: Every deployment credential is checked
    Given the deployment workflow and the credential check workflow
    When the credentials of both are compared
    Then every credential the deployment uses is also checked

  Scenario: A credential is recognized in every reference syntax
    Given a workflow that references credentials by property, by index, and with digits in their names
    When its credentials are read
    Then every credential is found with its full name, and plain values are left out

  Scenario: The check changes nothing at a target
    Given the credential check workflow and its write access script
    When their commands are read
    Then every push is a dry run and nothing is uploaded
