# frozen_string_literal: true

# Behaviour specification bridge for the article navigation generator.
#
# Minitest is a classic (non-BDD) runner, so each test method name is a
# sanitized translation of a scenario title in features/article-navigation.feature,
# with Given/When/Then comment anchors separating Arrange, Act, and Assert. Each
# test builds an isolated temporary profile tree so the real repository is never
# touched.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'yaml'

require_relative '../scripts/validate-profile-metamodel'

class ProfileNavigationTest < Minitest::Test
  # Builds an isolated profile tree from lightweight article descriptions and
  # yields a validated validator plus the generated-navigation lookup.
  def with_articles(articles)
    Dir.mktmpdir('profile-nav-test') do |dir|
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
    metadata['tags'] = article[:tags] if article.key?(:tags)
    metadata['previous'] = article[:previous] if article.key?(:previous)
    metadata['next'] = article[:next] if article.key?(:next)
    metadata['relations'] = article[:relations] if article.key?(:relations)
    metadata.to_yaml
  end

  def nav_for(root, slug, dir: 'articles')
    path = root + "#{dir}/generated/#{slug}-navigation.adoc"
    path.exist? ? path.read : ''
  end

  def test_article_without_matches_produces_an_empty_navigation_file
    # Given: an article with a unique meaningful tag and no relations or series links
    articles = [
      { id: 'ART-101-solo', slug: 'solo', tags: %w[unique-topic] },
      { id: 'ART-102-other', slug: 'other', tags: %w[different-topic] }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article navigation is generated
      validator.generate_article_navigation(artifacts)

      # Then: its navigation include file is empty
      assert_equal '', nav_for(root, 'solo')
    end
  end

  def test_previous_and_next_series_links_are_rendered_from_ids
    # Given: two articles linked as a series through previous and next ids
    articles = [
      { id: 'ART-201-part-one', slug: 'part-one', title: 'Part One', next: 'ART-202-part-two' },
      { id: 'ART-202-part-two', slug: 'part-two', title: 'Part Two', previous: 'ART-201-part-one' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article navigation is generated
      validator.generate_article_navigation(artifacts)

      # Then: the first links to the next and the second links to the previous
      part_one = nav_for(root, 'part-one')
      part_two = nav_for(root, 'part-two')
      assert_includes part_one, 'article-nav-next'
      assert_includes part_one, 'href="part-two.html"'
      assert_includes part_one, 'Part Two'
      assert_includes part_two, 'article-nav-prev'
      assert_includes part_two, 'href="part-one.html"'
      assert_includes part_two, 'Part One'
    end
  end

  def test_related_articles_are_collected_from_shared_meaningful_tags
    # Given: two articles that share a meaningful tag
    articles = [
      { id: 'ART-301-alpha', slug: 'alpha', title: 'Alpha', tags: %w[docs-as-code] },
      { id: 'ART-302-beta', slug: 'beta', title: 'Beta', tags: %w[docs-as-code] }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article navigation is generated
      validator.generate_article_navigation(artifacts)

      # Then: each article lists the other under the related heading
      alpha = nav_for(root, 'alpha')
      beta = nav_for(root, 'beta')
      assert_includes alpha, 'Könnte Sie auch interessieren'
      assert_includes alpha, 'href="beta.html"'
      assert_includes beta, 'href="alpha.html"'
    end
  end

  def test_ubiquitous_tags_are_ignored_and_reported
    # Given: an article whose only tag is the ubiquitous tag profile
    articles = [
      { id: 'ART-401-generic', slug: 'generic', tags: %w[profile] },
      { id: 'ART-402-also-generic', slug: 'also-generic', tags: %w[profile] }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: navigation is generated (validation already ran in with_articles)
      validator.generate_article_navigation(artifacts)

      # Then: the validator warns and no tag-based relatedness is produced
      assert(validator.warnings.any? { |w| w.include?('ubiquitous tag') && w.include?('profile') })
      assert_equal '', nav_for(root, 'generic')
    end
  end

  def test_related_articles_are_limited_to_the_five_newest_by_relevance
    # Given: a hub article that shares a tag with six other public articles
    others = (1..6).map do |i|
      { id: format('ART-5%02d-other', i), slug: "other-#{i}", title: "Other #{i}",
        tags: %w[shared], created: format('2026-01-%02d', i) }
    end
    hub = { id: 'ART-500-hub', slug: 'hub', title: 'Hub', tags: %w[shared], created: '2026-01-01' }

    with_articles([hub] + others) do |validator, artifacts, root|
      # When: the article navigation is generated
      validator.generate_article_navigation(artifacts)

      # Then: exactly the five newest are listed, newest first, oldest omitted
      hub_nav = nav_for(root, 'hub')
      listed = hub_nav.scan(/href="(other-\d+)\.html"/).flatten
      assert_equal %w[other-6 other-5 other-4 other-3 other-2], listed
      refute_includes hub_nav, 'other-1.html'
    end
  end

  def test_explicit_relations_rank_above_tag_only_matches
    # Given: an article linked by a relation plus newer tag-only matches
    articles = [
      { id: 'ART-601-source', slug: 'source', title: 'Source', tags: %w[topic], created: '2026-01-01',
        relations: [{ 'type' => 'relates_to', 'target' => 'ART-602-linked', 'status' => 'proposed' }] },
      { id: 'ART-602-linked', slug: 'linked', title: 'Linked', tags: %w[unrelated], created: '2025-01-01' },
      { id: 'ART-603-tagged', slug: 'tagged', title: 'Tagged', tags: %w[topic], created: '2026-12-01' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article navigation is generated
      validator.generate_article_navigation(artifacts)

      # Then: the relation-linked article precedes the newer tag-only match
      source_nav = nav_for(root, 'source')
      linked_pos = source_nav.index('linked.html')
      tagged_pos = source_nav.index('tagged.html')
      refute_nil linked_pos
      refute_nil tagged_pos
      assert linked_pos < tagged_pos, 'relation-linked article should rank before tag-only match'
    end
  end

  def test_empty_sections_are_omitted_from_the_navigation
    # Given: an article with only a previous link, no related articles or next link
    articles = [
      { id: 'ART-751-first', slug: 'first', title: 'First', tags: %w[unique-a] },
      { id: 'ART-752-second', slug: 'second', title: 'Second', tags: %w[unique-b], previous: 'ART-751-first' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article navigation is generated
      validator.generate_article_navigation(artifacts)

      # Then: only the previous section is rendered, with the (Serie) label
      second = nav_for(root, 'second')
      assert_includes second, 'article-nav-prev'
      assert_includes second, '(Serie) Vorheriger Artikel'
      refute_includes second, 'article-nav-related'
      refute_includes second, 'article-nav-next'
    end
  end

  def test_related_articles_exclude_the_previous_and_next_articles
    # Given: an article whose next article also shares a meaningful tag with it
    articles = [
      { id: 'ART-701-lead', slug: 'lead', title: 'Lead', tags: %w[series-topic], next: 'ART-702-follow' },
      { id: 'ART-702-follow', slug: 'follow', title: 'Follow', tags: %w[series-topic], previous: 'ART-701-lead' },
      { id: 'ART-703-extra', slug: 'extra', title: 'Extra', tags: %w[series-topic] }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article navigation is generated
      validator.generate_article_navigation(artifacts)

      # Then: the next article is not repeated in the related list
      lead_nav = nav_for(root, 'lead')
      related_block = lead_nav[/article-nav-related.*?<\/ul>/m] || ''
      assert_includes lead_nav, 'article-nav-next'
      refute_includes related_block, 'follow.html'
      assert_includes related_block, 'extra.html'
    end
  end

  def test_draft_and_private_articles_are_excluded_from_related_suggestions
    # Given: a published article that shares a tag with a draft article
    articles = [
      { id: 'ART-801-public', slug: 'public', title: 'Public', tags: %w[shared], status: 'published' },
      { id: 'ART-802-draft', slug: 'draft', title: 'Draft', tags: %w[shared], status: 'draft' }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article navigation is generated
      validator.generate_article_navigation(artifacts)

      # Then: the draft article is not suggested as related
      refute_includes nav_for(root, 'public'), 'draft.html'
    end
  end

  def test_articles_with_the_same_basename_in_different_directories_do_not_collide
    # Given: two articles that share a basename in different directories
    articles = [
      { id: 'ART-771-arch-intro', slug: 'introduction', title: 'Architecture Intro',
        dir: 'articles/architecture', tags: %w[shared-topic] },
      { id: 'ART-772-docs-intro', slug: 'introduction', title: 'Documentation Intro',
        dir: 'articles/documentation', tags: %w[shared-topic] }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the article navigation is generated
      validator.generate_article_navigation(artifacts)

      # Then: each article keeps its own navigation file that links to the other
      arch = nav_for(root, 'introduction', dir: 'articles/architecture')
      docs = nav_for(root, 'introduction', dir: 'articles/documentation')
      refute_equal '', arch
      refute_equal '', docs
      assert_includes arch, 'href="../documentation/introduction.html"'
      assert_includes docs, 'href="../architecture/introduction.html"'
    end
  end

  def test_previous_and_next_are_rejected_on_non_article_artifacts
    # Given: a non-article artifact that sets a next series link
    articles = [
      { id: 'PRJ-001-tool', slug: 'tool', type: 'Project', next: 'ART-981-real' },
      { id: 'ART-981-real', slug: 'real', type: 'Article' }
    ]

    with_articles(articles) do |validator, _artifacts, _root|
      # When/Then: validation reports that previous/next are article-only
      assert(validator.errors.any? { |e| e.include?('only allowed for Articles') })
    end
  end

  def test_unknown_previous_or_next_id_is_a_validation_error
    # Given: an article whose next id references a missing artifact
    articles = [
      { id: 'ART-901-dangling', slug: 'dangling', next: 'ART-999-missing' }
    ]

    with_articles(articles) do |validator, _artifacts, _root|
      # When/Then: validation (run in with_articles) reports the unknown reference
      assert(validator.errors.any? { |e| e.include?("field 'next'") && e.include?('ART-999-missing') })
    end
  end

  def test_previous_or_next_must_reference_an_article
    # Given: an article whose next id references a non-article artifact
    articles = [
      { id: 'ART-911-linker', slug: 'linker', next: 'PAGE-001-home' },
      { id: 'PAGE-001-home', slug: 'home', type: 'ProfilePage' }
    ]

    with_articles(articles) do |validator, _artifacts, _root|
      # When/Then: validation reports that the series reference must be an article
      assert(validator.errors.any? { |e| e.include?("field 'next'") && e.include?('must reference an Article') })
    end
  end

  def test_inconsistent_series_links_produce_a_warning
    # Given: an article declaring a next article that does not point back to it
    articles = [
      { id: 'ART-921-front', slug: 'front', next: 'ART-922-back' },
      { id: 'ART-922-back', slug: 'back' }
    ]

    with_articles(articles) do |validator, _artifacts, _root|
      # When/Then: validation warns about the inconsistent series link
      assert(validator.warnings.any? { |w| w.include?('declares next') && w.include?('does not declare previous') })
    end
  end

  def test_navigation_output_is_deterministic
    # Given: a set of articles with tags and series links
    articles = [
      { id: 'ART-931-one', slug: 'one', title: 'One', tags: %w[docs-as-code], next: 'ART-932-two' },
      { id: 'ART-932-two', slug: 'two', title: 'Two', tags: %w[docs-as-code], previous: 'ART-931-one' },
      { id: 'ART-933-three', slug: 'three', title: 'Three', tags: %w[docs-as-code] }
    ]

    with_articles(articles) do |validator, artifacts, root|
      # When: the navigation is generated twice
      validator.generate_article_navigation(artifacts)
      first = %w[one two three].map { |slug| nav_for(root, slug) }
      validator.generate_article_navigation(artifacts)
      second = %w[one two three].map { |slug| nav_for(root, slug) }

      # Then: both generations produce identical navigation files
      assert_equal first, second
      refute_equal '', first[0]
    end
  end
end
