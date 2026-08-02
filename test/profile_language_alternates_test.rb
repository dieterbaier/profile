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

      assert_includes german, '<span class="language-switch-current" lang="de">'
      assert_match(%r{<a href="[^"]*en/index\.html" lang="en"}, german)
      assert_includes english, '<span class="language-switch-current" lang="en">'
      assert_match(%r{<a href="[^"]*index\.html" lang="de"}, english)
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
