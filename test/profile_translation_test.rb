# frozen_string_literal: true

# Behaviour specification bridge for translation provenance.
#
# Minitest is a classic (non-BDD) runner, so each test method name is a
# sanitized translation of a scenario title in
# features/article-translation-provenance.feature, with Given/When/Then comment
# anchors separating Arrange, Act, and Assert. Each test builds an isolated
# temporary profile tree so the real repository is never touched.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'yaml'

require_relative '../scripts/validate-profile-metamodel'

class ProfileTranslationTest < Minitest::Test
  # Builds an original and, optionally, a translation of it. The translation's
  # recorded digest is computed from the original's source unless the test asks
  # for a stale one.
  def with_translation(original_body: "= Original\nText.\n", digest: :current, divergence: nil, translated: true)
    Dir.mktmpdir('profile-translation-test') do |dir|
      root = Pathname.new(dir)
      (root + 'includes/i18n').mkpath
      (root + 'includes/i18n/ui-de.adoc').write(":ui_nav_home: Home\n")
      (root + 'includes/i18n/ui-en.adoc').write(":ui_nav_home: Home\n")

      (root + 'site/articles').mkpath
      (root + 'site/articles/original.adoc').write(original_body)
      (root + 'site/articles/original.profile.yaml').write(metadata('ART-001-original', 'de', 'site/articles/original.adoc'))

      if translated
        recorded = digest == :current ? Digest::SHA256.hexdigest(original_body) : digest
        (root + 'site/en/articles').mkpath
        (root + 'site/en/articles/original.adoc').write("= Original\nText.\n")
        extra = { 'translation_of' => 'ART-001-original' }
        extra['translation_source_digest'] = recorded unless recorded.nil?
        extra['translation_divergence'] = divergence if divergence
        (root + 'site/en/articles/original.profile.yaml').write(
          metadata('ART-001-original-en', 'en', 'site/en/articles/original.adoc', extra)
        )
      end

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      artifacts = validator.validate
      yield(validator, artifacts, root)
    end
  end

  def metadata(id, language, source, extra = {})
    {
      'id' => id, 'type' => 'Article', 'title' => id, 'status' => 'published',
      'owner' => 'Test Owner', 'created' => '2026-01-01', 'language' => language, 'source' => source
    }.merge(extra).to_yaml
  end

  def note(root, relative)
    path = root + relative
    path.exist? ? path.read : ''
  end

  def test_original_article_shows_no_provenance_note
    # Given: an article that was not translated from another article
    with_translation(translated: false) do |validator, artifacts, root|
      # When: the translation notes are generated
      validator.generate_translation_notes(artifacts)

      # Then: its translation note file is empty
      assert_empty note(root, 'site/articles/generated/original-translation.adoc')
    end
  end

  def test_translation_names_the_article_it_came_from
    # Given: a translation whose recorded digest matches its original
    with_translation do |validator, artifacts, root|
      # When: the translation notes are generated
      validator.generate_translation_notes(artifacts)

      # Then: its note states that the article is a translation and links to the original
      generated = note(root, 'site/en/articles/generated/original-translation.adoc')
      assert_includes generated, '{ui_translation_of}'
      assert_match(%r{<a href="[^"]*original\.html">}, generated)
      refute_includes generated, '{ui_translation_outdated}'
    end
  end

  def test_changed_original_marks_its_translations_as_outdated
    # Given: a translation whose original has changed since the translation was written
    with_translation(digest: 'b' * 64) do |validator, artifacts, root|
      # When: the translation notes are generated
      validator.generate_translation_notes(artifacts)
      validator.report_translation_states(artifacts)

      # Then: its note additionally states that the original has changed,
      # and the outdated translation is reported to the author
      generated = note(root, 'site/en/articles/generated/original-translation.adoc')
      assert_includes generated, '{ui_translation_of}'
      assert_includes generated, '{ui_translation_outdated}'
      assert validator.warnings.any? { |warning| warning.include?('is outdated') },
             "expected an outdated warning, got: #{validator.warnings.inspect}"
    end
  end

  def test_outdated_translation_stays_publishable
    # Given: a translation whose original has changed since the translation was written
    with_translation(digest: 'b' * 64) do |validator, _artifacts, _root|
      # When: the profile metadata is validated (done by the helper)
      # Then: validation reports no error
      assert_empty validator.errors
    end
  end

  def test_re_accepting_the_original_clears_the_outdated_note
    # Given: a translation whose original has changed since the translation was written
    with_translation(digest: 'b' * 64) do |validator, artifacts, root|
      # When: the author re-accepts the current original for that translation
      validator.accept_translation(artifacts, 'ART-001-original-en')

      # Then: its note no longer states that the original has changed
      revalidated = ProfileArtifactValidator.new(root: root, profile_dir: root)
      reloaded = revalidated.validate
      revalidated.generate_translation_notes(reloaded)

      generated = note(root, 'site/en/articles/generated/original-translation.adoc')
      assert_includes generated, '{ui_translation_of}'
      refute_includes generated, '{ui_translation_outdated}'
    end
  end

  def test_deliberate_divergence_is_shown_even_when_the_translation_is_in_sync
    # Given: a translation that declares a deliberate difference from its original
    with_translation(divergence: 'shortened for the web') do |validator, artifacts, root|
      # When: the translation notes are generated
      validator.generate_translation_notes(artifacts)

      # Then: its note states that the content differs from the original
      generated = note(root, 'site/en/articles/generated/original-translation.adoc')
      assert_includes generated, '{ui_translation_divergent}'
      refute_includes generated, '{ui_translation_outdated}'
    end
  end

  def test_outdated_and_deliberately_different_are_shown_together
    # Given: a translation that declares a deliberate difference and whose original has changed
    with_translation(digest: 'b' * 64, divergence: 'shortened for the web') do |validator, artifacts, root|
      # When: the translation notes are generated
      validator.generate_translation_notes(artifacts)

      # Then: its note states both that the original has changed and that the content differs
      generated = note(root, 'site/en/articles/generated/original-translation.adoc')
      assert_includes generated, '{ui_translation_outdated}'
      assert_includes generated, '{ui_translation_divergent}'
    end
  end
end
