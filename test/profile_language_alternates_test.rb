# frozen_string_literal: true

# Behaviour specification bridge for the language switcher.
#
# Minitest is a classic (non-BDD) runner, so each test method name is a
# sanitized translation of a scenario title in features/language-alternates.feature,
# with Given/When/Then comment anchors separating Arrange, Act, and Assert. The
# alternate-link scenarios of the same feature are bridged in
# test/site_metadata_injector_test.rb, because they belong to the injector.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'yaml'

require_relative '../scripts/validate-profile-metamodel'

class ProfileLanguageAlternatesTest < Minitest::Test
  def with_pages(pages)
    Dir.mktmpdir('profile-alternates-test') do |dir|
      root = Pathname.new(dir)
      (root + 'includes/i18n').mkpath
      (root + 'includes/i18n/ui-de.adoc').write(":ui_nav_home: Home\n")
      (root + 'includes/i18n/ui-en.adoc').write(":ui_nav_home: Home\n")

      pages.each do |page|
        rel_dir = page.fetch(:dir)
        slug = page.fetch(:slug)
        (root + rel_dir).mkpath
        source = "#{rel_dir}/#{slug}.adoc"
        (root + source).write("= #{slug}\n")
        metadata = {
          'id' => page.fetch(:id), 'type' => 'ProfilePage', 'title' => slug, 'status' => 'published',
          'owner' => 'Test Owner', 'created' => '2026-01-01', 'language' => page.fetch(:language),
          'source' => source
        }
        metadata['translation_of'] = page[:translation_of] if page[:translation_of]
        (root + "#{rel_dir}/#{slug}.profile.yaml").write(metadata.to_yaml)
      end

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      artifacts = validator.validate
      yield(validator, artifacts, root)
    end
  end

  def switcher(root, relative)
    path = root + relative
    path.exist? ? path.read : ''
  end

  def test_page_with_a_translation_offers_a_language_switcher
    # Given: a page that exists in the default language and in one other language
    with_pages([
                 { id: 'PAGE-001-index', slug: 'index', dir: 'site', language: 'de' },
                 { id: 'PAGE-001-index-en', slug: 'index', dir: 'site/en', language: 'en',
                   translation_of: 'PAGE-001-index' }
               ]) do |validator, artifacts, root|
      # When: the language switchers are generated
      validator.generate_language_switchers(artifacts)

      # Then: each variant links to the other and marks its own language as current
      german = switcher(root, 'site/generated/index-langswitch.adoc')
      english = switcher(root, 'site/en/generated/index-langswitch.adoc')

      # Rendered as menu list items: a flag as the visible label, the language
      # name on title and aria-label, because a flag is no accessible name.
      # One list item holds every language, so the menu row's single gap cannot
      # push the flags apart. A flag is the visible label only; the language name
      # stays on title and aria-label, because a flag is no accessible name.
      assert_includes german, '<li class="language-switch">'
      assert_includes german, '<span class="language-switch-current" lang="de" title="{ui_language_name_de}"'
      assert_match(%r{<a href="[^"]*en/index\.html" lang="en"[^>]*>\{ui_language_flag_en\}</a>}, german)
      assert_includes english, '<span class="language-switch-current" lang="en"'
      assert_match(%r{<a href="[^"]*index\.html" lang="de"[^>]*>\{ui_language_flag_de\}</a>}, english)
      assert_equal 1, german.scan('<li class="language-switch">').length
    end
  end

  # The listings are generated pages without metadata. Basing the switcher on
  # artifacts left exactly those pages without one, which is what made a second,
  # differently shaped switcher look necessary in the first place.
  def test_generated_listing_pages_offer_the_switcher_as_well
    # Given: published articles in two languages
    Dir.mktmpdir('profile-alternates-listing-test') do |dir|
      root = Pathname.new(dir)
      (root + 'includes/i18n').mkpath
      %w[de en].each do |language|
        (root + "includes/i18n/ui-#{language}.adoc").write(
          ":ui_article_list_all: All\n:ui_article_list_tag_prefix: Tag:\n:ui_article_list_skill_prefix: Skill:\n"
        )
      end

      [['ART-001-de', 'site/articles', 'de'], ['ART-002-en', 'site/en/articles', 'en']].each do |id, rel_dir, language|
        (root + rel_dir).mkpath
        source = "#{rel_dir}/entry.adoc"
        (root + source).write("= entry\n")
        (root + "#{rel_dir}/entry.profile.yaml").write({
          'id' => id, 'type' => 'Article', 'title' => id, 'status' => 'published', 'owner' => 'Test Owner',
          'created' => '2026-01-01', 'language' => language, 'source' => source
        }.to_yaml)
      end

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      artifacts = validator.validate
      validator.generate_article_lists(artifacts)

      # When: the language switchers are generated
      validator.generate_language_switchers(artifacts)

      # Then: the generated article listings of each language offer the switcher too
      german = switcher(root, 'site/articles/generated/pages/generated/all-langswitch.adoc')
      english = switcher(root, 'site/en/articles/generated/pages/generated/all-langswitch.adoc')

      assert_match(%r{<a href="\.\./\.\./en/articles/lists/all\.html"}, german)
      assert_match(%r{<a href="\.\./\.\./\.\./articles/lists/all\.html"}, english)
    end
  end

  def test_page_without_a_translation_offers_no_language_switcher
    # Given: a page that exists in the default language only
    with_pages([{ id: 'PAGE-001-index', slug: 'index', dir: 'site', language: 'de' }]) do |validator, artifacts, root|
      # When: the language switchers are generated
      validator.generate_language_switchers(artifacts)

      # Then: its language switcher file is empty
      assert_empty switcher(root, 'site/generated/index-langswitch.adoc')
    end
  end

  def test_fallback_pages_are_not_offered_as_translations
    # Given: a page that exists in the default language only
    # And: another page in that same site that has been translated
    with_pages([
                 { id: 'PAGE-002-legal', slug: 'legal', dir: 'site', language: 'de' },
                 { id: 'PAGE-001-index', slug: 'index', dir: 'site', language: 'de' },
                 { id: 'PAGE-001-index-en', slug: 'index', dir: 'site/en', language: 'en',
                   translation_of: 'PAGE-001-index' }
               ]) do |validator, artifacts, root|
      # When: the language switchers are generated
      validator.generate_language_switchers(artifacts)

      # Then: the untranslated page still offers no language switcher
      assert_empty switcher(root, 'site/generated/legal-langswitch.adoc')
      refute_empty switcher(root, 'site/generated/index-langswitch.adoc')
    end
  end
end
