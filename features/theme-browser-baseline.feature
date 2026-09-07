# Living documentation for keeping the theme inside the browser baseline the
# published site is read on.
#
# Bridged to: test/theme_browser_baseline_test.rb (classic Minitest, no native
# BDD runner in this repository). Each scenario maps to at least one automated
# test method named after the sanitized scenario title, with Given/When/Then
# comment anchors inside it. Traceability is a reviewer-verifiable convention,
# not a build-enforced link.
#
# This is the stylesheet counterpart of features/rendered-asset-references.feature
# and exists for the same reason: a failure nothing reports. A missing image is
# reported to a reader rather than to the build, and so is a CSS declaration the
# reading engine does not understand — dropping it silently is what makes CSS
# forward compatible, and it is also what lets a whole layout disappear on a
# device nobody develops on. Both were found by looking at the site, not by the
# pipeline.
#
# The baseline is a statement rather than a detection. It names the oldest
# engine the site is expected to render on and is the reason each rule exists;
# raising it is a decision, and the rules move with it.

Feature: Theme browser baseline
  As a reader on a television browser
  I want the theme to use only what my browser understands
  So that a menu I cannot read is found by the build rather than by me

  Scenario: Spacing an engine below the baseline drops is reported
    Given a rule that spaces its items with gap and says nothing about grid
    When the theme is checked
    Then the rule is reported with the property that carries the spacing

  Scenario: Row spacing is reported like column spacing
    Given a rule using row-gap and column-gap outside a grid
    When the theme is checked
    Then both properties are reported, because they are the same feature

  Scenario: A grid container may space its items with gap
    Given a rule that declares a grid display and spaces its items with gap
    When the theme is checked
    Then nothing is reported, because grid spacing predates the baseline

  Scenario: A grid adjusted without repeating its display is still a grid
    Given a rule that only changes the tracks of a grid and its spacing
    When the theme is checked
    Then nothing is reported, because the grid properties are the evidence

  Scenario: Spacing written as margins is accepted
    Given a flex container whose items carry their spacing as margins
    When the theme is checked
    Then nothing is reported

  Scenario: An emoji rendered as text is reported
    Given a rule whose content is an emoji
    When the theme is checked
    Then the rule is reported, because no font can be assumed to draw it

  Scenario: Naming the bundled emoji font does not make the rule acceptable
    Given the same rule with the emoji webfont in its font-family
    When the theme is checked
    Then it is still reported, because that font is one Chromium cannot draw

  Scenario: A flag drawn as an image is accepted
    Given a rule that draws the flag as a background image
    When the theme is checked
    Then nothing is reported

  Scenario: An interface term carrying an emoji is reported
    Given a term whose value is a flag
    When the theme is checked
    Then it is reported, because a term reaches the page as text

  Scenario: A term that carries no emoji is left alone
    Given the interface terms of a language without a flag among them
    When the theme is checked
    Then nothing is reported

  Scenario: A comment is not read as a rule
    Given a comment that talks about gap and about an emoji
    When the theme is checked
    Then nothing is reported, and the reported lines still match the file
