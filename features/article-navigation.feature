# Living documentation for the article navigation generator (previous/next
# series links and related-article suggestions at the end of each article).
#
# Bridged to: test/profile_navigation_test.rb (classic Minitest, no native BDD
# runner in this repository). Each scenario maps to at least one automated test
# method named after the sanitized scenario title, with Given/When/Then comment
# anchors inside it. Traceability is a reviewer-verifiable convention, not a
# build-enforced link.

Feature: Article navigation
  As a reader of the profile articles
  I want previous/next series links and related-article suggestions at the end of an article
  So that I can navigate a series and discover articles that could also interest me

  Scenario: Article without matches produces an empty navigation file
    Given an article with a unique meaningful tag, no relations, and no series links
    When the article navigation is generated
    Then its navigation include file is empty

  Scenario: Previous and next series links are rendered from ids
    Given two articles linked as a series through previous and next ids
    When the article navigation is generated
    Then the first article links to the next article and the second links to the previous article

  Scenario: Related articles are collected from shared meaningful tags
    Given two articles that share a meaningful tag
    When the article navigation is generated
    Then each article lists the other under the related articles heading

  Scenario: Ubiquitous tags are ignored and reported
    Given an article whose only tag is the ubiquitous tag profile
    When the profile metamodel is validated and navigation is generated
    Then the validator warns about the ubiquitous tag and the article has no tag-based related articles

  Scenario: Related articles are limited to the five newest by relevance
    Given a hub article that shares a tag with six other public articles
    When the article navigation is generated
    Then the hub lists exactly the five newest related articles, newest first, and omits the oldest

  Scenario: Explicit relations rank above tag-only matches
    Given an article linked to another article by a relation and to further articles only by a shared tag
    When the article navigation is generated
    Then the relation-linked article is listed before the tag-only matches

  Scenario: Empty sections are omitted from the navigation
    Given an article that only has a previous series link and no related articles or next link
    When the article navigation is generated
    Then the navigation shows the previous section only and omits the related and next sections

  Scenario: Related articles exclude the previous and next articles
    Given an article whose next article also shares a meaningful tag with it
    When the article navigation is generated
    Then the next article is not repeated in the related articles list

  Scenario: Draft and private articles are excluded from related suggestions
    Given a published article that shares a tag with a draft article
    When the article navigation is generated
    Then the draft article is not suggested as related

  Scenario: Articles with the same basename in different directories do not collide
    Given two articles that share a basename in different directories
    When the article navigation is generated
    Then each article keeps its own navigation file next to it

  Scenario: Previous and next are rejected on non-article artifacts
    Given a non-article artifact that sets a next series link
    When the profile metamodel is validated
    Then the validator reports that previous and next are only allowed for articles

  Scenario: Unknown previous or next id is a validation error
    Given an article whose next id references a missing artifact
    When the profile metamodel is validated
    Then the validator reports the unknown series reference

  Scenario: Previous or next must reference an article
    Given an article whose next id references a non-article artifact
    When the profile metamodel is validated
    Then the validator reports that the series reference must be an article

  Scenario: Inconsistent series links produce a warning
    Given an article that declares a next article which does not point back to it
    When the profile metamodel is validated
    Then the validator warns about the inconsistent series link

  Scenario: Navigation output is deterministic
    Given a set of articles with tags and series links
    When the article navigation is generated twice
    Then both generations produce identical navigation files
