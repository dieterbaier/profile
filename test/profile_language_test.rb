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
require 'json'
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

  # Listing titles are baked into generated pages, so those tests need the
  # terms the generator reads.
  LIST_TERMS_DE = {
    'ui_nav_home' => 'Home',
    'ui_article_list_all' => 'Alle Artikel',
    'ui_article_list_tag_prefix' => 'Artikel mit dem Tag:',
    'ui_article_list_skill_prefix' => 'Artikel zum Thema:'
  }.freeze

  LIST_TERMS_EN = {
    'ui_nav_home' => 'Home',
    'ui_article_list_all' => 'All articles',
    'ui_article_list_tag_prefix' => 'Articles tagged:',
    'ui_article_list_skill_prefix' => 'Articles about:'
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
      artifacts = validator.validate
      yield(validator, root, artifacts)
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
    %i[language translation_of translation_source_digest translation_divergence tags channels].each do |field|
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

  # A page reference resolves to the same-language page where one exists and to
  # the default language otherwise, so it always leads somewhere. The fallback is
  # marked with the language it leads to.
  def test_link_registry_resolves_per_language_and_marks_fallbacks
    with_artifacts(
      [
        { id: 'PAGE-001-index', slug: 'index', dir: 'site', type: 'ProfilePage', language: 'de' },
        { id: 'PAGE-002-legal', slug: 'legal', dir: 'site', type: 'ProfilePage', language: 'de' },
        { id: 'PAGE-001-index-en', slug: 'index', dir: 'site/en', type: 'ProfilePage', language: 'en',
          translation_of: 'PAGE-001-index' }
      ],
      ui_terms: BILINGUAL_UI_TERMS
    ) do |validator, root, artifacts|
      validator.generate_link_registries(artifacts)
      english = (root + 'includes/generated/i18n/links-en.adoc').read

      # The translated page wins and carries no marker.
      assert_includes english, ":url_index: {basedir}/en/index.html\n"
      assert_includes english, ":url_index_lang: en\n"
      assert_includes english, ":url_index_marker:\n"

      # The untranslated page falls back and says which language it leads to.
      assert_includes english, ":url_legal: {basedir}/legal.html\n"
      assert_includes english, ":url_legal_lang: de\n"
      assert_includes english, ":url_legal_marker: {nbsp}(de)\n"

      assert validator.warnings.any? { |warning| warning.include?('legal.html') },
             "expected a fallback warning, got: #{validator.warnings.inspect}"
    end
  end

  # The registry is included into the AsciiDoc document header. ':name:value'
  # without the space is not an attribute entry and would end the header, leaving
  # every later reference unresolved and the site on the default theme.
  def test_link_registry_contains_only_attribute_entries
    with_artifacts(
      [
        { id: 'PAGE-001-index', slug: 'index', dir: 'site', type: 'ProfilePage', language: 'de' },
        { id: 'PAGE-001-index-en', slug: 'index', dir: 'site/en', type: 'ProfilePage', language: 'en',
          translation_of: 'PAGE-001-index' }
      ],
      ui_terms: BILINGUAL_UI_TERMS
    ) do |validator, root, artifacts|
      validator.generate_link_registries(artifacts).each do |path|
        path.read.lines.each_with_index do |line, index|
          assert_match(/\A:[a-z0-9_]+:(\s\S.*)?\n\z/, line,
                       "#{path.basename} line #{index + 1} is not an attribute entry: #{line.inspect}")
        end
      end
    end
  end

  def test_rejects_unknown_page_reference
    Dir.mktmpdir('profile-language-test') do |dir|
      root = Pathname.new(dir)
      (root + 'includes/i18n').mkpath
      (root + 'includes/i18n/ui-de.adoc').write(":ui_nav_home: Home\n")
      (root + 'site').mkpath
      (root + 'site/index.adoc').write("= Index\nlink:{url_does_not_exist}[Gone]\n")

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      validator.validate

      assert_error_matching(validator, /unknown page reference '\{url_does_not_exist\}'/)
    end
  end

  # Builds a tree with a page and fragment files, and validates it.
  def with_fragments(pages:, fragments:)
    Dir.mktmpdir('profile-fragment-test') do |dir|
      root = Pathname.new(dir)
      (root + 'includes/i18n').mkpath
      (root + 'includes/i18n/ui-de.adoc').write(":ui_nav_home: Home\n")
      (root + 'includes/i18n/ui-en.adoc').write(":ui_nav_home: Home\n")

      fragments.each do |relative, body|
        path = root + "includes/i18n/#{relative}"
        path.dirname.mkpath
        path.write(body)
      end

      pages.each do |relative, body|
        path = root + "site/#{relative}"
        path.dirname.mkpath
        path.write(body)
      end

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      validator.validate
      yield(validator)
    end
  end

  # A link leading to a German page is usable, so it falls back. A German
  # paragraph inside an English page is not, so the build stops instead.
  def test_rejects_fragment_missing_in_the_page_language
    with_fragments(
      pages: { 'en/index.adoc' => "= Index\ninclude::{includesdir}/i18n/{lang}/profile/bio.adoc[]\n" },
      fragments: { 'de/profile/bio.adoc' => "Deutscher Text\n" }
    ) do |validator|
      assert_error_matching(validator, /is written in 'en', but the fragment 'profile\/bio\.adoc' is not available in 'en'/)
    end
  end

  def test_rejects_fragment_of_another_language
    with_fragments(
      pages: { 'en/index.adoc' => "= Index\ninclude::{includesdir}/i18n/de/profile/bio.adoc[]\n" },
      fragments: { 'de/profile/bio.adoc' => "Deutscher Text\n" }
    ) do |validator|
      assert_error_matching(validator, /includes the 'de' fragment .*a page may only include fragments of its own language/)
    end
  end

  def test_accepts_fragment_translated_into_the_page_language
    with_fragments(
      pages: { 'en/index.adoc' => "= Index\ninclude::{includesdir}/i18n/{lang}/profile/bio.adoc[]\n" },
      fragments: {
        'de/profile/bio.adoc' => "Deutscher Text\n",
        'en/profile/bio.adoc' => "English text\n"
      }
    ) do |validator|
      assert_empty validator.errors
    end
  end

  # Fragments reached through an attribute-driven include must be checked too;
  # the CV builds its project and experience entries that way.
  def test_follows_attribute_driven_and_nested_includes
    with_fragments(
      pages: { 'en/index.adoc' => "= Index\ninclude::{includesdir}/i18n/{lang}/projects/list.adoc[]\n" },
      fragments: {
        'de/projects/list.adoc' => "include::entry/master.adoc[]\n",
        'de/projects/entry/master.adoc' => ":entry-file: entry/body.adoc\ninclude::../entry.adoc[]\n",
        'de/projects/entry.adoc' => "include::{entry-file}[]\n",
        'de/projects/entry/body.adoc' => "Deutscher Text\n",
        'en/projects/list.adoc' => "include::entry/master.adoc[]\n",
        'en/projects/entry/master.adoc' => ":entry-file: entry/body.adoc\ninclude::../entry.adoc[]\n",
        'en/projects/entry.adoc' => "include::{entry-file}[]\n"
      }
    ) do |validator|
      # The English body is the only missing file in the chain and must be named.
      assert_error_matching(validator, %r{fragment 'projects/entry/body\.adoc' is not available in 'en'})
    end
  end

  # Untranslated fragments nobody includes are a gap, not a failure.
  def test_reports_untranslated_fragments_as_coverage_warning
    with_fragments(
      pages: { 'en/index.adoc' => "= Index\n" },
      fragments: { 'de/profile/bio.adoc' => "Deutscher Text\n" }
    ) do |validator|
      assert_empty validator.errors
      assert validator.warnings.any? { |warning| warning.match?(/en: 1 of 1 content fragment/) },
             "expected a coverage warning, got: #{validator.warnings.inspect}"
    end
  end

  # Listings are built per language: a reader browsing the English listings
  # should not be handed German articles.
  def test_article_listings_are_generated_per_language
    with_artifacts(
      [
        { id: 'ART-001-de', slug: 'first', dir: 'site/articles', language: 'de', tags: %w[architecture] },
        { id: 'ART-001-en', slug: 'first', dir: 'site/en/articles', language: 'en', tags: %w[architecture],
          translation_of: 'ART-001-de' }
      ],
      ui_terms: {
        'de' => LIST_TERMS_DE,
        'en' => LIST_TERMS_EN
      }
    ) do |validator, root, artifacts|
      validator.generate_article_lists(artifacts)

      german = (root + 'site/articles/generated/pages/all.adoc').read
      english = (root + 'site/en/articles/generated/pages/all.adoc').read

      # Each listing is titled in its own language and lists only its own articles.
      assert_includes german, '= Alle Artikel'
      assert_includes german, 'first.html'
      refute_includes german, 'en/articles'

      assert_includes english, '= All articles'
      assert_includes english, 'first.html'

      assert_includes (root + 'site/en/articles/generated/pages/tag-architecture.adoc').read, '= Articles tagged: architecture'
      assert_includes (root + 'site/articles/generated/pages/tag-architecture.adoc').read, '= Artikel mit dem Tag: architecture'
    end
  end

  # Article chrome resolves its wording through the page it lands on, so a
  # translated article gets translated navigation without a second generator pass.
  def test_article_chrome_wording_is_resolved_by_the_page
    with_artifacts(
      [
        { id: 'ART-001-de', slug: 'first', dir: 'site/articles', language: 'de', tags: %w[architecture] },
        { id: 'ART-002-de', slug: 'second', dir: 'site/articles', language: 'de', tags: %w[architecture] }
      ]
    ) do |validator, root, artifacts|
      validator.generate_article_navigation(artifacts)
      validator.generate_article_comment_includes(artifacts)

      navigation = (root + 'site/articles/generated/first-navigation.adoc').read
      comments = (root + 'site/articles/generated/first-comments.adoc').read

      assert_includes navigation, '[subs="attributes"]'
      assert_includes navigation, 'aria-label="{ui_article_nav_label}"'
      assert_includes navigation, '{ui_article_nav_related}'
      assert_includes comments, '{ui_comments_heading}'
      assert_includes comments, '{ui_comments_create}'
      refute_match(/Könnte Sie auch interessieren|Kommentare<|Diesen Artikel kommentieren/, navigation + comments)
    end
  end

  # A recommendation is swapped for its variant in the reader's language, and one
  # that exists only in the default language is still offered - marked.
  def test_related_articles_prefer_the_page_language_and_mark_the_rest
    with_artifacts(
      [
        { id: 'ART-001-de', slug: 'first', dir: 'site/articles', language: 'de', tags: %w[architecture] },
        { id: 'ART-001-en', slug: 'first', dir: 'site/en/articles', language: 'en', tags: %w[architecture],
          translation_of: 'ART-001-de' },
        { id: 'ART-002-de', slug: 'second', dir: 'site/articles', language: 'de', tags: %w[architecture] },
        { id: 'ART-003-en', slug: 'third', dir: 'site/en/articles', language: 'en', tags: %w[architecture] }
      ],
      ui_terms: BILINGUAL_UI_TERMS
    ) do |validator, root, artifacts|
      validator.generate_article_navigation(artifacts)
      english = (root + 'site/en/articles/generated/third-navigation.adoc').read

      # The English variant of ART-001 wins over its German original, unmarked.
      assert_includes english, 'first.html'
      # ART-002 exists in German only and is offered with its language marked.
      assert_match(/second\.html">[^<]*&#160;\(de\)</, english)
    end
  end

  # Each language variant is its own artifact, so its comment thread and its
  # allowlist entry follow from its own ID without any extra rule.
  def test_comment_threads_are_separate_per_language_variant
    with_artifacts(
      [
        { id: 'ART-001-de', slug: 'first', dir: 'site/articles', language: 'de', channels: %w[website] },
        { id: 'ART-001-en', slug: 'first', dir: 'site/en/articles', language: 'en', channels: %w[website],
          translation_of: 'ART-001-de' }
      ],
      ui_terms: BILINGUAL_UI_TERMS
    ) do |validator, root, artifacts|
      validator.generate_article_comment_includes(artifacts)
      allowlist = validator.generate_article_comment_allowlist(artifacts, output: 'build/allowed.json')

      assert_includes (root + 'site/articles/generated/first-comments.adoc').read, 'data-article-id="ART-001-de"'
      assert_includes (root + 'site/en/articles/generated/first-comments.adoc').read, 'data-article-id="ART-001-en"'
      assert_equal %w[ART-001-de ART-001-en], JSON.parse(allowlist.read)['article_ids']
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
