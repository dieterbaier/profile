# Living documentation for translation provenance: telling a reader that the
# article they are on is a translation, which text it came from, and whether it
# still matches that text.
#
# Bridged to: test/profile_translation_test.rb (classic Minitest, no native BDD
# runner in this repository). Each scenario maps to at least one automated test
# method named after the sanitized scenario title, with Given/When/Then comment
# anchors inside it. Traceability is a reviewer-verifiable convention, not a
# build-enforced link.
#
# Default language and original language are separate concepts: 'de' is the
# fallback target for missing translations, while the original is whatever
# language the article was written in first. An article written in English and
# translated into German afterwards is an English original.

Feature: Article translation provenance
  As a reader of a translated article
  I want to see that it is a translation and whether it still matches its original
  So that I can judge how current and complete the text in front of me is

  Scenario: Original article shows no provenance note
    Given an article that was not translated from another article
    When the translation notes are generated
    Then its translation note file is empty

  Scenario: Translation names the article it came from
    Given a translation whose recorded digest matches its original
    When the translation notes are generated
    Then its note states that the article is a translation and links to the original

  Scenario: Changed original marks its translations as outdated
    Given a translation whose original has changed since the translation was written
    When the translation notes are generated
    Then its note additionally states that the original has changed
    And the outdated translation is reported to the author

  Scenario: Outdated translation stays publishable
    Given a translation whose original has changed since the translation was written
    When the profile metadata is validated
    Then validation reports no error

  Scenario: Re-accepting the original clears the outdated note
    Given a translation whose original has changed since the translation was written
    When the author re-accepts the current original for that translation
    Then its note no longer states that the original has changed

  Scenario: Deliberate divergence is shown even when the translation is in sync
    Given a translation that declares a deliberate difference from its original
    When the translation notes are generated
    Then its note states that the content differs from the original

  Scenario: Outdated and deliberately different are shown together
    Given a translation that declares a deliberate difference and whose original has changed
    When the translation notes are generated
    Then its note states both that the original has changed and that the content differs
