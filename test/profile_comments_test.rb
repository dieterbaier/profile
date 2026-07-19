# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'yaml'

require_relative '../scripts/validate-profile-metamodel'

class ProfileCommentsTest < Minitest::Test
  def with_article
    Dir.mktmpdir('profile-comments-test') do |dir|
      root = Pathname.new(dir)
      (root + 'articles').mkpath
      (root + 'articles/example.adoc').write("= Example & Practice\n")
      (root + 'articles/example.profile.yaml').write({
        'id' => 'ART-101-example',
        'type' => 'Article',
        'title' => 'Example & Practice',
        'status' => 'published',
        'owner' => 'Test Owner',
        'created' => '2026-01-01',
        'source' => 'articles/example.adoc'
      }.to_yaml)
      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      artifacts = validator.validate
      yield validator, artifacts, root
    end
  end

  def test_each_article_receives_a_prefilled_comment_link
    # Given: a metadata-backed article
    with_article do |validator, artifacts, root|
      # When: profile artifacts are generated
      validator.generate_article_comment_includes(artifacts)
      generated = (root + 'articles/generated/example-comments.adoc').read

      # Then: its link creates a GitHub issue marked with article id and title
      assert_includes generated, 'https://github.com/dieterbaier/profile-artikelkommentare/issues/new?'
      assert_includes generated, 'template=artikelkommentar.yml'
      assert_includes generated, 'article_id=ART-101-example'
      assert_includes generated, '%5BArtikelkommentar%5D+%5BART-101-example%5D'
      assert_includes generated, 'Example+%26+Practice'
    end
  end

  def test_existing_comments_can_be_requested_explicitly
    # Given: an article comment block on the static website
    with_article do |validator, artifacts, root|
      validator.generate_article_comment_includes(artifacts)
      generated = (root + 'articles/generated/example-comments.adoc').read
      script = Pathname.new(__dir__).join('../src-content/theme/article-comments.js').read

      # When: the reader requests existing comments
      # Then: a local enhancement loads matching issues and renders linked titles
      assert_includes generated, 'Vorhandene Kommentare laden'
      assert_includes generated, '[subs="attributes"]'
      assert_includes generated, '<script src="{basedir}/stylesheet/article-comments.js"></script>'
      assert_includes script, 'addEventListener("click"'
      assert_includes script, 'https://api.github.com/search/issues?q='
      assert_includes script, 'label:\"Artikelkommentar\"'
      assert_includes script, 'url.searchParams.set("article_url", window.location.href)'
      refute_includes script, 'DOMContentLoaded'
    end
  end

  def test_non_website_article_exports_omit_the_comment_block
    # Given: a generated article comment include
    with_article do |validator, artifacts, root|
      validator.generate_article_comment_includes(artifacts)
      generated = (root + 'articles/generated/example-comments.adoc').read

      # When: it is rendered without the buildsite attribute
      # Then: AsciiDoc guards the complete interaction as website-only
      assert_match(/ifdef::buildsite\[\].*endif::\[\]/m, generated)
    end
  end

  def test_article_comment_styles_do_not_change_page_container_styles
    # Given: the shared website stylesheet
    stylesheet = Pathname.new(__dir__).join('../src-content/theme/style.css').read

    # Then: page containers retain their shared layout rule, while comment
    # presentation is defined by an independent selector.
    assert_match(/#header,\s*#content,\s*#footnotes,\s*footer\s*\{[^}]*max-width: var\(--page-width\);/m, stylesheet)
    assert_match(%r!/\* Optional, reader-triggered GitHub discussion for articles\. \*/\s*\.article-comments\s*\{([^}]*)\}!m, stylesheet)
    refute_match(%r!\.article-comments\s*\{[^}]*border(?:-radius)?:!m, stylesheet)
    refute_match(/#footnotes,\s*\/\* Optional, reader-triggered GitHub discussion for articles\. \*\/\s*\.article-comments/m, stylesheet)
  end

  def test_article_template_includes_every_generated_article_fragment
    # Given: the article template and all per-article fragment suffixes emitted
    # by the profile generator
    template = Pathname.new(__dir__).join('../templates/write-article/article.adoc').read
    generator = Pathname.new(__dir__).join('../scripts/validate-profile-metamodel.rb').read
    generated_suffixes = generator.scan(/#\{article_slug\(article\)\}-(navigation|tags|comments)\.adoc/).flatten.uniq

    # Then: new articles include every generated fragment family
    assert_equal %w[comments navigation tags], generated_suffixes.sort
    generated_suffixes.each do |suffix|
      assert_includes template, "include::{docfile}/../generated/{docname}-#{suffix}.adoc[opts=optional]"
    end
  end
end
