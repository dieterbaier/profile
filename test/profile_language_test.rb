# frozen_string_literal: true

# Validator tests for the language and translation dimension of the profile
# metamodel.
#
# These rules are author-facing: they decide which metadata the build accepts,
# not what a reader sees. There is therefore no Gherkin feature bridged here,
# unlike the navigation, listing, and comment generators. Each test builds an
# isolated temporary profile tree so the real repository is never touched.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'yaml'

require_relative '../scripts/validate-profile-metamodel'

class ProfileLanguageTest < Minitest::Test
  DIGEST = 'a' * 64

  # Every profile tree owes default interface terms, so the helper writes a
  # minimal set unless a test states its own. Pass an empty mapping to build a
  # tree without any interface terms at all.
  DEFAULT_UI_TERMS = { 'de' => { 'ui_nav_home' => 'Home' } }.freeze

  # Content in a second language requires that language's interface terms, so
  # tests that publish English content supply both sets.
  BILINGUAL_UI_TERMS = {
    'de' => { 'ui_nav_home' => 'Home' },
    'en' => { 'ui_nav_home' => 'Home' }
  }.freeze

  # Builds an isolated profile tree from lightweight artifact descriptions and
  # yields the validated validator. :ui_terms maps a language to key/value pairs.
  def with_artifacts(artifacts, ui_terms: DEFAULT_UI_TERMS)
    Dir.mktmpdir('profile-language-test') do |dir|
      root = Pathname.new(dir)

      ui_terms.each do |language, terms|
        (root + 'includes/i18n').mkpath
        # Attribute entries only: these files are included into the document
        # header, where a comment or blank line would end it.
        body = terms.map { |key, value| ":#{key}: #{value}\n" }.join
        (root + "includes/i18n/ui-#{language}.adoc").write(body)
      end

      artifacts.each do |artifact|
        slug = artifact.fetch(:slug)
        rel_dir = artifact.fetch(:dir, 'site/articles')
        (root + rel_dir).mkpath
        source_rel = "#{rel_dir}/#{slug}.adoc"
        (root + source_rel).write("= #{artifact.fetch(:title, slug)}\n")
        (root + "#{rel_dir}/#{slug}.profile.yaml").write(metadata_yaml(artifact, source_rel))
      end

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      validator.validate
      yield(validator)
    end
  end

  def metadata_yaml(artifact, source_rel)
    metadata = {
      'id' => artifact.fetch(:id),
      'type' => artifact.fetch(:type, 'Article'),
      'title' => artifact.fetch(:title, artifact.fetch(:slug)),
      'status' => artifact.fetch(:status, 'published'),
      'owner' => 'Test Owner',
      'created' => '2026-01-01',
      'source' => source_rel
    }
    %i[language translation_of translation_source_digest translation_divergence].each do |field|
      metadata[field.to_s] = artifact[field] if artifact.key?(field)
    end
    metadata.to_yaml
  end

  def assert_error_matching(validator, pattern)
    assert validator.errors.any? { |error| error.match?(pattern) },
           "expected an error matching #{pattern.inspect}, got: #{validator.errors.inspect}"
  end

  # An original in the default language plus its translation in the language
  # subtree is the reference case and must validate cleanly.
  def test_accepts_original_and_translation_pair
    with_artifacts(
      [
        { id: 'ART-001-example', slug: 'example', language: 'de' },
        { id: 'ART-001-example-en', slug: 'example', dir: 'site/en/articles', language: 'en',
          translation_of: 'ART-001-example', translation_source_digest: DIGEST }
      ],
      ui_terms: BILINGUAL_UI_TERMS
    ) do |validator|
      assert_empty validator.errors
    end
  end

  # Absent language metadata keeps meaning the default language, so existing
  # single-language content stays valid without being touched.
  def test_accepts_absent_language_at_default_location
    with_artifacts([{ id: 'ART-001-example', slug: 'example' }]) do |validator|
      assert_empty validator.errors
    end
  end

  def test_rejects_language_that_contradicts_the_location
    with_artifacts([
                     { id: 'ART-001-example', slug: 'example', dir: 'site/en/articles', language: 'de' }
                   ]) do |validator|
      assert_error_matching(validator, /declares 'language: de', but its location implies 'en'/)
    end
  end

  def test_rejects_missing_language_in_a_language_subtree
    with_artifacts([
                     { id: 'ART-001-example', slug: 'example', dir: 'site/en/articles' }
                   ]) do |validator|
      assert_error_matching(validator, /must declare 'language: en'/)
    end
  end

  def test_rejects_unknown_translation_target
    with_artifacts([
                     { id: 'ART-001-example-en', slug: 'example', dir: 'site/en/articles', language: 'en',
                       translation_of: 'ART-999-missing' }
                   ]) do |validator|
      assert_error_matching(validator, /references unknown artifact 'ART-999-missing'/)
    end
  end

  def test_rejects_self_reference
    with_artifacts([
                     { id: 'ART-001-example', slug: 'example', language: 'de', translation_of: 'ART-001-example' }
                   ]) do |validator|
      assert_error_matching(validator, /must not reference the artifact itself/)
    end
  end

  def test_rejects_translation_cycle
    with_artifacts([
                     { id: 'ART-001-example', slug: 'example', language: 'de',
                       translation_of: 'ART-001-example-en' },
                     { id: 'ART-001-example-en', slug: 'example', dir: 'site/en/articles', language: 'en',
                       translation_of: 'ART-001-example' }
                   ]) do |validator|
      assert_error_matching(validator, /forms a translation cycle/)
    end
  end

  # A translation must point at the original directly, so provenance stays a
  # single hop and the reader-facing note names the real source text.
  def test_rejects_translation_of_a_translation
    with_artifacts([
                     { id: 'ART-001-example', slug: 'example', language: 'de' },
                     { id: 'ART-001-example-en', slug: 'example', dir: 'site/en/articles', language: 'en',
                       translation_of: 'ART-001-example' },
                     { id: 'ART-001-example-en-copy', slug: 'copy', dir: 'site/en/articles', language: 'en',
                       translation_of: 'ART-001-example-en' }
                   ]) do |validator|
      assert_error_matching(validator, /is itself a translation/)
    end
  end

  def test_rejects_translation_in_the_same_language_as_its_original
    with_artifacts([
                     { id: 'ART-001-example', slug: 'example', language: 'de' },
                     { id: 'ART-001-example-copy', slug: 'copy', language: 'de',
                       translation_of: 'ART-001-example' }
                   ]) do |validator|
      assert_error_matching(validator, /both are written in 'de'/)
    end
  end

  # The original may be in any language: an English original translated into
  # German must validate, because the default language is only the fallback
  # target, not the assumed source language.
  def test_accepts_english_original_translated_into_german
    with_artifacts(
      [
        { id: 'ART-001-example-en', slug: 'example', dir: 'site/en/articles', language: 'en' },
        { id: 'ART-001-example', slug: 'example', language: 'de',
          translation_of: 'ART-001-example-en', translation_source_digest: DIGEST }
      ],
      ui_terms: BILINGUAL_UI_TERMS
    ) do |validator|
      assert_empty validator.errors
    end
  end

  def test_rejects_translation_fields_without_translation_of
    with_artifacts([
                     { id: 'ART-001-example', slug: 'example', language: 'de',
                       translation_source_digest: DIGEST, translation_divergence: 'shortened for the web' }
                   ]) do |validator|
      assert_error_matching(validator, /'translation_source_digest' is only allowed on a translation/)
      assert_error_matching(validator, /'translation_divergence' is only allowed on a translation/)
    end
  end

  def test_rejects_malformed_digest
    with_artifacts([
                     { id: 'ART-001-example', slug: 'example', language: 'de' },
                     { id: 'ART-001-example-en', slug: 'example', dir: 'site/en/articles', language: 'en',
                       translation_of: 'ART-001-example', translation_source_digest: 'not-a-digest' }
                   ]) do |validator|
      assert_error_matching(validator, /'translation_source_digest' must match/)
    end
  end

  # 'mixed' is gone from the vocabulary: a page may only include fragments of
  # its own language, so an artifact is always written in exactly one language.
  def test_rejects_mixed_language
    with_artifacts([{ id: 'ART-001-example', slug: 'example', language: 'mixed' }]) do |validator|
      assert_error_matching(validator, /unknown language 'mixed'/)
    end
  end

  # Interface terms are the one class that must never fall back: a menu label has
  # nowhere to tell the reader it is showing another language.
  def test_accepts_complete_interface_terms
    with_artifacts(
      [{ id: 'ART-001-example', slug: 'example', language: 'de' }],
      ui_terms: {
        'de' => { 'ui_nav_home' => 'Home', 'ui_toc_title' => 'Inhalt' },
        'en' => { 'ui_nav_home' => 'Home', 'ui_toc_title' => 'Contents' }
      }
    ) do |validator|
      assert_empty validator.errors
    end
  end

  def test_rejects_missing_interface_term
    with_artifacts(
      [{ id: 'ART-001-example', slug: 'example', language: 'de' }],
      ui_terms: {
        'de' => { 'ui_nav_home' => 'Home', 'ui_toc_title' => 'Inhalt' },
        'en' => { 'ui_nav_home' => 'Home' }
      }
    ) do |validator|
      assert_error_matching(validator, /ui-en\.adoc is missing interface term\(s\): ui_toc_title/)
    end
  end

  # A key that exists only in a translation is usually a typo in the key name,
  # which would otherwise silently render as an unresolved attribute.
  def test_rejects_interface_term_unknown_to_the_default_language
    with_artifacts(
      [{ id: 'ART-001-example', slug: 'example', language: 'de' }],
      ui_terms: {
        'de' => { 'ui_nav_home' => 'Home' },
        'en' => { 'ui_nav_home' => 'Home', 'ui_nav_hom' => 'Home' }
      }
    ) do |validator|
      assert_error_matching(validator, /defines interface term\(s\) unknown to .*ui-de\.adoc: ui_nav_hom/)
    end
  end

  # Content in a language without interface terms would render German chrome
  # around a translated page, so the missing file is an error rather than a gap.
  def test_rejects_content_language_without_interface_terms
    with_artifacts(
      [
        { id: 'ART-001-example', slug: 'example', language: 'de' },
        { id: 'ART-001-example-en', slug: 'example', dir: 'site/en/articles', language: 'en',
          translation_of: 'ART-001-example' }
      ],
      ui_terms: { 'de' => { 'ui_nav_home' => 'Home' } }
    ) do |validator|
      assert_error_matching(validator, /en content exists, but its interface terms are missing/)
    end
  end

  # docheader.adoc includes the default terms unconditionally, so a missing
  # directory breaks every page. It must produce the same contract error as a
  # missing file rather than silently skipping the whole check.
  def test_rejects_missing_interface_terms_directory
    with_artifacts([{ id: 'ART-001-example', slug: 'example', language: 'de' }], ui_terms: {}) do |validator|
      assert_error_matching(validator, %r{missing interface terms for the default language: includes/i18n/ui-de\.adoc})
    end
  end

  def test_rejects_missing_default_interface_terms_file
    with_artifacts(
      [{ id: 'ART-001-example', slug: 'example', language: 'de' }],
      ui_terms: { 'en' => { 'ui_nav_home' => 'Home' } }
    ) do |validator|
      assert_error_matching(validator, /missing interface terms for the default language/)
    end
  end

  # Interface term files are included into the AsciiDoc document header, where a
  # blank or comment line ends the header and silently disables ':stylesheet:'
  # and ':copycss:' further down. The site then renders with the default
  # Asciidoctor theme, so the format is validated instead of trusted.
  def test_rejects_blank_and_comment_lines_in_interface_terms
    Dir.mktmpdir('profile-language-test') do |dir|
      root = Pathname.new(dir)
      (root + 'includes/i18n').mkpath
      (root + 'includes/i18n/ui-de.adoc').write(":ui_nav_home: Home\n\n// a group\n:ui_toc_title: Inhalt\n")

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      validator.validate

      assert_error_matching(validator, /line 2: a blank line ends the AsciiDoc header/)
      assert_error_matching(validator, /line 3: a comment line inside a header include ends the header/)
    end
  end

  # A language nobody writes in yet needs no interface terms.
  def test_accepts_missing_interface_terms_for_unused_language
    with_artifacts(
      [{ id: 'ART-001-example', slug: 'example', language: 'de' }],
      ui_terms: { 'de' => { 'ui_nav_home' => 'Home' } }
    ) do |validator|
      assert_empty validator.errors
    end
  end
end
