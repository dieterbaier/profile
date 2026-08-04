# Living documentation for rendering the private content root locally.
#
# Bridged to two files, because the rules live in two places (classic Minitest,
# no native BDD runner in this repository). Each scenario maps to a test method
# named after the sanitized scenario title, with Given/When/Then comment anchors
# inside it. Traceability is a reviewer-verifiable convention, not a
# build-enforced link.
#
#   test/profile_private_target_test.rb      - selection, interface terms, noindex
#   test/private_checkout_contract_test.rb   - the sibling-checkout contract, which
#                                              lives in the build and is therefore
#                                              verified by running the build
#
# The rules come from ADR-009 and ADR-008. The private repository holds content
# and nothing else; it reaches this repository's tooling through a sibling
# checkout. The target that results is read locally and deployed nowhere, which
# is why it may carry drafts and why every page in it must say that it is not
# the official location of anything.

Feature: Private content target
  As the owner of the profile publishing system
  I want the private repository's content rendered with this repository's tooling
  So that I can read a draft as a finished page before deciding anything about it

  Scenario: The private target renders drafts alongside published articles
    Given private, preview, and published articles in the private content root
    When the private article selection is computed
    Then none of their sources is excluded from the private target

  Scenario: A status that belongs to no target is kept out of the private one
    Given articles with the statuses draft, proposed, reviewed, archived, and deprecated
    When the private article selection is computed
    Then every one of their sources is excluded from the private target

  Scenario: An article the private target renders is still absent from the public one
    Given a private article and a preview article
    When the public article selection is computed
    Then both of their sources are excluded from the public target

  Scenario: Interface terms come from the tree that owns them
    Given a content root without interface terms and a separate tree that has them
    When the profile metadata is validated against that includes tree
    Then validation passes without the content root holding a copy

  Scenario: A content root with no interface terms anywhere stops the build
    Given a content root and an includes tree that both lack interface terms
    When the profile metadata is validated
    Then validation fails naming the interface terms it expected

  Scenario: Every page of the private target is marked as not to be indexed
    Given a rendered target whose pages carry a canonical link
    When the target is marked as not indexed
    Then every page carries a robots noindex tag and no canonical link

  Scenario: Marking a target twice leaves one robots tag
    Given a rendered target that was already marked as not indexed
    When the target is marked as not indexed again
    Then each page carries exactly one robots tag

  Scenario: A target cannot be both unindexed and canonical
    Given a request to mark a target as not indexed
    When a base URL is supplied with it
    Then the request is refused rather than resolved in favour of one of them

  Scenario: Output of an article the private target must not contain is reported
    Given a rendered private target holding the page of a draft article
    When the rendered target is checked against the private status set
    Then that page is reported

  Scenario: The private target is checked where it is rendered, not where its content lives
    Given private content in one tree and its rendered target in another
    When the rendered target is checked
    Then the reported path is relative to the tree holding the target

  Scenario: A missing sibling checkout names the path it expected
    Given no checkout at the configured path
    When the private target is asked for
    Then the build stops naming what it expected and where

  Scenario: A checkout without a content root names the directory it expected
    Given a checkout that exists but carries no content root
    When the private target is asked for
    Then the build stops naming the content root it expected

  Scenario: A checkout carrying its own tooling stops the build
    Given a private checkout with a schema of its own
    When the private target is asked for
    Then the build stops and names the copy it found

  Scenario: An absent sibling leaves the rest of the build alone
    Given no private checkout at the configured path
    When a task that has nothing to do with the private target runs
    Then it succeeds, because a checkout without the sibling is an ordinary state
