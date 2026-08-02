# Living documentation for the language rule on reusable content fragments.
#
# Bridged to: test/profile_language_test.rb (classic Minitest, no native BDD
# runner in this repository). Each scenario maps to at least one automated test
# method named after the sanitized scenario title, with Given/When/Then comment
# anchors inside it.
#
# Fragments are the one class that does not fall back. A link leading to a German
# page is still usable, so it falls back and says so; a German paragraph inside
# an English page is not, so the build stops instead of producing a page in mixed
# languages. That is the trade-off ADR-010 records: a page is all-or-nothing,
# while translation itself can progress fragment by fragment.

Feature: Content fragment languages
  As a reader of a page in my language
  I want its body to be in that language throughout
  So that I never hit a paragraph I cannot read in the middle of a page

  Scenario: A fragment missing in the page language stops the build
    Given a page including a fragment that exists only in the default language
    When the profile metadata is validated
    Then validation reports the fragment, the page and the language

  Scenario: A fragment of another language stops the build
    Given a page including a fragment of a different language directly
    When the profile metadata is validated
    Then validation reports that a page may only include fragments of its own language

  Scenario: A translated fragment is accepted
    Given a page including a fragment that exists in the page language
    When the profile metadata is validated
    Then validation reports no error

  Scenario: Fragments reached through attributes are checked too
    Given a page whose fragment chain ends in an attribute-driven include
    When the profile metadata is validated
    Then validation reports the missing fragment at the end of that chain

  Scenario: Untranslated fragments nobody includes are reported as coverage
    Given fragments that are not translated and no page including them
    When the profile metadata is validated
    Then validation reports the untranslated fragments as a warning without failing
