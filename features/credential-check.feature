# Living documentation for checking deployment credentials without deploying.
#
# Bridged to: test/credential_check_test.rb (classic Minitest). Each scenario maps
# to a test method named after the sanitized scenario title, with Given/When/Then
# comment anchors inside it.

Feature: Credential check
  As the operator of the site
  I want to check all deployment credentials without deploying
  So that an expired token shows up before it blocks a deployment

  Scenario: A token far from its expiry date passes
    Given a token that GitHub accepts and that expires in 30 days
    When its expiry is checked
    Then the check passes and names the expiry date

  Scenario: A token close to its expiry date fails early
    Given a token that GitHub accepts and that expires in 13 days
    When its expiry is checked
    Then the check fails and names the expiry date

  Scenario: A token without an expiry date passes
    Given a token that GitHub accepts and for which it reports no expiry date
    When its expiry is checked
    Then the check passes

  Scenario: A rejected token fails
    Given a token that GitHub rejects
    When its expiry is checked
    Then the check fails and names the HTTP status

  Scenario: The check runs weekly and by hand
    Given the credential check workflow
    When its triggers are read
    Then it runs on a schedule and on manual dispatch

  Scenario: Every deployment credential is checked
    Given the deployment workflow and the credential check workflow
    When the credentials of both are compared
    Then every credential the deployment uses is also checked

  Scenario: A manual deployment deploys every target
    Given the deployment workflow
    When it is dispatched by hand
    Then every target counts as changed, whatever the last commit touched

  Scenario: A credential is recognized in every reference syntax
    Given a workflow that references credentials by property, by index, and with digits in their names
    When its credentials are read
    Then every credential is found with its full name, and plain values are left out

  Scenario: The check changes nothing at a target
    Given the credential check workflow and its write access script
    When their commands are read
    Then every push is a dry run and nothing is uploaded
