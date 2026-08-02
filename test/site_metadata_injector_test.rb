# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'pathname'

require_relative '../scripts/inject-site-metadata'

class SiteMetadataInjectorTest < Minitest::Test
  SCRIPT = Pathname.new(__dir__).join('../scripts/inject-site-metadata.rb').expand_path

  def with_site(files)
    Dir.mktmpdir('site-metadata-test') do |dir|
      root = Pathname.new(dir)
      files.each do |relative|
        path = root.join(relative)
        path.dirname.mkpath
        path.write("<!DOCTYPE html>\n<html><head><title>Test</title></head><body></body></html>\n")
      end
      yield root
    end
  end

  def canonical_href(path)
    path.read[%r{<link rel="canonical" href="([^"]+)">}, 1]
  end

  def test_public_pages_receive_canonical_urls_derived_from_their_output_paths
    # Given: a generated public site and a configured HTTPS base URL
    with_site(%w[index.html articles/architecture/example.html]) do |site|
      injector = SiteMetadataInjector.new(site_dir: site, base_url: 'https://example.test')

      # When: public site metadata is injected
      injector.inject

      # Then: each HTML page links to its canonical URL below that base URL
      assert_equal 'https://example.test/', canonical_href(site.join('index.html'))
      assert_equal 'https://example.test/articles/architecture/example.html',
                   canonical_href(site.join('articles/architecture/example.html'))
    end
  end

  def test_index_pages_use_directory_canonical_urls
    # Given: generated index pages at the site root and in a subdirectory
    with_site(%w[index.html articles/index.html]) do |site|
      injector = SiteMetadataInjector.new(site_dir: site, base_url: 'https://example.test/root/')

      # When: public site metadata is injected
      injector.inject

      # Then: their canonical URLs omit index.html
      assert_equal 'https://example.test/root/', canonical_href(site.join('index.html'))
      assert_equal 'https://example.test/root/articles/', canonical_href(site.join('articles/index.html'))
    end
  end

  # The default language stays at the site root while every other language lives
  # in its own subtree, so a language variant must keep its prefix in the
  # canonical URL instead of collapsing onto the German page.
  def test_language_subtree_pages_keep_their_language_prefix_in_the_canonical_url
    with_site(%w[index.html en/index.html en/articles/example.html]) do |site|
      injector = SiteMetadataInjector.new(site_dir: site, base_url: 'https://example.test')

      injector.inject

      assert_equal 'https://example.test/', canonical_href(site.join('index.html'))
      assert_equal 'https://example.test/en/', canonical_href(site.join('en/index.html'))
      assert_equal 'https://example.test/en/articles/example.html',
                   canonical_href(site.join('en/articles/example.html'))
    end
  end

  # Scenarios from features/language-alternates.feature that belong to the
  # injector. The rendered site carries no metadata, so the translation groups
  # are handed in as output paths.
  ALTERNATES = {
    'schema_version' => 1,
    'default_language' => 'de',
    'groups' => [{ 'de' => 'index.html', 'en' => 'en/index.html' }]
  }.freeze

  def alternate_hrefs(path)
    path.read.scan(/<link rel="alternate" hreflang="([^"]+)" href="([^"]+)">/)
  end

  def test_translation_group_is_published_as_alternate_links
    # Given: a rendered site whose page exists in two languages
    with_site(%w[index.html en/index.html]) do |site|
      injector = SiteMetadataInjector.new(site_dir: site, base_url: 'https://example.test',
                                          alternates: ALTERNATES)

      # When: the site metadata is injected
      injector.inject

      # Then: each variant links to both variants and names the default language as x-default
      expected = [%w[de https://example.test/], %w[en https://example.test/en/],
                  ['x-default', 'https://example.test/']]
      assert_equal expected, alternate_hrefs(site.join('index.html'))
      assert_equal expected, alternate_hrefs(site.join('en/index.html'))
    end
  end

  def test_page_without_variants_carries_no_alternate_links
    # Given: a rendered site whose page exists in one language only
    with_site(%w[index.html legal.html en/index.html]) do |site|
      injector = SiteMetadataInjector.new(site_dir: site, base_url: 'https://example.test',
                                          alternates: ALTERNATES)

      # When: the site metadata is injected
      injector.inject

      # Then: that page carries no alternate links
      assert_empty alternate_hrefs(site.join('legal.html'))
    end
  end

  def test_alternate_links_leave_canonical_links_untouched
    # Given: a rendered site whose page exists in two languages
    with_site(%w[index.html en/index.html]) do |site|
      injector = SiteMetadataInjector.new(site_dir: site, base_url: 'https://example.test',
                                          alternates: ALTERNATES)

      # When: the site metadata is injected, twice, as the listing build does
      injector.inject
      injector.inject

      # Then: each variant keeps the canonical URL of its own output path,
      # and the alternates are replaced rather than appended
      assert_equal 'https://example.test/', canonical_href(site.join('index.html'))
      assert_equal 'https://example.test/en/', canonical_href(site.join('en/index.html'))
      assert_equal 3, alternate_hrefs(site.join('index.html')).length
    end
  end

  def test_special_characters_in_output_paths_are_percent_encoded
    # Given: a generated public page whose output path contains spaces and non-ASCII characters
    with_site(['articles/Über uns & mehr.html']) do |site|
      injector = SiteMetadataInjector.new(site_dir: site, base_url: 'https://example.test')

      # When: public site metadata is injected
      injector.inject

      # Then: each path segment is percent-encoded in the canonical URL
      assert_equal 'https://example.test/articles/%C3%9Cber%20uns%20%26%20mehr.html',
                   canonical_href(site.join('articles/Über uns & mehr.html'))
    end
  end

  def test_local_builds_may_omit_canonical_urls_without_a_base_url
    # Given: a local site build without a configured base URL
    with_site(%w[index.html]) do |site|
      # When: public site metadata injection is invoked
      _stdout, stderr, status = Open3.capture3('ruby', SCRIPT.to_s, '--site-dir', site.to_s)

      # Then: the build succeeds without adding canonical links
      assert status.success?
      assert_includes stderr, 'canonical links are omitted'
      assert_nil canonical_href(site.join('index.html'))
    end
  end

  def test_production_builds_require_a_configured_base_url
    # Given: a production site build without a configured base URL
    with_site(%w[index.html]) do |site|
      # When: public site metadata injection is invoked
      _stdout, stderr, status = Open3.capture3('ruby', SCRIPT.to_s, '--site-dir', site.to_s, '--required')

      # Then: the build fails before deployment
      refute status.success?
      assert_includes stderr, 'SITE_BASE_URL is required'
      assert_nil canonical_href(site.join('index.html'))
    end
  end

  def test_base_url_must_be_https
    with_site(%w[index.html]) do |site|
      error = assert_raises(ArgumentError) do
        SiteMetadataInjector.new(site_dir: site, base_url: 'http://example.test')
      end
      assert_includes error.message, 'absolute HTTPS URL'
    end
  end

  def test_existing_canonical_link_is_replaced_instead_of_duplicated
    with_site(%w[index.html]) do |site|
      page = site.join('index.html')
      page.write(page.read.sub('</head>', '<link href="https://old.test/" rel="canonical"></head>'))

      SiteMetadataInjector.new(site_dir: site, base_url: 'https://example.test').inject

      assert_equal 1, page.read.scan('rel="canonical"').length
      assert_equal 'https://example.test/', canonical_href(page)
    end
  end
end
