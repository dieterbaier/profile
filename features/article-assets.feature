# Living documentation for the files an article owns.
#
# Bridged to: test/profile_article_assets_test.rb (classic Minitest, no native
# BDD runner in this repository). Each scenario maps to a test method named
# after the sanitized scenario title, with Given/When/Then comment anchors
# inside it. Traceability is a reviewer-verifiable convention, not a
# build-enforced link.
#
# The rule follows ADR-008 and ADR-009 read together. Selection is by metadata
# rather than by location, and an article is promoted between two repositories
# rather than copied. Naming an asset directory after the article's ID serves
# both: the page and the files it asks for are chosen by one rule, and every
# reference to them is relative, so moving the article moves its assets without
# rewriting anything.

Feature: Article assets
  As the owner of the profile publishing system
  I want an article's assets to be selected and moved with the article itself
  So that a page and the files it asks for can never disagree about being public

  Scenario: A rendered article publishes the directory named after it
    Given a published article with an asset directory named after its ID
    When the public asset selection is computed
    Then that directory is published

  Scenario: An article a target must not render leaves its assets behind
    Given a draft article, which the public target must not carry
    When the public asset selection is computed
    Then its assets are not published either

  Scenario: The private target publishes assets of the statuses it renders
    Given one article of each status, in a tree the private target reads
    When the private asset selection is computed
    Then it carries the assets of exactly the statuses it renders

  Scenario: A translation owns its own directory and its own status
    Given a published article and an unpublished translation of it
    When the public asset selection is computed
    Then only the original's directory is published

  Scenario: An article without assets contributes no directory
    Given a published article that owns no asset directory
    When the public asset selection is computed
    Then nothing is named, rather than a path that does not exist

  Scenario: A directory no article claims is reported
    Given an asset directory whose name matches no article's ID
    When the tree is validated
    Then it is an error rather than an unused file

  Scenario: A directory of an unpublished article is claimed rather than orphaned
    Given a draft article with an asset directory
    When the tree is validated
    Then nothing is reported, because its status is not a mistake in the tree
