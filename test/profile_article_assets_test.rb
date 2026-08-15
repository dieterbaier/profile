# frozen_string_literal: true

# Behaviour specification for the files an article owns.
#
# An article's own assets live in a directory named after its ID, next to the
# article source. Two things follow from that name, and both are what these
# tests pin down: a target publishes such a directory exactly when it renders
# the article that claims it, and a directory no article claims is a mistake
# rather than a spare file.
#
# Each test builds an isolated temporary profile tree so the real repository is
# never touched.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'yaml'

require_relative '../scripts/validate-profile-metamodel'

class ProfileArticleAssetsTest < Minitest::Test
  # Builds an isolated profile tree and yields a validator plus its root.
  #
  # Articles live below 'site/' here, unlike the publication-status tests: the
  # orphan scan is a question about the rendered site tree, so a tree without
  # one would answer it vacuously.
  def with_artifacts(artifacts_spec, stray_dirs: [])
    Dir.mktmpdir('profile-assets-test') do |dir|
      root = Pathname.new(dir)

      (root + 'includes/i18n').mkpath
      (root + 'includes/i18n/ui-de.adoc').write(
        ":ui_article_list_all: Alle Artikel\n" \
        ":ui_article_list_tag_prefix: Artikel mit dem Tag:\n" \
        ":ui_article_list_skill_prefix: Artikel zum Thema:\n"
      )

      artifacts_spec.each do |spec|
        slug = spec.fetch(:slug)
        rel_dir = spec.fetch(:dir, 'site/articles')
        (root + rel_dir).mkpath
        source_rel = "#{rel_dir}/#{slug}.adoc"
        (root + source_rel).write("= #{spec.fetch(:title, slug)}\n")
        (root + "#{rel_dir}/#{slug}.profile.yaml").write(metadata_yaml(spec, source_rel))

        next unless spec.fetch(:assets, true)

        assets = root + rel_dir + spec.fetch(:id)
        assets.mkpath
        (assets + 'picture.webp').write('binary')
      end

      stray_dirs.each do |stray|
        (root + stray).mkpath
        (root + stray + 'picture.webp').write('binary')
      end

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      yield(validator, validator.scan_artifacts, root)
    end
  end

  def metadata_yaml(spec, source_rel)
    {
      'id' => spec.fetch(:id),
      'type' => spec.fetch(:type, 'Article'),
      'title' => spec.fetch(:title, spec.fetch(:slug)),
      'status' => spec.fetch(:status, 'published'),
      'owner' => 'Test Owner',
      'created' => '2026-01-01',
      'source' => source_rel,
      'metadata_version' => ProfileArtifactValidator.supported_metadata_versions.first
    }.merge(spec.slice(:language, :translation_of).transform_keys(&:to_s)).to_yaml
  end

  def asset_dirs(validator, artifacts, target: 'public')
    validator.article_asset_dirs(artifacts, target: target)
  end

  def test_a_rendered_article_publishes_the_directory_named_after_it
    # Given: a published article with an asset directory named after its ID
    with_artifacts([{ id: 'ART-101-live', slug: 'live', status: 'published' }]) do |validator, artifacts, _root|
      # When: the public asset selection is computed
      result = asset_dirs(validator, artifacts)

      # Then: that directory is published
      assert_equal ['site/articles/ART-101-live'], result
    end
  end

  def test_an_article_a_target_must_not_render_leaves_its_assets_behind
    # Given: a draft article, which the public target must not carry
    with_artifacts([{ id: 'ART-102-draft', slug: 'draft', status: 'draft' }]) do |validator, artifacts, _root|
      # When: the public asset selection is computed
      result = asset_dirs(validator, artifacts)

      # Then: its assets are not published either. Selecting the page and the
      # files it asks for by one rule is the point of naming the directory after
      # the article: an unpublished article cannot leave its pictures reachable.
      assert_empty result
    end
  end

  def test_the_private_target_publishes_assets_of_the_statuses_it_renders
    # Given: one article of each status, in a tree the private target reads
    spec = %w[private preview published draft].map do |status|
      { id: "ART-20#{status.length}-#{status}", slug: status, status: status }
    end

    with_artifacts(spec) do |validator, artifacts, _root|
      # When: the private asset selection is computed
      result = asset_dirs(validator, artifacts, target: 'private')

      # Then: it carries the assets of exactly the statuses it renders
      assert_equal ProfileArtifactValidator::TARGET_STATUSES.fetch('private').length, result.length
      refute(result.any? { |dir| dir.end_with?('draft') })
    end
  end

  def test_a_translation_owns_its_own_directory_and_its_own_status
    # Given: a published article and an unpublished translation of it
    spec = [
      { id: 'ART-301-original', slug: 'original', status: 'published', language: 'de' },
      { id: 'ART-301-original-en', slug: 'original', dir: 'site/en/articles', status: 'draft',
        language: 'en', translation_of: 'ART-301-original' }
    ]

    with_artifacts(spec) do |validator, artifacts, _root|
      # When: the public asset selection is computed
      result = asset_dirs(validator, artifacts)

      # Then: only the original's directory is published. A translation is a
      # separate artifact with a separate status, so it neither inherits the
      # original's assets nor rides on its status to publish its own.
      assert_equal ['site/articles/ART-301-original'], result
    end
  end

  def test_an_article_without_assets_contributes_no_directory
    # Given: a published article that owns no asset directory
    with_artifacts([{ id: 'ART-401-bare', slug: 'bare', status: 'published', assets: false }]) do |validator, artifacts, _root|
      # When: the public asset selection is computed
      result = asset_dirs(validator, artifacts)

      # Then: nothing is named. A path that does not exist would reach the build
      # as a copy source and fail there, far from the article that lacks it.
      assert_empty result
    end
  end

  def test_a_directory_no_article_claims_is_reported
    # Given: an asset directory whose name matches no article's ID
    spec = [{ id: 'ART-501-real', slug: 'real', status: 'published' }]

    with_artifacts(spec, stray_dirs: ['site/articles/ART-999-typo']) do |validator, artifacts, _root|
      # When: the tree is validated
      validator.validate_article_assets(artifacts)

      # Then: it is an error rather than an unused file. No target copies it, so
      # the author would see broken images and no reason for them.
      assert_equal 1, validator.errors.length
      assert_includes validator.errors.first, 'site/articles/ART-999-typo'
    end
  end

  def test_a_directory_of_an_unpublished_article_is_claimed_rather_than_orphaned
    # Given: a draft article with an asset directory
    with_artifacts([{ id: 'ART-601-draft', slug: 'draft', status: 'draft' }]) do |validator, artifacts, _root|
      # When: the tree is validated
      validator.validate_article_assets(artifacts)

      # Then: nothing is reported. The directory is claimed; that no target
      # publishes it yet is the article's status, not a mistake in the tree.
      assert_empty validator.errors
    end
  end
end
