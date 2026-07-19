#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cgi'
require 'date'
require 'fileutils'
require 'optparse'
require 'pathname'
require 'set'
require 'yaml'

class ProfileArtifactValidator
  REQUIRED = %w[id type title status owner created].freeze
  PROPERTIES = %w[id type title status owner created updated published reviewed generated language audience channels summary summary_de summary_en source tags skills previous next relations metadata_version].freeze
  TYPES = %w[ProfilePage Article ShortThought CV Project ProfessionalExperience Education Skill Contact ProfileFragment].freeze
  STATUSES = %w[draft proposed preview reviewed published private archived deprecated].freeze
  # Statuses whose articles may appear as public "related article" suggestions.
  PUBLIC_STATUSES = %w[published preview reviewed].freeze
  # Ubiquitous tags carry no discriminating meaning across articles. They are
  # ignored when computing related-article tag overlap, and the validator warns
  # when an article relies on them. Keep meaningful topical tags (for example
  # docs-as-code) out of this list even when most articles currently share them.
  UBIQUITOUS_TAGS = %w[profile].freeze
  # Maximum number of "Könnte Sie auch interessieren" entries per article.
  RELATED_LIMIT = 5
  # Number of most recent articles shown on the article landing page.
  RECENT_LIMIT = 10
  # Default display language for article listings when none is requested.
  DEFAULT_LANGUAGE = 'de'
  ARTICLE_COMMENTS_REPOSITORY = 'dieterbaier/profile-artikelkommentare'
  ARTICLE_COMMENTS_TEMPLATE = 'artikelkommentar.yml'
  LANGUAGES = %w[de en mixed].freeze
  CHANNELS = %w[website cv readme github gitlab markdown-export pdf].freeze
  RELATION_TYPES = %w[addresses depends_on constrains refines supersedes conflicts_with mitigates introduces_risk affects verifies documents relates_to].freeze
  RELATION_STATUSES = %w[proposed reviewed accepted rejected].freeze
  RELATION_KEYS = %w[type target status rationale evidence reviewed].freeze
  ARTIFACT_ID_PATTERN = /\A[A-Z]+-[0-9]{3,}(-[a-z0-9]+)*\z/
  TAG_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9-]*\z/

  Artifact = Struct.new(:path, :metadata, keyword_init: true)
  attr_reader :errors, :warnings, :root, :profile_dir

  def initialize(root:, profile_dir:)
    @root = Pathname.new(root).expand_path
    @profile_dir = Pathname.new(profile_dir).expand_path
    @errors = []
    @warnings = []
  end

  def validate
    artifacts = scan
    validate_fields(artifacts)
    validate_ids(artifacts)
    validate_relations(artifacts)
    validate_series(artifacts)
    artifacts
  end

  def generate(artifacts, output:)
    output_path = @root.join(output)
    FileUtils.mkdir_p(output_path.dirname)
    output_path.write(render_index(artifacts, output_path))
    output_path
  end

  # Writes one navigation include per article into a `generated/` directory next
  # to the article (for example .../architecture/generated/<slug>-navigation.adoc).
  # Placing the file beside its article keeps the filename unique per directory,
  # so articles that share a basename in different directories never collide, and
  # the fixed `include::generated/{docname}-navigation.adoc` resolves per article.
  # Each file holds previous/next series links and up to RELATED_LIMIT related
  # articles, or stays empty when nothing applies. Returns the written paths.
  def generate_article_navigation(artifacts)
    articles = artifacts.select { |artifact| artifact.metadata['type'] == 'Article' }
    by_id = articles.each_with_object({}) { |article, index| index[article.metadata['id']] = article }

    clean_generated_navigation

    articles.map do |article|
      nav_dir = article_source_path(article).dirname.join('generated')
      FileUtils.mkdir_p(nav_dir)
      nav_path = nav_dir.join("#{article_slug(article)}-navigation.adoc")
      nav_path.write(render_navigation(article, articles, by_id), encoding: 'UTF-8')
      nav_path
    end
  end

  # Writes one tag-list include per article into the same adjacent `generated/`
  # directory used by article navigation. Links are relative to the article.
  def generate_article_tag_includes(artifacts)
    articles = artifacts.select { |artifact| artifact.metadata['type'] == 'Article' }
    articles_dir = articles_base_dir(articles)
    return [] if articles_dir.nil?

    clean_generated_tag_includes

    articles.map do |article|
      tags_dir = article_source_path(article).dirname.join('generated')
      FileUtils.mkdir_p(tags_dir)
      tags_path = tags_dir.join("#{article_slug(article)}-tags.adoc")
      tags_path.write(render_article_tags(article, articles_dir), encoding: 'UTF-8')
      tags_path
    end
  end

  # Writes the progressive-enhancement block used to create and display GitHub
  # issues for an article. The optional issue list is loaded by a local script
  # only after the reader explicitly requests it.
  def generate_article_comment_includes(artifacts)
    articles = artifacts.select { |artifact| artifact.metadata['type'] == 'Article' }

    clean_generated_comment_includes

    articles.map do |article|
      comments_dir = article_source_path(article).dirname.join('generated')
      FileUtils.mkdir_p(comments_dir)
      comments_path = comments_dir.join("#{article_slug(article)}-comments.adoc")
      comments_path.write(render_article_comments(article), encoding: 'UTF-8')
      comments_path
    end
  end

  # Generates the article listings from metadata: a "recent" include fragment
  # (RECENT_LIMIT newest public articles) plus standalone overview pages for all
  # articles, each tag, and each skill. Fragments live under
  # <articles-dir>/generated/lists and standalone pages under
  # <articles-dir>/generated/pages. Standalone pages are authored for the output
  # location <articles-dir>/lists, so their links resolve once the dedicated
  # Asciidoctor task renders that directory into the site. Returns written paths.
  def generate_article_lists(artifacts, language: DEFAULT_LANGUAGE)
    all_articles = artifacts.select { |artifact| artifact.metadata['type'] == 'Article' }
    articles_dir = articles_base_dir(all_articles)
    return [] if articles_dir.nil?

    clean_generated_lists(articles_dir)

    lists_dir = articles_dir.join('generated', 'lists')
    pages_dir = articles_dir.join('generated', 'pages')
    FileUtils.mkdir_p(lists_dir)
    FileUtils.mkdir_p(pages_dir)

    # The output location of the standalone pages; used to compute link targets.
    output_dir = articles_dir.join('lists')
    ordered = sort_articles(public_articles(artifacts))
    written = []

    recent_path = lists_dir.join('recent.adoc')
    recent_path.write(render_list_fragment(ordered.first(RECENT_LIMIT), from_dir: articles_dir, language: language), encoding: 'UTF-8')
    written << recent_path

    all_path = pages_dir.join('all.adoc')
    all_path.write(render_list_page(title: 'Alle Artikel', articles: ordered, output_dir: output_dir, articles_dir: articles_dir, language: language), encoding: 'UTF-8')
    written << all_path

    tags_in_use(ordered).each do |tag|
      tagged = ordered.select { |article| Array(article.metadata['tags']).include?(tag) }
      path = pages_dir.join("tag-#{tag}.adoc")
      path.write(render_list_page(title: "Artikel mit dem Tag: #{tag}", articles: tagged, output_dir: output_dir, articles_dir: articles_dir, language: language), encoding: 'UTF-8')
      written << path
    end

    skills_in_use(ordered).each do |skill|
      skilled = ordered.select { |article| Array(article.metadata['skills']).include?(skill) }
      path = pages_dir.join("skill-#{skill}.adoc")
      path.write(render_list_page(title: "Artikel zum Thema: #{humanize_slug(skill)}", articles: skilled, output_dir: output_dir, articles_dir: articles_dir, language: language), encoding: 'UTF-8')
      written << path
    end

    written
  end

  # Removes previously generated article listings so removed tags, skills, or
  # articles do not leave stale pages or fragments behind.
  def clean_generated_lists(articles_dir)
    FileUtils.rm_rf(articles_dir.join('generated', 'lists'))
    FileUtils.rm_rf(articles_dir.join('generated', 'pages'))
  end

  # Removes previously generated navigation files, including files left behind by
  # the earlier flat `generated/articles/` layout, so deletions and renames do not
  # leave stale navigation around.
  def clean_generated_navigation
    FileUtils.rm_rf(profile_dir.join('generated', 'articles'))
    Dir.glob(profile_dir.join('**', 'generated', '*-navigation.adoc').to_s).each do |path|
      File.delete(path)
    end
  end

  def clean_generated_tag_includes
    Dir.glob(profile_dir.join('**', 'generated', '*-tags.adoc').to_s).each do |path|
      File.delete(path)
    end
  end

  def clean_generated_comment_includes
    Dir.glob(profile_dir.join('**', 'generated', '*-comments.adoc').to_s).each do |path|
      File.delete(path)
    end
  end

  def report(artifacts)
    puts 'Profile metamodel validation report'
    puts "Profile target: #{relative(profile_dir)}"
    puts "Artifacts scanned: #{artifacts.length}"
    puts "Errors: #{errors.length}"
    puts "Warnings: #{warnings.length}"
    unless errors.empty?
      puts "\nErrors:"
      errors.each { |error| puts "  - #{error}" }
    end
    unless warnings.empty?
      puts "\nWarnings:"
      warnings.each { |warning| puts "  - #{warning}" }
    end
    puts
    puts(errors.empty? ? 'Validation passed.' : 'Validation failed.')
  end

  private

  def scan
    paths = Dir.glob(profile_dir.join('**/*.{adoc,yaml,yml}').to_s).reject { |path| path.include?('/generated/') }.sort
      paths.map do |path|
        path = Pathname.new(path)
        metadata = if path.extname == '.adoc'
                     front_matter(path)
                   elsif path.basename.to_s.end_with?('.profile.yaml', '.profile.yml')
                     YAML.safe_load(path.read, permitted_classes: [Date], aliases: false)
                   end
        Artifact.new(path: path, metadata: stringify(metadata)) if metadata
      rescue Psych::SyntaxError => e
        errors << "#{relative(path)} has invalid YAML: #{e.message.lines.first.strip}"
        nil
      end.compact
  end

  def front_matter(path)
    text = path.read
    return nil unless text.start_with?("---\n")
    parts = text.split(/^---\s*$/, 3)
    return nil if parts.length < 3
    YAML.safe_load(parts[1], permitted_classes: [Date], aliases: false)
  end

  def stringify(value)
    return nil unless value.is_a?(Hash)
    value.transform_keys(&:to_s)
  end

  def validate_fields(artifacts)
    artifacts.each do |artifact|
      unknown_keys = artifact.metadata.keys - PROPERTIES
      errors << "#{relative(artifact.path)} has unknown field(s): #{unknown_keys.sort.join(', ')}" unless unknown_keys.empty?

      REQUIRED.each do |field|
        errors << "#{relative(artifact.path)} missing required field '#{field}'" if blank?(artifact.metadata[field])
      end

      validate_string(artifact, 'id', pattern: ARTIFACT_ID_PATTERN)
      validate_string(artifact, 'title')
      validate_string(artifact, 'owner')
      validate_string(artifact, 'summary', required: false)
      validate_string(artifact, 'summary_de', required: false)
      validate_string(artifact, 'summary_en', required: false)
      validate_string(artifact, 'source', required: false)
      validate_string(artifact, 'metadata_version', required: false)
      validate_enum(artifact, 'type', TYPES)
      validate_enum(artifact, 'status', STATUSES)
      validate_enum(artifact, 'language', LANGUAGES, required: false)
      validate_date(artifact, 'created')
      validate_date(artifact, 'updated', required: false)
      validate_date(artifact, 'published', required: false)
      validate_boolean(artifact, 'reviewed')
      validate_boolean(artifact, 'generated')
      validate_string_array(artifact, 'audience')
      validate_string_array(artifact, 'channels', allowed: CHANNELS)
      validate_tags(artifact)
      validate_ubiquitous_tags(artifact)
      validate_skills(artifact)
      validate_string(artifact, 'previous', pattern: ARTIFACT_ID_PATTERN, required: false)
      validate_string(artifact, 'next', pattern: ARTIFACT_ID_PATTERN, required: false)
      validate_relations_field(artifact)

      if artifact.metadata['source']
        source = root.join(artifact.metadata['source'])
        errors << "#{relative(artifact.path)} source does not exist: #{artifact.metadata['source']}" unless source.exist?
      end
    end
  end

  def validate_ids(artifacts)
    by_id = artifacts.group_by { |artifact| artifact.metadata['id'] }
    by_id.each do |id, matches|
      next if blank?(id) || matches.length == 1
      errors << "duplicate profile artifact id '#{id}' in #{matches.map { |m| relative(m.path) }.join(', ')}"
    end
  end

  def validate_relations(artifacts)
    known = artifacts.map { |artifact| artifact.metadata['id'] }.compact.to_set
    artifacts.each do |artifact|
      Array(artifact.metadata['relations']).each_with_index do |relation, index|
        location = "#{relative(artifact.path)} relation ##{index + 1}"
        unless relation.is_a?(Hash)
          errors << "#{location} must be a mapping"
          next
        end
        type = relation['type']
        target = relation['target']
        unknown_keys = relation.keys - RELATION_KEYS
        errors << "#{location} has unknown key(s): #{unknown_keys.sort.join(', ')}" unless unknown_keys.empty?
        errors << "#{location} missing type" if blank?(type)
        errors << "#{location} missing target" if blank?(target)
        errors << "#{location} missing status" if blank?(relation['status'])
        errors << "#{location} unknown type '#{type}'" if type && !RELATION_TYPES.include?(type)
        errors << "#{location} unknown status '#{relation['status']}'" if relation['status'] && !RELATION_STATUSES.include?(relation['status'])
        errors << "#{location} target must match #{ARTIFACT_ID_PATTERN.inspect}" if target && target !~ ARTIFACT_ID_PATTERN
        errors << "#{location} rationale must be a string" if relation.key?('rationale') && !relation['rationale'].is_a?(String)
        errors << "#{location} evidence must be a string" if relation.key?('evidence') && !relation['evidence'].is_a?(String)
        errors << "#{location} reviewed must be true or false" if relation.key?('reviewed') && !boolean?(relation['reviewed'])
        warnings << "#{location} references external artifact '#{target}'" if target && !known.include?(target)
      end
    end
  end

  def validate_string(artifact, field, pattern: nil, required: true)
    value = artifact.metadata[field]
    return if !required && value.nil?

    unless value.is_a?(String) && !value.empty?
      errors << "#{relative(artifact.path)} field '#{field}' must be a non-empty string"
      return
    end

    errors << "#{relative(artifact.path)} field '#{field}' must match #{pattern.inspect}" if pattern && value !~ pattern
  end

  def validate_enum(artifact, field, allowed, required: true)
    value = artifact.metadata[field]
    return if !required && value.nil?

    errors << "#{relative(artifact.path)} unknown #{field} '#{value}'" unless allowed.include?(value)
  end

  def validate_date(artifact, field, required: true)
    value = artifact.metadata[field]
    return if !required && value.nil?

    if value.is_a?(Date)
      return
    elsif value.is_a?(String)
      begin
        parsed = Date.iso8601(value)
        return if parsed.to_s == value
      rescue Date::Error
        # handled below
      end
    end

    errors << "#{relative(artifact.path)} field '#{field}' must be an ISO-8601 date"
  end

  def validate_boolean(artifact, field)
    value = artifact.metadata[field]
    return if value.nil?

    errors << "#{relative(artifact.path)} field '#{field}' must be true or false" unless boolean?(value)
  end

  def validate_string_array(artifact, field, allowed: nil)
    value = artifact.metadata[field]
    return if value.nil?

    unless value.is_a?(Array)
      errors << "#{relative(artifact.path)} field '#{field}' must be an array"
      return
    end

    value.each_with_index do |item, index|
      unless item.is_a?(String)
        errors << "#{relative(artifact.path)} field '#{field}' item ##{index + 1} must be a string"
        next
      end
      errors << "#{relative(artifact.path)} field '#{field}' item ##{index + 1} unknown value '#{item}'" if allowed && !allowed.include?(item)
    end
  end

  def validate_tags(artifact)
    tags = artifact.metadata['tags']
    return if tags.nil?

    unless tags.is_a?(Array)
      errors << "#{relative(artifact.path)} field 'tags' must be an array"
      return
    end

    duplicates = tags.group_by(&:itself).select { |_tag, matches| matches.length > 1 }.keys
    errors << "#{relative(artifact.path)} field 'tags' contains duplicate value(s): #{duplicates.join(', ')}" unless duplicates.empty?

    tags.each_with_index do |tag, index|
      unless tag.is_a?(String) && tag =~ TAG_PATTERN
        errors << "#{relative(artifact.path)} field 'tags' item ##{index + 1} must match #{TAG_PATTERN.inspect}"
      end
    end
  end

  def validate_skills(artifact)
    skills = artifact.metadata['skills']
    return if skills.nil?

    unless skills.is_a?(Array)
      errors << "#{relative(artifact.path)} field 'skills' must be an array"
      return
    end

    duplicates = skills.group_by(&:itself).select { |_skill, matches| matches.length > 1 }.keys
    errors << "#{relative(artifact.path)} field 'skills' contains duplicate value(s): #{duplicates.join(', ')}" unless duplicates.empty?

    skills.each_with_index do |skill, index|
      unless skill.is_a?(String) && skill =~ TAG_PATTERN
        errors << "#{relative(artifact.path)} field 'skills' item ##{index + 1} must match #{TAG_PATTERN.inspect}"
      end
    end
  end

  def validate_relations_field(artifact)
    relations = artifact.metadata['relations']
    return if relations.nil? || relations.is_a?(Array)

    errors << "#{relative(artifact.path)} field 'relations' must be an array"
  end

  def validate_ubiquitous_tags(artifact)
    return unless artifact.metadata['type'] == 'Article'

    tags = artifact.metadata['tags']
    return unless tags.is_a?(Array)

    used = (tags & UBIQUITOUS_TAGS).sort
    return if used.empty?

    warnings << "#{relative(artifact.path)} uses ubiquitous tag(s) with no discriminating meaning for related articles: #{used.join(', ')}"
  end

  def validate_series(artifacts)
    by_id = index_by_id(artifacts)
    artifacts.each do |artifact|
      self_id = artifact.metadata['id']

      unless artifact.metadata['type'] == 'Article'
        if %w[previous next].any? { |field| !blank?(artifact.metadata[field]) }
          errors << "#{relative(artifact.path)} 'previous'/'next' are only allowed for Articles"
        end
        next
      end

      %w[previous next].each do |field|
        target = artifact.metadata[field]
        next if blank?(target)

        referenced = by_id[target]
        if referenced.nil?
          errors << "#{relative(artifact.path)} field '#{field}' references unknown artifact '#{target}'"
        elsif referenced.metadata['type'] != 'Article'
          errors << "#{relative(artifact.path)} field '#{field}' must reference an Article, but '#{target}' is a #{referenced.metadata['type']}"
        end
      end

      nxt = artifact.metadata['next']
      if !blank?(nxt) && (paired = by_id[nxt]) && paired.metadata['previous'] != self_id
        warnings << "#{relative(artifact.path)} declares next '#{nxt}', but '#{nxt}' does not declare previous '#{self_id}'"
      end

      prv = artifact.metadata['previous']
      if !blank?(prv) && (paired = by_id[prv]) && paired.metadata['next'] != self_id
        warnings << "#{relative(artifact.path)} declares previous '#{prv}', but '#{prv}' does not declare next '#{self_id}'"
      end
    end
  end

  def public_articles(artifacts)
    artifacts.select do |artifact|
      artifact.metadata['type'] == 'Article' && PUBLIC_STATUSES.include?(artifact.metadata['status'])
    end
  end

  # Newest first by publication date, ties broken by id for deterministic output.
  def sort_articles(articles)
    articles.sort_by { |article| [-publication_ordinal(article), article.metadata['id'].to_s] }
  end

  def publication_ordinal(article)
    date = publication_date(article)
    date ? date.jd : 0
  end

  # Publication date is 'published' when present, otherwise 'created'.
  def publication_date(article)
    raw = article.metadata['published'] || article.metadata['created']
    return raw if raw.is_a?(Date)

    begin
      Date.iso8601(raw.to_s)
    rescue Date::Error
      nil
    end
  end

  def format_date(date)
    date.nil? ? '' : date.strftime('%d.%m.%Y')
  end

  # Language-specific summary with fallback to the language-neutral 'summary'.
  def summary_for(article, language)
    article.metadata["summary_#{language}"] || article.metadata['summary'] || ''
  end

  def tags_in_use(articles)
    articles.flat_map { |article| Array(article.metadata['tags']) }.uniq.sort
  end

  def skills_in_use(articles)
    articles.flat_map { |article| Array(article.metadata['skills']) }.uniq.sort
  end

  # Turns a slug into a readable heading, e.g. "Software-Architektur" -> "Software Architektur".
  def humanize_slug(slug)
    slug.to_s.tr('-', ' ')
  end

  # Common directory of all article sources; the listings live beneath it.
  def articles_base_dir(articles)
    dirs = articles.map { |article| article_source_path(article).dirname }
    return nil if dirs.empty?

    dirs.reduce { |common, dir| common_ancestor(common, dir) }
  end

  def common_ancestor(first, second)
    shared = []
    first.each_filename.to_a.zip(second.each_filename.to_a).each do |left, right|
      break if left.nil? || left != right

      shared << left
    end
    Pathname.new("/#{shared.join('/')}")
  end

  # Relative href from an output directory to a target output path.
  def article_href(from_dir, target_path)
    target_path.relative_path_from(from_dir).to_s
  end

  def tag_page_output_path(articles_dir, tag)
    articles_dir.join('lists', "tag-#{tag}.html")
  end

  def render_list_fragment(articles, from_dir:, language:)
    ['// Generated article list. Do not edit manually.',
     '++++',
     article_list_html(articles, from_dir: from_dir, articles_dir: from_dir, language: language),
     '++++',
     ''].join("\n")
  end

  def render_list_page(title:, articles:, output_dir:, articles_dir:, language:)
    body = ['<p class="article-list-back"><a href="../articles.html">&#8592; Zurück zur Artikelübersicht</a></p>',
            article_list_html(articles, from_dir: output_dir, articles_dir: articles_dir, language: language)].join("\n")

    ['// Generated article list page. Do not edit manually.',
     "= #{title}",
     'ifdef::buildsite[]',
     ':basedir: ../..',
     'endif::[]',
     'include::{includesdir}/../../revinfo.adoc[]',
     ':revdate!:',
     ':revnumber!:',
     ':revremark!:',
     ':active: articles',
     'include::{includesdir}/docheader.adoc[]',
     '',
     '++++',
     body,
     '++++',
     ''].join("\n")
  end

  def article_list_html(articles, from_dir:, articles_dir:, language:)
    return '<div class="article-list"></div>' if articles.empty?

    cards = articles.map { |article| article_card_html(article, from_dir: from_dir, articles_dir: articles_dir, language: language) }
    ['<div class="article-list">', *cards, '</div>'].join("\n")
  end

  def article_card_html(article, from_dir:, articles_dir:, language:)
    href = h(article_href(from_dir, article_source_path(article).sub_ext('.html')))
    title = h(article.metadata['title'])
    date = publication_date(article)
    summary = summary_for(article, language)
    tags = Array(article.metadata['tags'])

    parts = ['  <article class="skillbox article-card">']
    parts << "    <h3 class=\"article-card-title\"><a href=\"#{href}\">#{title}</a></h3>"
    unless date.nil?
      parts << "    <p class=\"article-card-date\"><time datetime=\"#{h(date.iso8601)}\">#{h(format_date(date))}</time></p>"
    end
    parts << "    <p class=\"article-card-summary\">#{h(summary)}</p>" unless summary.empty?
    unless tags.empty?
      parts << "    <p class=\"article-card-tags\">#{tag_links_html(tags, from_dir: from_dir, articles_dir: articles_dir)}</p>"
    end
    parts << '  </article>'
    parts.join("\n")
  end

  def render_article_tags(article, articles_dir)
    tags = Array(article.metadata['tags'])
    return '' if tags.empty?

    from_dir = article_source_path(article).dirname
    ['// Generated article tags. Do not edit manually.',
     '++++',
     "<p class=\"article-card-tags article-tags\">#{tag_links_html(tags, from_dir: from_dir, articles_dir: articles_dir)}</p>",
     '++++',
     ''].join("\n")
  end

  def render_article_comments(article)
    article_id = article.metadata['id'].to_s
    article_title = article.metadata['title'].to_s
    issue_title = "[Artikelkommentar] [#{article_id}] #{article_title}"
    new_issue_url = "https://github.com/#{ARTICLE_COMMENTS_REPOSITORY}/issues/new?" \
                    "template=#{CGI.escape(ARTICLE_COMMENTS_TEMPLATE)}&title=#{CGI.escape(issue_title)}&" \
                    "article_id=#{CGI.escape(article_id)}&article_title=#{CGI.escape(article_title)}"

    ['// Generated article comments. Do not edit manually.',
     'ifdef::buildsite[]',
     '[subs="attributes"]',
     '++++',
     "<section class=\"article-comments\" data-article-comments data-repository=\"#{h(ARTICLE_COMMENTS_REPOSITORY)}\" data-article-id=\"#{h(article_id)}\">",
     '  <h2>Kommentare</h2>',
     '  <p>Fragen, Ergänzungen oder Feedback sind willkommen und werden als öffentliches GitHub-Issue erfasst.</p>',
     "  <p><a class=\"article-comment-create fingerPointsTo\" href=\"#{h(new_issue_url)}\" target=\"_blank\" rel=\"noopener noreferrer\">Diesen Artikel kommentieren</a></p>",
     '  <button class="article-comments-load" type="button">Vorhandene Kommentare laden</button>',
     '  <p class="article-comments-status" aria-live="polite"></p>',
     '  <ul class="article-comments-list"></ul>',
     '</section>',
     '<script src="{basedir}/stylesheet/article-comments.js"></script>',
     '++++',
     'endif::[]',
     ''].join("\n")
  end

  def tag_links_html(tags, from_dir:, articles_dir:)
    tags.map do |tag|
      href = h(article_href(from_dir, tag_page_output_path(articles_dir, tag)))
      "<a class=\"article-card-tag\" href=\"#{href}\">#{h(tag)}</a>"
    end.join(' ')
  end

  def render_navigation(article, all_articles, by_id)
    previous = lookup_article(by_id, article.metadata['previous'])
    nxt = lookup_article(by_id, article.metadata['next'])
    related = related_articles(article, all_articles)

    sections = [
      nav_prev_html(article, previous),
      nav_related_html(article, related),
      nav_next_html(article, nxt)
    ].compact
    return '' if sections.empty?

    lines = []
    lines << '// Generated article navigation. Do not edit manually.'
    lines << '++++'
    lines << '<nav class="article-nav" aria-label="Artikel-Navigation">'
    lines.concat(sections)
    lines << '</nav>'
    lines << '++++'
    lines << ''
    lines.join("\n")
  end

  def nav_prev_html(from_article, target)
    return nil if target.nil?

    href = h(article_link_href(from_article, target))
    title = h(target.metadata['title'])
    "  <div class=\"article-nav-prev\">\n" \
      "    <a href=\"#{href}\" rel=\"prev\"><span class=\"article-nav-label\">&#8592; (Serie) Vorheriger Artikel</span>" \
      "<span class=\"article-nav-title\">#{title}</span></a>\n" \
      '  </div>'
  end

  def nav_next_html(from_article, target)
    return nil if target.nil?

    href = h(article_link_href(from_article, target))
    title = h(target.metadata['title'])
    "  <div class=\"article-nav-next\">\n" \
      "    <a href=\"#{href}\" rel=\"next\"><span class=\"article-nav-label\">(Serie) Nächster Artikel &#8594;</span>" \
      "<span class=\"article-nav-title\">#{title}</span></a>\n" \
      '  </div>'
  end

  def nav_related_html(from_article, related)
    return nil if related.empty?

    items = related.map do |target|
      "      <li><a href=\"#{h(article_link_href(from_article, target))}\">#{h(target.metadata['title'])}</a></li>"
    end
    ['  <div class="article-nav-related">',
     '    <span class="article-nav-heading">Könnte Sie auch interessieren</span>',
     '    <ul>',
     *items,
     '    </ul>',
     '  </div>'].join("\n")
  end

  def related_articles(article, all_articles)
    self_id = article.metadata['id']
    excluded = [self_id, article.metadata['previous'], article.metadata['next']].compact.to_set
    self_tags = meaningful_tags(article)
    linked = related_relation_ids(article, all_articles)

    candidates = all_articles.reject do |candidate|
      excluded.include?(candidate.metadata['id']) || !PUBLIC_STATUSES.include?(candidate.metadata['status'])
    end

    scored = candidates.filter_map do |candidate|
      shared = (self_tags & meaningful_tags(candidate)).length
      is_linked = linked.include?(candidate.metadata['id'])
      next unless is_linked || shared.positive?

      { article: candidate, linked: is_linked, shared: shared }
    end

    scored.sort_by do |entry|
      [entry[:linked] ? 0 : 1, -entry[:shared], -date_ordinal(entry[:article]), entry[:article].metadata['id'].to_s]
    end.first(RELATED_LIMIT).map { |entry| entry[:article] }
  end

  def related_relation_ids(article, all_articles)
    self_id = article.metadata['id']
    article_ids = all_articles.map { |candidate| candidate.metadata['id'] }.to_set
    ids = Set.new

    Array(article.metadata['relations']).each do |relation|
      target = relation.is_a?(Hash) ? relation['target'] : nil
      ids << target if target && article_ids.include?(target)
    end

    all_articles.each do |other|
      next if other.metadata['id'] == self_id

      Array(other.metadata['relations']).each do |relation|
        ids << other.metadata['id'] if relation.is_a?(Hash) && relation['target'] == self_id
      end
    end

    ids
  end

  def meaningful_tags(article)
    Array(article.metadata['tags']) - UBIQUITOUS_TAGS
  end

  def lookup_article(by_id, id)
    return nil if blank?(id)

    article = by_id[id]
    article if article && article.metadata['type'] == 'Article'
  end

  def article_link_href(from_article, to_article)
    from_dir = article_source_path(from_article).dirname
    target = article_source_path(to_article).sub_ext('.html')
    target.relative_path_from(from_dir).to_s
  end

  def article_source_path(article)
    source = article.metadata['source']
    return root.join(source) if source.is_a?(String) && !source.empty?

    article.path.sub_ext('.adoc')
  end

  def article_slug(article)
    article_source_path(article).basename('.adoc').to_s
  end

  def date_ordinal(article)
    value = article.metadata['created']
    return value.jd if value.is_a?(Date)

    begin
      Date.iso8601(value.to_s).jd
    rescue Date::Error
      0
    end
  end

  def index_by_id(artifacts)
    artifacts.each_with_object({}) do |artifact, index|
      id = artifact.metadata['id']
      index[id] = artifact unless blank?(id)
    end
  end

  def boolean?(value)
    value == true || value == false
  end

  def render_index(artifacts, output_path)
    lines = []
    lines << '[[profile-artifact-index]]'
    lines << '= Profile Artifact Index'
    lines << ''
    lines << '// Generated from profile artifact metadata. Do not edit manually.'
    lines << ''
    lines << '[cols="1,1,2,1,2,2", options="header"]'
    lines << '|==='
    lines << '| ID | Type | Title | Status | Channels | Source'
    artifacts.sort_by { |artifact| artifact.metadata['id'].to_s }.each do |artifact|
      metadata = artifact.metadata
      source = metadata['source'] || relative(artifact.path)
      lines << "| #{cell(metadata['id'])}"
      lines << "| #{cell(metadata['type'])}"
      lines << "| #{cell(metadata['title'])}"
      lines << "| #{cell(metadata['status'])}"
      lines << "| #{cell(Array(metadata['channels']).join(', '))}"
      lines << "| `#{cell(source)}`"
    end
    lines << '|==='
    lines << ''
    lines.join("\n")
  end

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end

  def cell(value)
    value.to_s.gsub('|', '\|').gsub("\n", ' ')
  end

  def h(value)
    CGI.escapeHTML(value.to_s)
  end

  def relative(path)
    Pathname.new(path).expand_path.relative_path_from(root).to_s
  rescue ArgumentError
    path.to_s
  end
