# Living documentation for checking a rendered target against its own pages.
#
# Bridged to: test/rendered_asset_references_test.rb (classic Minitest, no
# native BDD runner in this repository). Each scenario maps to a test method
# named after the sanitized scenario title, with Given/When/Then comment anchors
# inside it. Traceability is a reviewer-verifiable convention, not a
# build-enforced link.
#
# Selecting an asset into a target is metadata work and is specified in
# article-assets.feature. This is the other end of the same guarantee, and it is
# separate because the two fail independently: assets selected correctly can
# still be copied to the wrong place, and a converter can rewrite references
# while it moves files. Neither is reported by a renderer — a missing image
# reaches the reader rather than the build — so the target is asked directly.

Feature: Rendered asset references
  As the owner of the profile publishing system
  I want every published target checked against what its own pages request
  So that a broken image is found by the build rather than by a reader

  Scenario: A page whose image is in the target is accepted
    Given a page next to the image it asks for
    When the target is checked
    Then nothing is reported

  Scenario: A page whose image is absent is reported
    Given a page asking for an image the target does not contain
    When the target is checked
    Then it is reported with the page and the line it stands on

  Scenario: A reference is resolved relative to the page that makes it
    Given a page reaching out of its own directory, as the Markdown export does
    When the target is checked
    Then the reference resolves rather than being read from the target root

  Scenario: An external reference is not hosted by the target
    Given pages linking to other hosts, inline data, and an anchor
    When the target is checked
    Then none of them is reported

  Scenario: A reference that is not an asset is left alone
    Given a page linking to another page and a stylesheet
    When the target is checked
    Then nothing is reported

  Scenario: A markdown image is checked like an HTML one
    Given a Markdown page using the native image syntax
    When the target is checked
    Then it is reported, because the export renders both forms

  Scenario: A manifest the pages link to is checked like an image
    Given a page linking the web app manifest of its target
    When the target is checked
    Then it is reported when the target does not hold the manifest

  Scenario: The icons a manifest names are checked
    Given a manifest in the target naming an icon the target does not hold
    When the target is checked
    Then it is reported against the manifest and the line the icon stands on

  Scenario: A manifest entry that names a page is left alone
    Given a manifest whose start URL and scope name no file
    When the target is checked
    Then nothing is reported, because only a file can be absent

  Scenario: A percent-encoded reference names the file it encodes
    Given a page asking for a file whose name carries a space
    When the target is checked
    Then it resolves, because only the decoded form names a file

  Scenario: A query or fragment is not part of the file name
    Given a page cache-busting an image it does contain
    When the target is checked
    Then it resolves rather than being reported as a missing file

  Scenario: A reference that leaves the target is missing even when the file exists
    Given a page climbing out of the target at a file that is really there
    When the target is checked
    Then it is reported as having left the target, not as resolved

  Scenario: A sibling target whose name extends this one is not mistaken for it
    Given two targets side by side, one named as a prefix of the other
    When the shorter-named target is checked
    Then the reference counts as outside it

  Scenario: A target that was never rendered reports nothing
    Given no rendered target at all
    When a directory that does not exist is checked
    Then nothing is reported
