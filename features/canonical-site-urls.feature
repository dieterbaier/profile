# Living documentation for canonical URLs in the generated public site.
#
# Bridged to: test/site_metadata_injector_test.rb (classic Minitest). Each
# scenario maps to a test method named after the sanitized scenario title, with
# Given/When/Then comment anchors inside it.

Feature: Canonical URLs for the public site
  As the owner of the profile publishing system
  I want public pages to identify their canonical deployment URL
  So that search engines consolidate each page under its official URL

  Scenario: Public pages receive canonical URLs derived from their output paths
    Given a generated public site and a configured HTTPS base URL
    When public site metadata is injected
    Then each HTML page links to its canonical URL below that base URL

  Scenario: Index pages use directory canonical URLs
    Given generated index pages at the site root and in a subdirectory
    When public site metadata is injected
    Then their canonical URLs omit index.html

  Scenario: Special characters in output paths are percent encoded
    Given a generated public page whose output path contains spaces and non-ASCII characters
    When public site metadata is injected
    Then each path segment is percent encoded in the canonical URL

  Scenario: Local builds may omit canonical URLs without a base URL
    Given a local site build without a configured base URL
    When public site metadata injection is invoked
    Then the build succeeds without adding canonical links

  Scenario: Production builds require a configured base URL
    Given a production site build without a configured base URL
    When public site metadata injection is invoked
    Then the build fails before deployment

  Scenario: Language subtree pages keep their language prefix in the canonical url
    Given a generated public site whose pages exist below a language prefix
    When public site metadata is injected
    Then each variant keeps its own prefix in the canonical URL

