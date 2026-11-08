# Living documentation for the badges in the generated profile README.
#
# Bridged to: test/readme_badges_test.rb (classic Minitest). Each scenario maps
# to a test method named after the sanitized scenario title, with Given/When/Then
# comment anchors inside it.

Feature: README badges
  As the owner of the profile
  I want the badges in the generated README to render as images
  So that a newer Pandoc does not turn them into text

  Scenario: Badges are images in the source
    Given the profile sources
    When they are searched for a badge written as an exclamation mark before a link
    Then none is found, because Pandoc 3 escapes that exclamation mark

  Scenario: Remote badges keep their URL
    Given the Pandoc call that converts the README to Markdown
    When its options are read
    Then it does not extract media, so a badge keeps its shields.io URL
