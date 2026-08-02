# Living documentation for how a page gets its wording and its page references in
# the reader's language.
#
# Bridged to: test/profile_language_test.rb (classic Minitest, no native BDD
# runner in this repository). Each scenario maps to at least one automated test
# method named after the sanitized scenario title, with Given/When/Then comment
# anchors inside it. Traceability is a reviewer-verifiable convention, not a
# build-enforced link.
#
# Two classes with deliberately opposite rules, decided in ADR-010: a link
# leading to a page in the default language is still usable, so it falls back and
# says so. Interface wording has nowhere to say it, so a missing term fails the
# build instead. Content fragments are the third class and do not fall back at
# all; they are specified in features/content-fragment-languages.feature.

Feature: Language chrome
  As a reader of a page in my language
  I want its wording and its links to follow that language
  So that the page is coherent and no link leads me nowhere

  Scenario: Interface wording of a language must be complete
    Given content in a language whose interface terms are missing a key
    When the profile metadata is validated
    Then validation reports the missing key and the language

  Scenario: A language that has content must have interface terms
    Given content in a language that has no interface terms at all
    When the profile metadata is validated
    Then validation reports the missing interface terms

  Scenario: Page reference resolves to the same-language page
    Given a page that exists in the default language and in one other language
    When the link registries are generated
    Then the reference of each language resolves to that language's page and carries no marker

  Scenario: Page reference falls back and names the language it leads to
    Given a page that exists in the default language only
    When the link registries are generated
    Then the other language resolves the reference to the default-language page and marks it

  Scenario: A reference no page can satisfy is rejected
    Given a page referencing a target that no page provides
    When the profile metadata is validated
    Then validation reports the unknown page reference

  Scenario: Article chrome takes its wording from the page it lands on
    Given articles that share a meaningful tag
    When the per-article includes are generated
    Then their navigation and comment wording is left to the page's interface terms
