# Living documentation for selecting article sources into a publication target.
#
# Bridged to: test/profile_publication_status_test.rb (classic Minitest, no
# native BDD runner in this repository). Each scenario maps to a test method
# named after the sanitized scenario title, with Given/When/Then comment anchors
# inside it. Traceability is a reviewer-verifiable convention, not a
# build-enforced link.
#
# The rule comes from ADR-008: the public target carries status published and
# nothing else. Selection is by metadata rather than by location, so an article
# is kept out of a target by what it says about itself. Absence here means the
# page is not built at all - it has no URL, rather than merely no link.

Feature: Article selection by publication status
  As the owner of the profile publishing system
  I want the public site to be selected from article metadata
  So that an article is public because it says so, not because it exists

  Scenario: A published article is rendered into the public target
    Given an article whose status is published
    When the public article selection is computed
    Then its source is not excluded from the public target

  Scenario: An article of any other status is kept out of the public target
    Given articles with the statuses draft, proposed, preview, reviewed, private, archived, and deprecated
    When the public article selection is computed
    Then every one of their sources is excluded from the public target

  Scenario: A language variant is selected on its own status
    Given a published article and an unpublished translation of it
    When the public article selection is computed
    Then only the translation's source is excluded from the public target

  Scenario: A page that is not an article is never excluded
    Given a profile page and a short thought alongside an unpublished article
    When the public article selection is computed
    Then only the article's source is excluded from the public target

  Scenario: Exclusions name the source file rather than the metadata file
    Given an article whose metadata lives in a sidecar next to its source
    When the public article selection is computed
    Then the excluded path is the article source, not the sidecar

  Scenario: Only published articles appear in public listings and navigation
    Given a published article and a preview article sharing a tag
    When the article listings and navigation are generated
    Then the preview article appears in neither

  Scenario: A published article may not point at an unpublished part of its series
    Given a published article whose next article is still a draft
    When the profile metadata is validated
    Then validation fails naming both articles and the draft status

  Scenario: An article sidecar that does not name its source stops the build
    Given an article sidecar without a source field
    When the profile metadata is validated
    Then validation fails naming the sidecar

  Scenario: An article sidecar whose source does not exist stops the build
    Given an article sidecar naming a source file that is absent
    When the profile metadata is validated
    Then validation fails naming the sidecar
