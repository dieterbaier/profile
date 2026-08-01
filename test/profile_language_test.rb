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

  # Builds an isolated profile tree from lightweight artifact descriptions and
  # yields the validated validator.
  def with_artifacts(artifacts)
    Dir.mktmpdir('profile-language-test') do |dir|
      root = Pathname.new(dir)

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
    with_artifacts([
                     { id: 'ART-001-example', slug: 'example', language: 'de' },
                     { id: 'ART-001-example-en', slug: 'example', dir: 'site/en/articles', language: 'en',
                       translation_of: 'ART-001-example', translation_source_digest: DIGEST }
                   ]) do |validator|
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
    with_artifacts([
                     { id: 'ART-001-example-en', slug: 'example', dir: 'site/en/articles', language: 'en' },
                     { id: 'ART-001-example', slug: 'example', language: 'de',
                       translation_of: 'ART-001-example-en', translation_source_digest: DIGEST }
                   ]) do |validator|
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
end
