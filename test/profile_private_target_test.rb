# frozen_string_literal: true

# Behaviour specification bridge for the private content target.
#
# Minitest is a classic (non-BDD) runner, so each test method name is a
# sanitized translation of a scenario title in
# features/private-content-target.feature, with Given/When/Then comment anchors
# separating Arrange, Act, and Assert.
#
# Every test builds temporary trees for the sibling arrangement: a content root
# that owns no includes, an includes tree that does, and an output root that is
# neither. The real private repository is never touched.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'yaml'
require 'open3'

require_relative '../scripts/validate-profile-metamodel'
require_relative '../scripts/inject-site-metadata'

class ProfilePrivateTargetTest < Minitest::Test
  UI_TERMS = ":ui_article_list_all: Alle Artikel\n" \
             ":ui_article_list_tag_prefix: Artikel mit dem Tag:\n" \
             ":ui_article_list_skill_prefix: Artikel zum Thema:\n"

  INJECTOR = File.expand_path('../scripts/inject-site-metadata.rb', __dir__)

  # A content root shaped like the private repository: articles and their
  # sidecars, and deliberately no includes of its own.
  def with_private_content(specs)
    Dir.mktmpdir('profile-private-content') do |content|
      Dir.mktmpdir('profile-private-includes') do |includes|
        root = Pathname.new(content)
        includes_root = Pathname.new(includes)
        (includes_root + 'i18n').mkpath
        (includes_root + 'i18n/ui-de.adoc').write(UI_TERMS)

        (root + 'src-content/profile/site/articles').mkpath
        specs.each do |spec|
          slug = spec.fetch(:slug)
          source_rel = "src-content/profile/site/articles/#{slug}.adoc"
          (root + source_rel).write("= #{slug}\n")
          (root + "src-content/profile/site/articles/#{slug}.profile.yaml").write(metadata_yaml(spec, source_rel))
        end

        validator = ProfileArtifactValidator.new(
          root: root,
          profile_dir: root + 'src-content/profile',
          includes_dir: includes_root
        )
        yield(validator, validator.scan_artifacts, root)
      end
    end
  end

  def metadata_yaml(spec, source_rel)
    {
      'id' => spec.fetch(:id),
      'type' => 'Article',
      'title' => spec.fetch(:slug),
      'status' => spec.fetch(:status),
      'owner' => 'Test Owner',
      'created' => '2026-01-01',
      'source' => source_rel,
      'metadata_version' => ProfileArtifactValidator.supported_metadata_versions.first
    }.to_yaml
  end

  def page(body)
    "<html><head><title>t</title>#{body}</head><body>p</body></html>"
  end

  def write_page(dir, relative, body)
    path = Pathname.new(dir) + relative
    path.dirname.mkpath
    path.write(page(body), encoding: 'UTF-8')
    path
  end

  def test_the_private_target_renders_drafts_alongside_published_articles
    # Given: private, preview, and published articles in the private content root
    specs = ProfileArtifactValidator::TARGET_STATUSES.fetch('private').each_with_index.map do |status, index|
      { id: format('ART-7%02d-%s', index, status), slug: status, status: status }
    end

    with_private_content(specs) do |validator, artifacts, _root|
      # When: the private article selection is computed
      excluded = validator.excluded_article_sources(artifacts, target: 'private')

      # Then: none of their sources is excluded from the private target
      assert_empty excluded
    end
  end

  def test_a_status_that_belongs_to_no_target_is_kept_out_of_the_private_one
    # Given: articles with every status neither target renders
    statuses = ProfileArtifactValidator::STATUSES - ProfileArtifactValidator::TARGET_STATUSES.fetch('private')
    specs = statuses.each_with_index.map do |status, index|
      { id: format('ART-8%02d-%s', index, status), slug: status, status: status }
    end

    with_private_content(specs) do |validator, artifacts, _root|
      # When: the private article selection is computed
      excluded = validator.excluded_article_sources(artifacts, target: 'private')

      # Then: every one of their sources is excluded from the private target
      expected = statuses.map { |status| "src-content/profile/site/articles/#{status}.adoc" }.sort
      assert_equal expected, excluded
    end
  end

  def test_an_article_the_private_target_renders_is_still_absent_from_the_public_one
    # Given: a private article and a preview article
    specs = [
      { id: 'ART-901-private', slug: 'private', status: 'private' },
      { id: 'ART-902-preview', slug: 'preview', status: 'preview' }
    ]

    with_private_content(specs) do |validator, artifacts, _root|
      # When: the public article selection is computed
      excluded = validator.excluded_article_sources(artifacts, target: 'public')

      # Then: both of their sources are excluded from the public target
      assert_equal(
        ['src-content/profile/site/articles/preview.adoc', 'src-content/profile/site/articles/private.adoc'],
        excluded
      )
    end
  end

  def test_interface_terms_come_from_the_tree_that_owns_them
    # Given: a content root without interface terms and a separate tree that has them
    with_private_content([{ id: 'ART-903-draft', slug: 'draft', status: 'private' }]) do |validator, _artifacts, root|
      refute (root + 'src-content/profile/includes').exist?, 'the content root must own no includes'

      # When: the profile metadata is validated against that includes tree
      validator.validate

      # Then: validation passes without the content root holding a copy
      assert_empty validator.errors
    end
  end

  def test_a_content_root_with_no_interface_terms_anywhere_stops_the_build
    # Given: a content root and an includes tree that both lack interface terms
    Dir.mktmpdir('profile-private-content') do |content|
      Dir.mktmpdir('profile-private-includes') do |includes|
        root = Pathname.new(content)
        (root + 'src-content/profile/site/articles').mkpath
        (root + 'src-content/profile/site/articles/draft.adoc').write("= draft\n")
        (root + 'src-content/profile/site/articles/draft.profile.yaml').write(
          metadata_yaml({ id: 'ART-904-draft', slug: 'draft', status: 'private' },
                        'src-content/profile/site/articles/draft.adoc')
        )

        validator = ProfileArtifactValidator.new(
          root: root, profile_dir: root + 'src-content/profile', includes_dir: includes
        )

        # When: the profile metadata is validated
        validator.validate

        # Then: validation fails naming the interface terms it expected
        assert(validator.errors.any? { |error| error.include?('missing interface terms') && error.include?('ui-de.adoc') })
      end
    end
  end

  def test_every_page_of_the_private_target_is_marked_as_not_to_be_indexed
    # Given: a rendered target whose pages carry a canonical link
    Dir.mktmpdir('site-private') do |dir|
      write_page(dir, 'index.html', '<link rel="canonical" href="https://example.org/">')
      write_page(dir, 'articles/ai/draft.html', '<link rel="canonical" href="https://example.org/a">')

      # When: the target is marked as not indexed
      marked = RobotsNoindexInjector.new(site_dir: dir).inject

      # Then: every page carries a robots noindex tag and no canonical link
      assert_equal 2, marked.length
      Pathname.glob(File.join(dir, '**/*.html')).each do |path|
        content = path.read
        assert_includes content, '<meta name="robots" content="noindex, nofollow">'
        refute_includes content, 'canonical'
      end
    end
  end

  def test_marking_a_target_twice_leaves_one_robots_tag
    # Given: a rendered target that was already marked as not indexed
    Dir.mktmpdir('site-private') do |dir|
      path = write_page(dir, 'index.html', '')
      RobotsNoindexInjector.new(site_dir: dir).inject

      # When: the target is marked as not indexed again
      RobotsNoindexInjector.new(site_dir: dir).inject

      # Then: each page carries exactly one robots tag
      assert_equal 1, path.read.scan('name="robots"').length
    end
  end

  def test_a_target_cannot_be_both_unindexed_and_canonical
    # Given: a request to mark a target as not indexed
    Dir.mktmpdir('site-private') do |dir|
      write_page(dir, 'index.html', '')

      # When: a base URL is supplied with it
      _out, err, status = Open3.capture3(
        'ruby', INJECTOR, '--site-dir', dir, '--noindex', '--base-url', 'https://example.org'
      )

      # Then: the request is refused rather than resolved in favour of one of them
      refute_predicate status, :success?
      assert_includes err, 'mutually exclusive'
    end
  end

  def test_output_of_an_article_the_private_target_must_not_contain_is_reported
    # Given: a rendered private target holding the page of a draft article
    with_private_content([{ id: 'ART-905-draft', slug: 'draft', status: 'draft' }]) do |validator, artifacts, root|
      output = root + 'build/site-private/articles/draft.html'
      output.dirname.mkpath
      output.write("rendered\n")

      # When: the rendered target is checked against the private status set
      reported = validator.unexpected_target_outputs(artifacts, target: 'private')

      # Then: that page is reported
      assert_equal ['build/site-private/articles/draft.html'], reported
    end
  end

  def test_the_private_target_is_checked_where_it_is_rendered_not_where_its_content_lives
    # Given: private content in one tree and its rendered target in another
    with_private_content([{ id: 'ART-906-draft', slug: 'draft', status: 'draft' }]) do |validator, artifacts, root|
      Dir.mktmpdir('public-checkout') do |output_root|
        output = Pathname.new(output_root) + 'build/site-private/articles/draft.html'
        output.dirname.mkpath
        output.write("rendered\n")
        refute (root + 'build').exist?, 'the content root holds no rendered target'

        # When: the rendered target is checked
        reported = validator.unexpected_target_outputs(artifacts, target: 'private', output_root: output_root)

        # Then: the reported path is relative to the tree holding the target
        assert_equal ['build/site-private/articles/draft.html'], reported
      end
    end
  end
end
