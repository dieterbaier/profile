# Living documentation for https://github.com/dieterbaier/profile/issues/44[feature #44]: GitHub-backed article comments.
#
# Bridged to: test/profile_comments_test.rb (classic Minitest). Each scenario maps
# to a test method named after its sanitized title with Given/When/Then anchors.

Feature: GitHub-backed article comments
  As a reader of a profile article
  I want to comment through a prefilled GitHub issue
  So that I can give public, article-specific feedback without a website backend

  Scenario: Each article receives a prefilled comment link
    Given a metadata-backed article
    When profile artifacts are generated
    Then its comment block opens the dedicated GitHub issue form with article id, title, and current page URL

  Scenario: Existing comments can be requested explicitly
    Given an article comment block on the static website
    When the reader requests existing comments
    Then the local enhancement loads issues carrying the comment and article id labels and presents their headings as links

  Scenario: Non-website article exports omit the comment block
    Given a generated article comment include
    When the article is rendered for a non-website target
    Then the website-only comment block is omitted
