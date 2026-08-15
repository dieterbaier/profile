# frozen_string_literal: true

# Behaviour specification for the rendered-target asset check.
#
# Bridged to: features/rendered-asset-references.feature. Each test method is
# named after the sanitized scenario title, with Given/When/Then comment anchors
# inside it.
#
# The check exists because a missing image is reported to nobody: asciidoctor
# does not resolve a reference, pandoc does not either, and the browser tells a
# reader rather than the build. These tests pin down what counts as a reference
# it may judge, so it neither misses a broken image nor fails a target over a
# link it cannot be responsible for.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'

require_relative '../scripts/verify-rendered-asset-references'

class RenderedAssetReferencesTest < Minitest::Test
  # Builds an isolated rendered target from page bodies and asset paths.
  def with_target(pages, assets: [])
    Dir.mktmpdir('rendered-assets-test') do |dir|
      root = Pathname.new(dir)

      pages.each do |relative, body|
        path = root + relative
        path.dirname.mkpath
        path.write(body)
      end

      assets.each do |relative|
        path = root + relative
        path.dirname.mkpath
        path.write('binary')
      end

      yield(RenderedAssetReferences.unresolved(root))
    end
  end

  def test_a_page_whose_image_is_in_the_target_is_accepted
    # Given: a page next to the image it asks for
    pages = { 'articles/a.html' => '<img src="ART-001-a/picture.webp">' }

    with_target(pages, assets: ['articles/ART-001-a/picture.webp']) do |missing|
      # When: the target is checked
      # Then: nothing is reported
      assert_empty missing
    end
  end

  def test_a_page_whose_image_is_absent_is_reported
    # Given: a page asking for an image the target does not contain
    pages = { 'articles/a.html' => "line\n<img src=\"ART-001-a/picture.webp\">" }

    with_target(pages) do |missing|
      # When: the target is checked
      # Then: it is reported with the page and the line it stands on
      assert_equal 1, missing.length
      assert_equal 'articles/a.html', missing.first.page
      assert_equal 'ART-001-a/picture.webp', missing.first.target
      assert_equal 2, missing.first.line
    end
  end

  def test_a_reference_is_resolved_relative_to_the_page_that_makes_it
    # Given: a page reaching out of its own directory, as the Markdown export does
    pages = { 'articles/documentation/a.md' => '<img src="../media/ART-001-a/picture.svg">' }

    with_target(pages, assets: ['articles/media/ART-001-a/picture.svg']) do |missing|
      # When: the target is checked
      # Then: the reference resolves. A page is fetched from where it sits, so a
      # target-root-relative reading would call a correct reference broken.
      assert_empty missing
    end
  end

  def test_an_external_reference_is_not_hosted_by_the_target
    # Given: pages linking to other hosts, inline data, and an anchor
    pages = { 'a.html' => '<img src="https://example.org/x.png">' \
                          '<img src="//cdn.example.org/y.png">' \
                          '<img src="data:image/png;base64,AAAA">' \
                          '<a href="#top">top</a>' }

    with_target(pages) do |missing|
      # When: the target is checked
      # Then: none of them is reported, because the target does not host them
      assert_empty missing
    end
  end

  def test_a_reference_that_is_not_an_asset_is_left_alone
    # Given: a page linking to another page and a stylesheet
    pages = { 'a.html' => '<a href="other.html">other</a><link href="stylesheet/style.css">' }

    with_target(pages) do |missing|
      # When: the target is checked
      # Then: nothing is reported. This check answers for the files a page
      # fetches as images, and says nothing about navigation being complete.
      assert_empty missing
    end
  end

  def test_a_markdown_image_is_checked_like_an_html_one
    # Given: a Markdown page using the native image syntax
    pages = { 'a.md' => '![Alt](ART-001-a/picture.png)' }

    with_target(pages) do |missing|
      # When: the target is checked
      # Then: it is reported, because the export renders both forms
      assert_equal 1, missing.length
      assert_equal 'ART-001-a/picture.png', missing.first.target
    end
  end

  def test_a_percent_encoded_reference_names_the_file_it_encodes
    # Given: a page asking for a file whose name carries a space
    pages = { 'a.html' => '<img src="ART-001-a/two%20words.png">' }

    with_target(pages, assets: ['ART-001-a/two words.png']) do |missing|
      # When: the target is checked
      # Then: it resolves. A reference is a URL, so the encoded form is the
      # correct one and only the decoded form names a file.
      assert_empty missing
    end
  end

  def test_a_query_or_fragment_is_not_part_of_the_file_name
    # Given: a page cache-busting an image it does contain
    pages = { 'a.html' => '<img src="ART-001-a/picture.png?v=2">' }

    with_target(pages, assets: ['ART-001-a/picture.png']) do |missing|
      # When: the target is checked
      # Then: it resolves rather than being reported as a missing file
      assert_empty missing
    end
  end

  def test_a_reference_that_leaves_the_target_is_missing_even_when_the_file_exists
    # Given: a page climbing out of the target at a file that is really there
    Dir.mktmpdir('rendered-assets-test') do |dir|
      root = Pathname.new(dir)
      (root + 'target/articles').mkpath
      (root + 'outside').mkpath
      (root + 'outside/leak.png').write('binary')
      (root + 'target/articles/a.html').write('<img src="../../outside/leak.png">')

      # When: the target is checked
      missing = RenderedAssetReferences.unresolved(root + 'target')

      # Then: it is reported, and reported as having left the target. The file
      # exists on the machine that built it and nowhere the target is served, so
      # asking only whether it exists would pass here and break on deployment.
      assert_equal 1, missing.length
      assert_equal :outside_target, missing.first.reason
    end
  end

  def test_a_sibling_target_whose_name_extends_this_one_is_not_mistaken_for_it
    # Given: two targets side by side, one named as a prefix of the other, as
    # build/site and build/site-private are
    Dir.mktmpdir('rendered-assets-test') do |dir|
      root = Pathname.new(dir)
      (root + 'site/a').mkpath
      (root + 'site-private').mkpath
      (root + 'site-private/x.png').write('binary')
      (root + 'site/a/p.html').write('<img src="../../site-private/x.png">')

      # When: the shorter-named target is checked
      missing = RenderedAssetReferences.unresolved(root + 'site')

      # Then: the reference counts as outside it. Comparing the paths as plain
      # strings would read 'site-private' as living below 'site'.
      assert_equal 1, missing.length
      assert_equal :outside_target, missing.first.reason
    end
  end

  def test_a_target_that_was_never_rendered_reports_nothing
    # Given: no rendered target at all
    Dir.mktmpdir('rendered-assets-test') do |dir|
      # When: a directory that does not exist is checked
      missing = RenderedAssetReferences.unresolved(Pathname.new(dir) + 'absent')

      # Then: nothing is reported. A target nobody built is not a target with
      # broken images, and failing here would fail every unrelated task.
      assert_empty missing
    end
  end
end
