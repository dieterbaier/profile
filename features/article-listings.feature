# Living documentation for the generated article listings (the article landing
# page's "recent" list plus the standalone overview pages for all articles, each
# tag, and each skill).
#
# Bridged to: test/profile_listings_test.rb (classic Minitest, no native BDD
# runner in this repository). Each scenario maps to at least one automated test
# method named after the sanitized scenario title, with Given/When/Then comment
# anchors inside it. Traceability is a reviewer-verifiable convention, not a
# build-enforced link.

Feature: Article listings
  As a visitor of the profile website
  I want generated article lists on the landing page and dedicated overview pages per tag and per skill
  So that I can browse recent articles and drill into a topic or skill

  Scenario: Recent listing shows the newest public articles limited to ten
    Given twelve public articles with distinct publication dates
    When the article lists are generated
    Then the recent fragment lists the ten newest articles, newest first, and omits the two oldest

  Scenario: A list entry shows title link, summary, publication date, and tag links
    Given a public article with a title, summary, publication date, and tags
    When the article lists are generated
    Then its recent entry links the title to the article, shows the summary and formatted date, and links each tag to its tag page

  Scenario: Publication date falls back to the creation date
    Given a public article without a published date
    When the article lists are generated
    Then its listed date is derived from the creation date

  Scenario: Summary is language specific with a fallback
    Given one article with a German summary and one article with only the neutral summary
    When the article lists are generated in German
    Then the first entry shows the German summary and the second entry shows the neutral summary

  Scenario: Only public articles appear in listings
    Given a published article and a draft article
    When the article lists are generated
    Then the draft article does not appear in any listing

  Scenario: Listings are sorted by publication date descending with an id tiebreak
    Given three public articles, two sharing the same publication date
    When the article lists are generated
    Then the all-articles page orders them by date descending and breaks ties by id

  Scenario: A tag overview page lists every article carrying that tag
    Given two public articles sharing a tag and one article without it
    When the article lists are generated
    Then the tag page lists the two tagged articles and omits the third

  Scenario: A skill overview page lists articles and humanizes the skill heading
    Given a public article carrying a hyphenated skill slug
    When the article lists are generated
    Then a skill page exists for that slug, lists the article, and shows the slug with spaces as its heading

  Scenario: Removed tags and skills do not leave stale pages behind
    Given article lists were generated for a tag and a skill that later disappear
    When the article lists are generated again without that tag and skill
    Then the stale tag and skill pages are removed

  Scenario: Article listings are deterministic
    Given a set of public articles with tags and skills
    When the article lists are generated twice
    Then both generations produce identical listing files
