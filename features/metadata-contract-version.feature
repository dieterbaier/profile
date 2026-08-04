# Living documentation for the metadata contract version an artifact declares.
#
# Bridged to: test/profile_metadata_version_test.rb (classic Minitest, no native
# BDD runner in this repository). Each scenario maps to a test method named after
# the sanitized scenario title, with Given/When/Then comment anchors inside it.
# Traceability is a reviewer-verifiable convention, not a build-enforced link.
#
# The rule comes from ADR-009. Promotion may run with the public repository's
# validator applied to private content from a separate checkout, and nothing in
# that arrangement notices when the checkout is older than the content beside it.
# The declared version is what turns that into a named failure. It only works
# while it is enforced, so the contract lives in the schema and the validator
# reads it from there.

Feature: Metadata contract version
  As the owner of the profile publishing system
  I want every artifact to declare a contract version the validator enforces
  So that content and the checkout validating it cannot disagree in silence

  Scenario: An artifact declaring an accepted contract version passes validation
    Given an artifact declaring a contract version this checkout accepts
    When the profile metadata is validated
    Then validation reports no error about the contract version

  Scenario: An artifact declaring an unsupported contract version is rejected by name
    Given an artifact declaring a contract version this checkout does not accept
    When the profile metadata is validated
    Then validation fails naming the artifact, the declared version, and the accepted versions

  Scenario: An artifact that declares no contract version fails validation
    Given an artifact with no contract version at all
    When the profile metadata is validated
    Then validation fails naming the artifact and the missing field

  Scenario: The accepted versions come from the metamodel schema
    Given a metamodel schema listing the contract versions it accepts
    When the accepted versions are read
    Then they are the versions the schema lists

  Scenario: A schema that names no accepted versions stops the validator
    Given a metamodel schema whose contract version field lists no versions
    When the accepted versions are read
    Then reading fails naming the schema instead of assuming a version

  Scenario: Content is judged by the contract of the checkout validating it
    Given content whose own metamodel accepts a version this checkout does not
    When the profile metadata is validated
    Then the declared version is rejected against this checkout's accepted versions
