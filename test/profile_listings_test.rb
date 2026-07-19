# frozen_string_literal: true

# Behaviour specification bridge for the article listing generator (the recent
# fragment plus the all/tag/skill overview pages).
#
# Minitest is a classic (non-BDD) runner, so each test method name is a
# sanitized translation of a scenario title in features/article-listings.feature,
# with Given/When/Then comment anchors separating Arrange, Act, and Assert. Each
# test builds an isolated temporary profile tree so the real repository is never
# touched.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'yaml'

require_relative '../scripts/validate-profile-metamodel'

class ProfileListingsTest < Minitest::Test
  # Builds an isolated profile tree from lightweight article descriptions and
  # yields a validated validator plus the profile root.
  def with_articles(articles)
    Dir.mktmpdir('profile-list-test') do |dir|
      root = Pathname.new(dir)

      articles.each do |article|
        slug = article.fetch(:slug)
        rel_dir = article.fetch(:dir, 'articles')
        (root + rel_dir).mkpath
        source_rel = "#{rel_dir}/#{slug}.adoc"
        (root + source_rel).write("= #{article.fetch(:title, slug)}\n")
        (root + "#{rel_dir}/#{slug}.profile.yaml").write(metadata_yaml(article, source_rel))
      end

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      artifacts = validator.validate
      yield(validator, artifacts, root)
    end
  end

  def metadata_yaml(article, source_rel)
    metadata = {
      'id' => article.fetch(:id),
      'type' => article.fetch(:type, 'Article'),
      'title' => article.fetch(:title, article.fetch(:slug)),
      'status' => article.fetch(:status, 'published'),
      'owner' => 'Test Owner',
      'created' => article.fetch(:created, '2026-01-01'),
      'source' => source_rel
    }
    %i[published summary summary_de summary_en].each do |key|
      metadata[key.to_s] = article[key] if article.key?(key)
    end
    metadata['tags'] = article[:tags] if article.key?(:tags)
    metadata['skills'] = article[:skills] if article.key?(:skills)
    metadata.to_yaml
  end

  def recent(root, dir: 'articles')
    path = root + "#{dir}/generated/lists/recent.adoc"
    path.exist? ? path.read : ''
  end

  def page(root, name, dir: 'articles')
    path = root + "#{dir}/generated/pages/#{name}.adoc"
    path.exist? ? path.read : ''
  end

  def article_tags(root, slug, dir: 'articles')
    path = root + "#{dir}/generated/#{slug}-tags.adoc"
    path.exist? ? path.read : ''
  end

  def test_article_tag_include_reuses_card_markup_and_links_to_tag_pages
    # Given: an article in a topic directory with two tags
    articles = [
      { id: 'ART-200-tags', slug: 'tagged', dir: 'articles/architecture',
        tags: %w[greenIT docs-as-code] },
      { id: 'ART-201-other-topic', slug: 'other', dir: 'articles/documentation' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: per-article tag includes are generated
      validator.generate_article_tag_includes(artifacts)

      # Then: the horizontal card markup links from the article to each tag page
      tags = article_tags(root, 'tagged', dir: 'articles/architecture')
      assert_includes tags, '<p class="article-card-tags article-tags">'
      assert_includes tags, 'class="article-card-tag" href="../lists/tag-greenIT.html">greenIT</a>'
      assert_includes tags, 'class="article-card-tag" href="../lists/tag-docs-as-code.html">docs-as-code</a>'
    end
  end

  def test_article_without_tags_gets_an_empty_tag_include
    # Given: an article without tags
    articles = [{ id: 'ART-200-no-tags', slug: 'untagged' }]

    with_articles(articles) do |validator, artifacts, root|
      # When: per-article tag includes are generated
      validator.generate_article_tag_includes(artifacts)

      # Then: the optional include exists but contributes no markup
      assert_equal '', article_tags(root, 'untagged')
    end
  end

  def test_recent_listing_shows_the_newest_public_articles_limited_to_ten
    # Given: twelve public articles with distinct publication dates
    articles = (1..12).map do |i|
      { id: format('ART-1%02d-item', i), slug: "item-#{i}", title: "Item #{i}",
        published: format('2026-03-%02d', i) }
    end

    with_articles(articles) do |_validator, artifacts, root|
      # When: the article lists are generated
      _validator.generate_article_lists(artifacts)

      # Then: the ten newest are listed, newest first, and the two oldest are omitted
      listed = recent(root).scan(/href="(item-\d+)\.html"/).flatten
      assert_equal 10, listed.length
      assert_equal 'item-12', listed.first
      assert_equal 'item-3', listed.last
      refute_includes recent(root), 'item-2.html'
      refute_includes recent(root), 'item-1.html'
    end
  end

  def test_a_list_entry_shows_title_link_summary_publication_date_and_tag_links
    # Given: a public article with a title, summary, publication date, and tags
    articles = [
      { id: 'ART-201-full', slug: 'full', title: 'Full Entry', summary_de: 'Eine Zusammenfassung.',
        published: '2026-05-09', tags: %w[greenIT docs-as-code] }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article lists are generated
      validator.generate_article_lists(artifacts)

      # Then: the entry links the title, shows summary + formatted date, and links each tag
      entry = recent(root)
      assert_includes entry, '<a href="full.html">Full Entry</a>'
      assert_includes entry, 'Eine Zusammenfassung.'
      assert_includes entry, '<time datetime="2026-05-09">09.05.2026</time>'
      assert_includes entry, 'href="lists/tag-greenIT.html">greenIT</a>'
      assert_includes entry, 'href="lists/tag-docs-as-code.html">docs-as-code</a>'
    end
  end

  def test_publication_date_falls_back_to_the_creation_date
    # Given: a public article without a published date
    articles = [
      { id: 'ART-301-fallback', slug: 'fallback', title: 'Fallback', created: '2026-02-14' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article lists are generated
      validator.generate_article_lists(artifacts)

      # Then: the listed date is derived from the creation date
      assert_includes recent(root), '<time datetime="2026-02-14">14.02.2026</time>'
    end
  end

  def test_summary_is_language_specific_with_a_fallback
    # Given: one article with a German summary and one with only the neutral summary
    articles = [
      { id: 'ART-401-de', slug: 'de-article', title: 'DE', published: '2026-06-02',
        summary_de: 'Deutsche Zusammenfassung.', summary: 'Neutral summary.' },
      { id: 'ART-402-neutral', slug: 'neutral-article', title: 'Neutral', published: '2026-06-01',
        summary: 'Nur neutral.' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article lists are generated in German (the default)
      validator.generate_article_lists(artifacts, language: 'de')

      # Then: the first shows the German summary and the second falls back to neutral
      entry = recent(root)
      assert_includes entry, 'Deutsche Zusammenfassung.'
      assert_includes entry, 'Nur neutral.'
      refute_includes entry, 'Neutral summary.'
    end
  end

  def test_only_public_articles_appear_in_listings
    # Given: a published article and a draft article
    articles = [
      { id: 'ART-501-public', slug: 'public', title: 'Public', status: 'published', published: '2026-01-02' },
      { id: 'ART-502-draft', slug: 'draft', title: 'Draft', status: 'draft', published: '2026-01-03' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article lists are generated
      validator.generate_article_lists(artifacts)

      # Then: the draft article does not appear in any listing
      refute_includes recent(root), 'draft.html'
      refute_includes page(root, 'all'), 'draft.html'
    end
  end

  def test_listings_are_sorted_by_publication_date_descending_with_an_id_tiebreak
    # Given: three public articles, two sharing the same publication date
    articles = [
      { id: 'ART-601-b', slug: 'b', title: 'B', published: '2026-01-10' },
      { id: 'ART-602-a', slug: 'a', title: 'A', published: '2026-01-10' },
      { id: 'ART-603-newer', slug: 'newer', title: 'Newer', published: '2026-02-01' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article lists are generated
      validator.generate_article_lists(artifacts)

      # Then: newest first, and equal dates are ordered by id (ART-601 before ART-602)
      order = page(root, 'all').scan(/article-card-title"><a href="\.\.\/(\w+)\.html"/).flatten
      assert_equal %w[newer b a], order
    end
  end

  def test_a_tag_overview_page_lists_every_article_carrying_that_tag
    # Given: two public articles sharing a tag and one without it
    articles = [
      { id: 'ART-701-one', slug: 'one', title: 'One', tags: %w[greenIT], published: '2026-01-05' },
      { id: 'ART-702-two', slug: 'two', title: 'Two', tags: %w[greenIT], published: '2026-01-04' },
      { id: 'ART-703-three', slug: 'three', title: 'Three', tags: %w[other], published: '2026-01-03' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article lists are generated
      validator.generate_article_lists(artifacts)

      # Then: the tag page lists the two tagged articles and omits the third
      tag_page = page(root, 'tag-greenIT')
      assert_includes tag_page, 'one.html'
      assert_includes tag_page, 'two.html'
      refute_includes tag_page, 'three.html'
    end
  end

  def test_a_skill_overview_page_lists_articles_and_humanizes_the_skill_heading
    # Given: a public article carrying a hyphenated skill slug
    articles = [
      { id: 'ART-801-skilled', slug: 'skilled', title: 'Skilled', skills: %w[Software-Architektur],
        published: '2026-01-06' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article lists are generated
      validator.generate_article_lists(artifacts)

      # Then: a skill page exists, lists the article, and humanizes the slug heading
      skill_page = page(root, 'skill-Software-Architektur')
      refute_equal '', skill_page
      assert_includes skill_page, 'skilled.html'
      assert_includes skill_page, '= Artikel zum Thema: Software Architektur'
    end
  end

  def test_removed_tags_and_skills_do_not_leave_stale_pages_behind
    # Given: lists generated for a tag and a skill that later disappear
    first = [
      { id: 'ART-901-tagged', slug: 'tagged', title: 'Tagged', tags: %w[legacy], skills: %w[Legacy-Skill],
        published: '2026-01-07' }
    ]

    with_articles(first) do |validator, artifacts, root|
      validator.generate_article_lists(artifacts)
      assert_includes page(root, 'tag-legacy'), 'tagged.html'
      assert_includes page(root, 'skill-Legacy-Skill'), 'tagged.html'

      # When: the same article is regenerated without that tag and skill
      (root + 'articles/tagged.profile.yaml').write(metadata_yaml(
        { id: 'ART-901-tagged', slug: 'tagged', title: 'Tagged', published: '2026-01-07' },
        'articles/tagged.adoc'
      ))
      revalidated = validator.validate
      validator.generate_article_lists(revalidated)

      # Then: the stale tag and skill pages are removed
      refute_path_exists(root + 'articles/generated/pages/tag-legacy.adoc')
      refute_path_exists(root + 'articles/generated/pages/skill-Legacy-Skill.adoc')
    end
  end

  def test_article_listings_are_deterministic
    # Given: a set of public articles with tags and skills
    articles = [
      { id: 'ART-1001-one', slug: 'one', title: 'One', tags: %w[greenIT], skills: %w[Docs-as-Code],
        published: '2026-01-09' },
      { id: 'ART-1002-two', slug: 'two', title: 'Two', tags: %w[greenIT], published: '2026-01-08' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article lists are generated twice
      names = %w[all tag-greenIT skill-Docs-as-Code]
      validator.generate_article_lists(artifacts)
      first = [recent(root)] + names.map { |n| page(root, n) }
      validator.generate_article_lists(artifacts)
      second = [recent(root)] + names.map { |n| page(root, n) }

      # Then: both generations produce identical listing files
      assert_equal first, second
      refute_equal '', first.first
    end
  end
end
