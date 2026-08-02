# Living documentation for the CV as a multilingual artifact: its shared chrome
# follows the reader's language, and the downloadable PDF belongs to the language
# variant it was rendered from.
#
# Bridged to: test/profile_cv_language_test.rb (classic Minitest, no native BDD
# runner in this repository). Each scenario maps to at least one automated test
# method named after the sanitized scenario title, with Given/When/Then comment
# anchors inside it.
#
# The CV pulls in more content fragments than any other page, and fragments do
# not fall back. A CV language variant is therefore publishable only once every
# fragment it includes is translated, which is authoring work rather than
# generator work.

Feature: Multilingual CV
  As someone handing my CV to an international employer
  I want the CV in the reader's language, with its own PDF
  So that I can pass on one coherent document instead of a mixed-language one

  Scenario: CV download link points at the PDF of its own language variant
    Given a CV that exists in the default language and in one other language
    When the link registries are generated
    Then each language resolves the CV download to the PDF beside its own CV page

  Scenario: CV download link falls back with the default language marked
    Given a CV that exists in the default language only
    When the link registries are generated
    Then the other language resolves the CV download to the default-language PDF

  Scenario: CV chrome wording is resolved by the page it lands on
    Given the shared CV chrome
    Then it carries no wording of its own, only interface terms

  Scenario: CV language variant is blocked until its fragments are translated
    Given a CV language variant that includes a fragment available only in the default language
    When the profile metadata is validated
    Then validation reports that the fragment is missing in the variant's language
