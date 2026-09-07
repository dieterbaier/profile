# Living documentation for addressing the theme's stylesheets and scripts by a
# URL that changes when they do.
#
# Bridged to: test/theme_asset_versioning_test.rb (classic Minitest, no native
# BDD runner in this repository). Each scenario maps to at least one automated
# test method named after the sanitized scenario title, with Given/When/Then
# comment anchors inside it. Traceability is a reviewer-verifiable convention,
# not a build-enforced link.
#
# The third check asked of a rendered target rather than of the sources that
# produced it, next to features/rendered-asset-references.feature and
# features/theme-browser-baseline.feature. The failures they cover share one
# shape: the build succeeds, the page renders, and only a reader finds out.
#
# Here the reader is a returning one. The stylesheet URL never changed, so a
# browser holding the previous file went on using it against freshly fetched
# HTML. That went unnoticed while the markup could stand on its own; since the
# language switcher names its flag as a class for the stylesheet to draw, the
# two are of one generation and a mismatch renders a switcher with nothing in
# it.

Feature: Theme asset versioning
  As a reader who has been on this site before
  I want a changed theme to reach me rather than the one I already have
  So that a page is never rendered by a stylesheet from a previous deploy

  Scenario: The version follows the content of the theme
    Given two themes whose stylesheets differ
    When each is versioned
    Then the versions differ

  Scenario: The same theme is versioned the same way
    Given the same theme read twice
    When each is versioned
    Then the version is identical, so unchanged files keep their caches

  Scenario: Renaming a file changes the version
    Given a theme whose file was renamed but not edited
    When it is versioned
    Then the version changes, because the old name is now a different URL

  Scenario: Only stylesheets and scripts are versioned
    Given a theme holding a font and an image next to its stylesheet
    When its assets are collected
    Then only the stylesheet and the script are among them

  Scenario: A reference carrying the current version is accepted
    Given a page linking the stylesheet with the current version
    When the target is checked
    Then nothing is reported

  Scenario: A reference without a version is reported
    Given a page linking the stylesheet by its plain name
    When the target is checked
    Then it is reported with the file and the line it stands on

  Scenario: A reference carrying a previous version is reported
    Given a page linking the stylesheet with the version of an earlier deploy
    When the target is checked
    Then it is reported, because that URL serves what the reader already holds

  Scenario: A stylesheet importing another one is checked like a page
    Given a stylesheet in the target importing the vendored framework
    When the target is checked
    Then its import is checked, because no page mentions that file

  Scenario: A file name written in prose is not a reference
    Given a page that mentions article-comments.js in a sentence
    When the target is checked
    Then nothing is reported, because a name in prose asks for no file

  Scenario: A name that ends in another asset's name is not mistaken for it
    Given a page linking shortsmenuactivation.css with the current version
    When the target is checked
    Then menuactivation.css is not reported inside it

  Scenario: A file whose name carries the version is reported
    Given a target holding a stylesheet written as style.css?v=<version>
    When the target is checked
    Then it is reported, because a version addresses a file rather than naming it

  Scenario: A target that was never rendered reports nothing
    Given no rendered target at all
    When a directory that does not exist is checked
    Then nothing is reported