end

if $PROGRAM_NAME == __FILE__
  default_root = Pathname.new(__dir__).join('..').expand_path
  options = {
    root: default_root,
    profile_dir: nil,
    generate: false,
    output: nil
  }
  OptionParser.new do |parser|
    parser.on('--root PATH') { |value| options[:root] = Pathname.new(value) }
    parser.on('--profile-dir PATH') { |value| options[:profile_dir] = Pathname.new(value) }
    parser.on('--generate') { options[:generate] = true }
    parser.on('--output PATH') { |value| options[:output] = value }
  end.parse!

  root = options[:root]
  profile_dir = options[:profile_dir] || root.join('src-content/profile')
  output = options[:output] || 'src-content/profile/generated/profile-artifact-index.adoc'

  validator = ProfileArtifactValidator.new(root: root, profile_dir: profile_dir)
  artifacts = validator.validate
  validator.report(artifacts)
  exit(1) unless validator.errors.empty?
  if options[:generate]
    path = validator.generate(artifacts, output: output)
    puts "Generated: #{path.relative_path_from(root)}"
    nav_paths = validator.generate_article_navigation(artifacts)
    puts "Generated #{nav_paths.length} article navigation include(s)."
    tag_paths = validator.generate_article_tag_includes(artifacts)
    puts "Generated #{tag_paths.length} article tag include(s)."
    comment_paths = validator.generate_article_comment_includes(artifacts)
    puts "Generated #{comment_paths.length} article comment include(s)."
    list_paths = validator.generate_article_lists(artifacts)
    puts "Generated #{list_paths.length} article list file(s)."
  end
end
