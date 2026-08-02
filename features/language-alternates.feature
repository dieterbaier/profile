# Living documentation for making the language variants of a page discoverable:
# in the page chrome for readers, and in the HTML head for search engines.
#
# Bridged to: test/profile_language_alternates_test.rb and
# test/site_metadata_injector_test.rb (classic Minitest, no native BDD runner in
# this repository). Each scenario maps to at least one automated test method
# named after the sanitized scenario title, with Given/When/Then comment anchors
# inside it. Traceability is a reviewer-verifiable convention, not a
# build-enforced link.
#
# A variant only counts when the page really exists in that language. A page
# that merely falls back to the default language is not an alternate: offering
# it would promise a translation that was never written.

Feature: Language alternates
  As a reader who speaks another language, and as a search engine
  I want to find the language variants of a page
  So that I land on the right language and the variants are not treated as duplicates

  Scenario: Page with a translation offers a language switcher
    Given a page that exists in the default language and in one other language
    When the language switchers are generated
    Then each variant offers a link to the other and marks its own language as current

  Scenario: Page without a translation offers no language switcher
    Given a page that exists in the default language only
    When the language switchers are generated
    Then its language switcher file is empty

  Scenario: Fallback pages are not offered as translations
    Given a page that exists in the default language only
    And another page in that same site that has been translated
    When the language switchers are generated
    Then the untranslated page still offers no language switcher

  Scenario: Translation group is published as alternate links
    Given a rendered site whose page exists in two languages
    When the site metadata is injected
    Then each variant links to both variants as alternates and names the default language as x-default

  Scenario: Page without variants carries no alternate links
    Given a rendered site whose page exists in one language only
    When the site metadata is injected
    Then that page carries no alternate links

  Scenario: Alternate links leave canonical links untouched
    Given a rendered site whose page exists in two languages
    When the site metadata is injected
    Then each variant keeps the canonical URL of its own output path
