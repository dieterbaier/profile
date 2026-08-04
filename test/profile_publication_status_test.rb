# frozen_string_literal: true

# Behaviour specification bridge for selecting article sources into a
# publication target.
#
# Minitest is a classic (non-BDD) runner, so each test method name is a
# sanitized translation of a scenario title in
# features/article-publication-status.feature, with Given/When/Then comment
# anchors separating Arrange, Act, and Assert. Each test builds an isolated
# temporary profile tree so the real repository is never touched.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'yaml'

require_relative '../scripts/validate-profile-metamodel'

class ProfilePublicationStatusTest < Minitest::Test
  # Builds an isolated profile tree from lightweight artifact descriptions and
  # yields a validated validator plus the profile root.
  def with_artifacts(artifacts_spec)
    Dir.mktmpdir('profile-status-test') do |dir|
      root = Pathname.new(dir)

      # Listing titles come from the interface terms, so every profile tree that
      # generates listings needs them - the same contract the validator enforces.
      (root + 'includes/i18n').mkpath
      (root + 'includes/i18n/ui-de.adoc').write(
        ":ui_article_list_all: Alle Artikel\n" \
        ":ui_article_list_tag_prefix: Artikel mit dem Tag:\n" \
        ":ui_article_list_skill_prefix: Artikel zum Thema:\n"
      )

      artifacts_spec.each do |spec|
        slug = spec.fetch(:slug)
        rel_dir = spec.fetch(:dir, 'articles')
        (root + rel_dir).mkpath
        source_rel = "#{rel_dir}/#{slug}.adoc"
        (root + source_rel).write("= #{spec.fetch(:title, slug)}\n") unless spec[:omit_source_file]
        (root + "#{rel_dir}/#{slug}.profile.yaml").write(metadata_yaml(spec, source_rel))
      end

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      artifacts = validator.validate
      yield(validator, artifacts, root)
    end
  end

  def metadata_yaml(spec, source_rel)
    metadata = {
      'id' => spec.fetch(:id),
      'type' => spec.fetch(:type, 'Article'),
      'title' => spec.fetch(:title, spec.fetch(:slug)),
      'status' => spec.fetch(:status, 'published'),
      'owner' => 'Test Owner',
      'created' => spec.fetch(:created, '2026-01-01'),
      'metadata_version' => ProfileArtifactValidator.supported_metadata_versions.first
    }
    metadata['source'] = spec.fetch(:source, source_rel) unless spec[:omit_source]
    %i[language translation_of previous next tags].each do |key|
      metadata[key.to_s] = spec[key] if spec.key?(key)
    end
    metadata.to_yaml
  end

  def excluded(validator, artifacts)
    validator.excluded_article_sources(artifacts, target: 'public')
  end

  # The temporary tree has no src-content/profile/site, so the render roots are
  # named here instead of using the repository's own.
  def test_render_roots
    [
      { source_dir: 'articles', output_dir: 'out/site', extension: '.html' },
      { source_dir: 'articles', output_dir: 'out/articles', extension: '.md' }
    ]
  end

  def write_output(root, relative_path)
    path = root + relative_path
    path.dirname.mkpath
    path.write("rendered\n")
    path
  end

  def test_a_published_article_is_rendered_into_the_public_target
    # Given: an article whose status is published
    with_artifacts([{ id: 'ART-101-live', slug: 'live', status: 'published' }]) do |validator, artifacts, _root|
      # When: the public article selection is computed
      result = excluded(validator, artifacts)

      # Then: its source is not excluded from the public target
      assert_empty result
    end
  end

  def test_an_article_of_any_other_status_is_kept_out_of_the_public_target
    # Given: articles with every status the metamodel accepts besides published
    statuses = ProfileArtifactValidator::STATUSES - ProfileArtifactValidator::PUBLIC_STATUSES
    spec = statuses.each_with_index.map do |status, index|
      { id: format('ART-2%02d-%s', index, status), slug: status, status: status }
    end

    with_artifacts(spec) do |validator, artifacts, _root|
      # When: the public article selection is computed
      result = excluded(validator, artifacts)

      # Then: every one of their sources is excluded from the public target
      assert_equal statuses.map { |status| "articles/#{status}.adoc" }.sort, result
    end
  end

  def test_a_language_variant_is_selected_on_its_own_status
    # Given: a published article and an unpublished translation of it
    spec = [
      { id: 'ART-301-original', slug: 'original', status: 'published', language: 'de' },
      { id: 'ART-301-original-en', slug: 'original', dir: 'en/articles', status: 'draft',
        language: 'en', translation_of: 'ART-301-original' }
    ]

    with_artifacts(spec) do |validator, artifacts, _root|
      # When: the public article selection is computed
      result = excluded(validator, artifacts)

      # Then: only the translation's source is excluded from the public target
      assert_equal ['en/articles/original.adoc'], result
    end
  end

  def test_a_page_that_is_not_an_article_is_never_excluded
    # Given: a profile page and a short thought alongside an unpublished article
    spec = [
      { id: 'PP-401-home', slug: 'home', dir: 'pages', type: 'ProfilePage', status: 'draft' },
      { id: 'ST-402-thought', slug: 'thought', dir: 'shorts', type: 'ShortThought', status: 'draft' },
      { id: 'ART-403-hidden', slug: 'hidden', status: 'draft' }
    ]

    with_artifacts(spec) do |validator, artifacts, _root|
      # When: the public article selection is computed
      result = excluded(validator, artifacts)

      # Then: only the article's source is excluded from the public target
      assert_equal ['articles/hidden.adoc'], result
    end
  end

  def test_exclusions_name_the_source_file_rather_than_the_metadata_file
    # Given: an article whose metadata lives in a sidecar next to its source
    with_artifacts([{ id: 'ART-501-sidecar', slug: 'sidecar', status: 'draft' }]) do |validator, artifacts, _root|
      # When: the public article selection is computed
      result = excluded(validator, artifacts)

      # Then: the excluded path is the article source, not the sidecar
      assert_equal ['articles/sidecar.adoc'], result
      refute_includes result.join("\n"), '.profile.yaml'
    end
  end

  def test_a_sidecar_without_a_source_field_still_names_the_article_beside_it
    # Given: an unpublished article whose sidecar declares no source
    spec = [{ id: 'ART-1001-implicit', slug: 'implicit', status: 'draft', omit_source: true }]

    with_artifacts(spec) do |validator, artifacts, _root|
      # When: the public article selection is computed
      result = excluded(validator, artifacts)

      # Then: the article file next to the sidecar is excluded
      assert_equal ['articles/implicit.adoc'], result
    end
  end

  def test_an_unresolvable_source_stops_the_selection_instead_of_skipping_the_article
    # Given: an unpublished article whose sidecar names a source file that is absent
    spec = [{ id: 'ART-1101-gone', slug: 'gone', status: 'draft', source: 'articles/not-here.adoc' }]

    with_artifacts(spec) do |validator, artifacts, _root|
      # When: the public article selection is computed
      error = assert_raises(ProfileArtifactValidator::UnresolvableArticleSource) do
        excluded(validator, artifacts)
      end

      # Then: the selection fails naming the article and its status
      assert_includes error.message, 'gone.profile.yaml'
      assert_includes error.message, 'draft'
      assert_includes error.message, 'public'
    end
  end

  def test_a_published_article_with_an_unresolvable_source_does_not_stop_the_selection
    # Given: a published article whose sidecar names a source file that is absent
    spec = [{ id: 'ART-1201-live', slug: 'live', status: 'published', source: 'articles/not-here.adoc' }]

    with_artifacts(spec) do |validator, artifacts, _root|
      # When: the public article selection is computed
      result = excluded(validator, artifacts)

      # Then: the selection succeeds and excludes nothing
      assert_empty result
    end
  end

  def test_output_of_an_article_the_target_must_not_contain_is_reported
    # Given: a rendered target holding a page and an export of an unpublished article
    spec = [
      { id: 'ART-1301-live', slug: 'live', status: 'published' },
      { id: 'ART-1302-draft', slug: 'draft', status: 'draft' }
    ]

    with_artifacts(spec) do |validator, artifacts, root|
      write_output(root, 'out/site/draft.html')
      write_output(root, 'out/articles/draft.md')
      write_output(root, 'out/site/live.html')

      # When: the rendered target is checked
      result = validator.unexpected_target_outputs(artifacts, target: 'public', render_roots: test_render_roots)

      # Then: both outputs are reported
      assert_equal ['out/articles/draft.md', 'out/site/draft.html'], result
    end
  end

  def test_a_rendered_target_holding_only_published_output_is_accepted
    # Given: a rendered target holding the page of a published article only
    spec = [
      { id: 'ART-1401-live', slug: 'live', status: 'published' },
      { id: 'ART-1402-draft', slug: 'draft', status: 'draft' }
    ]

    with_artifacts(spec) do |validator, artifacts, root|
      write_output(root, 'out/site/live.html')

      # When: the rendered target is checked
      result = validator.unexpected_target_outputs(artifacts, target: 'public', render_roots: test_render_roots)

      # Then: nothing is reported
      assert_empty result
    end
  end

  def test_only_published_articles_appear_in_public_listings_and_navigation
    # Given: a published article and a preview article sharing a tag
    spec = [
      { id: 'ART-601-live', slug: 'live', title: 'Live', status: 'published', tags: %w[shared] },
      { id: 'ART-602-soon', slug: 'soon', title: 'Soon', status: 'preview', tags: %w[shared] }
    ]

    with_artifacts(spec) do |validator, artifacts, root|
      # When: the article listings and navigation are generated
      validator.generate_article_lists(artifacts)
      validator.generate_article_navigation(artifacts)

      listings = Dir.glob((root + 'articles/generated/lists/*.adoc').to_s).map { |path| File.read(path) }.join("\n")
      navigation = (root + 'articles/generated/live-navigation.adoc')

      # Then: the preview article appears in neither
      refute_empty listings
      refute_includes listings, 'soon.html'
      refute_includes listings, 'Soon'
      refute_includes(navigation.exist? ? navigation.read : '', 'soon.html')
    end
  end

  def test_a_published_article_may_not_point_at_an_unpublished_part_of_its_series
    # Given: a published article whose next article is still a draft
    spec = [
      { id: 'ART-701-part-one', slug: 'part-one', status: 'published', next: 'ART-702-part-two' },
      { id: 'ART-702-part-two', slug: 'part-two', status: 'draft', previous: 'ART-701-part-one' }
    ]

    with_artifacts(spec) do |validator, _artifacts, _root|
      # When: the profile metadata is validated
      errors = validator.errors

      # Then: validation fails naming both articles and the draft status
      matching = errors.grep(/part-one\.profile\.yaml/).grep(/ART-702-part-two/)
      refute_empty matching, "expected a series status error, got: #{errors.inspect}"
      assert_includes matching.first, 'draft'
    end
  end

  def test_an_article_sidecar_that_does_not_name_its_source_stops_the_build
    # Given: an article sidecar without a source field
    with_artifacts([{ id: 'ART-801-nameless', slug: 'nameless', omit_source: true }]) do |validator, _artifacts, _root|
      # When: the profile metadata is validated
      errors = validator.errors

      # Then: validation fails naming the sidecar
      matching = errors.grep(/nameless\.profile\.yaml/).grep(/must declare 'source'/)
      refute_empty matching, "expected a missing-source error, got: #{errors.inspect}"
    end
  end

  def test_an_article_sidecar_whose_source_does_not_exist_stops_the_build
    # Given: an article sidecar naming a source file that is absent
    spec = [{ id: 'ART-901-absent', slug: 'absent', omit_source_file: true }]

    with_artifacts(spec) do |validator, _artifacts, _root|
      # When: the profile metadata is validated
      errors = validator.errors

      # Then: validation fails naming the sidecar
      matching = errors.grep(/absent\.profile\.yaml/).grep(/source/)
      refute_empty matching, "expected a missing-source-file error, got: #{errors.inspect}"
    end
  end
end
