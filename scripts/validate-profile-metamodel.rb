#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cgi'
require 'date'
require 'digest'
require 'fileutils'
require 'json'
require 'optparse'
require 'pathname'
require 'set'
require 'yaml'

class ProfileArtifactValidator
  REQUIRED = %w[id type title status owner created].freeze
  PROPERTIES = %w[id type title status owner created updated published reviewed generated language translation_of translation_source_digest translation_divergence audience channels summary summary_de summary_en source tags skills previous next relations metadata_version].freeze
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
  # Concrete authoring languages. There is deliberately no 'mixed' value: a page
  # may only include fragments of its own language, so an artifact is always
  # written in exactly one language. Absent metadata means DEFAULT_LANGUAGE.
  LANGUAGES = %w[de en].freeze
  DIGEST_PATTERN = /\A[0-9a-f]{64}\z/
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
    validate_languages(artifacts)
    validate_translations(artifacts)
    validate_ui_terms(artifacts)
    validate_link_references(artifacts)
    validate_fragment_languages
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

  # Writes the stable IDs of articles eligible for the public website. The
  # deployment workflow synchronizes this allowlist to the comments repository,
  # where its issue workflow uses it for semantic article-ID validation.
  def generate_article_comment_allowlist(artifacts, output:)
    article_ids = artifacts.select do |artifact|
      metadata = artifact.metadata
      metadata['type'] == 'Article' && metadata['status'] == 'published' &&
        Array(metadata['channels']).include?('website')
    end.map { |article| article.metadata['id'] }.sort

    output_path = root.join(output)
    FileUtils.mkdir_p(output_path.dirname)
    output_path.write(JSON.pretty_generate({ 'schema_version' => 1, 'article_ids' => article_ids }) + "\n", encoding: 'UTF-8')
    output_path
  end

  # Generates the article listings from metadata: a "recent" include fragment
  # (RECENT_LIMIT newest public articles) plus standalone overview pages for all
  # articles, each tag, and each skill. Fragments live under
  # <articles-dir>/generated/lists and standalone pages under
  # <articles-dir>/generated/pages. Standalone pages are authored for the output
  # location <articles-dir>/lists, so their links resolve once the dedicated
  # Asciidoctor task renders that directory into the site. Returns written paths.
  # One listing set per language, built only from that language's articles: a
  # reader browsing the English listings should not be handed German articles.
  #
  # Unlike the per-article includes, these are standalone pages whose title is
  # parsed before any interface terms are available, so the wording is baked in
  # from the terms file rather than referenced as an attribute.
  def generate_article_lists(artifacts)
    all_articles = artifacts.select { |artifact| artifact.metadata['type'] == 'Article' }
    return [] if all_articles.empty?

    by_language = all_articles.group_by { |article| artifact_language(article) }

    @languages_with_articles = by_language.keys
    @tag_languages = Hash.new { |hash, key| hash[key] = [] }
    @skill_languages = Hash.new { |hash, key| hash[key] = [] }
    by_language.each do |language, articles|
      ordered = public_articles(articles)
      tags_in_use(ordered).each { |tag| @tag_languages[tag] << language }
      skills_in_use(ordered).each { |skill| @skill_languages[skill] << language }
    end

    by_language.flat_map do |language, articles|
      generate_article_lists_for(articles, language)
    end
  end

  def generate_article_lists_for(articles, language)
    articles_dir = articles_base_dir(articles)
    return [] if articles_dir.nil?

    clean_generated_lists(articles_dir)

    lists_dir = articles_dir.join('generated', 'lists')
    pages_dir = articles_dir.join('generated', 'pages')
    FileUtils.mkdir_p(lists_dir)
    FileUtils.mkdir_p(pages_dir)

    terms = ui_terms_values(language)

    # The output location of the standalone pages; used to compute link targets.
    output_dir = articles_dir.join('lists')
    ordered = sort_articles(public_articles(articles))
    written = []

    recent_path = lists_dir.join('recent.adoc')
    recent_path.write(render_list_fragment(ordered.first(RECENT_LIMIT), from_dir: articles_dir, language: language), encoding: 'UTF-8')
    written << recent_path

    all_path = pages_dir.join('all.adoc')
    all_path.write(render_list_page(title: terms.fetch('ui_article_list_all'), articles: ordered,
                                    output_dir: output_dir, articles_dir: articles_dir, language: language,
                                    other_languages: @languages_with_articles - [language]),
                   encoding: 'UTF-8')
    written << all_path

    tags_in_use(ordered).each do |tag|
      tagged = ordered.select { |article| Array(article.metadata['tags']).include?(tag) }
      path = pages_dir.join("tag-#{tag}.adoc")
      title = "#{terms.fetch('ui_article_list_tag_prefix')} #{tag}"
      path.write(render_list_page(title: title, articles: tagged, output_dir: output_dir,
                                  articles_dir: articles_dir, language: language,
                                  other_languages: @tag_languages[tag] - [language]),
                 encoding: 'UTF-8')
      written << path
    end

    skills_in_use(ordered).each do |skill|
      skilled = ordered.select { |article| Array(article.metadata['skills']).include?(skill) }
      path = pages_dir.join("skill-#{skill}.adoc")
      title = "#{terms.fetch('ui_article_list_skill_prefix')} #{humanize_slug(skill)}"
      path.write(render_list_page(title: title, articles: skilled, output_dir: output_dir,
                                  articles_dir: articles_dir, language: language,
                                  other_languages: @skill_languages[skill] - [language]),
                 encoding: 'UTF-8')
      written << path
    end

    written
  end

  # Writes one language switcher per page next to it, empty unless the page
  # really exists in more than one language. A page that merely falls back to the
  # default language is not offered as a variant: that would promise a
  # translation nobody wrote.
  # Derived from the page tree rather than from metadata: the article overview
  # and the generated listings are real pages a reader can land on, but they carry
  # no sidecar. Basing the switcher on artifacts left exactly those pages without
  # one, which is what made a second, differently shaped switcher look necessary.
  def generate_language_switchers(_artifacts = nil)
    clean_generated_language_switchers

    (page_language_groups.values + listing_language_groups.values)
      .select { |variants| variants.length > 1 }
      .flat_map { |variants| write_language_switchers(variants) }
  end

  # One switcher per variant, written next to its source so the fixed include in
  # the page chrome resolves per page.
  def write_language_switchers(variants)
    variants.map do |language, source|
      dir = source.dirname.join('generated')
      FileUtils.mkdir_p(dir)
      path = dir.join("#{source.basename('.adoc')}-langswitch.adoc")
      path.write(render_language_switcher(language, variants, source), encoding: 'UTF-8')
      path
    end
  end

  # Authored pages grouped by what they are, regardless of language: two pages
  # are variants when their output paths differ only by the language prefix.
  def page_language_groups
    site_pages.each_with_object({}) do |(output, source), groups|
      language = output_language(output)
      neutral = language == DEFAULT_LANGUAGE ? output : output.delete_prefix("#{language}/")
      (groups[neutral] ||= {})[language] = Pathname.new(source)
    end
  end

  # The generated listing pages, grouped the same way. They are generated before
  # the switchers, so their sources can be read from disk.
  def listing_language_groups
    groups = {}

    SITE_SOURCE_ROOTS.each do |source_root|
      Dir.glob(profile_dir.join(source_root, '**', 'generated', 'pages', '*.adoc').to_s).sort.each do |path|
        source = Pathname.new(path)
        relative = site_relative_dir(source.dirname)
        next if relative.nil?

        language = output_language(relative.to_s)
        (groups["listing:#{source.basename}"] ||= {})[language] = source
      end
    end

    groups
  end

  def output_language(output_path)
    prefix = output_path.to_s.split('/').first
    LANGUAGES.include?(prefix) && prefix != DEFAULT_LANGUAGE ? prefix : DEFAULT_LANGUAGE
  end

  # Artifacts that are translations of one another, keyed by their group, and
  # only those that are rendered as pages.
  def translation_groups(artifacts)
    artifacts.select { |artifact| page_artifact?(artifact) }
             .group_by { |artifact| translation_group_key(artifact) }
  end

  def page_artifact?(artifact)
    !artifact_output_path(artifact).nil?
  end

  # List items for the main navigation, so the switcher sits in the menu row
  # itself rather than as a separate block. The visible label is a flag; the
  # language name stays on title and aria-label, because a flag alone is not an
  # accessible name and stands for a country rather than a language.
  def render_language_switcher(current_language, variants, current_source)
    entries = variants.keys.sort.map do |language|
      flag = "{ui_language_flag_#{language}}"
      name = "{ui_language_name_#{language}}"

      if language == current_language
        "            <span class=\"language-switch-current\" lang=\"#{language}\" title=\"#{name}\" " \
          "aria-current=\"true\">#{flag}</span>"
      else
        href = h(page_link_href(current_source, variants[language]))
        "            <a href=\"#{href}\" lang=\"#{language}\" hreflang=\"#{language}\" title=\"#{name}\" " \
          "aria-label=\"#{name}\">#{flag}</a>"
      end
    end

    # One list item holding every language, rather than one item per language:
    # the menu row sets a single gap for all its entries, so separate items could
    # only be spaced apart by a negative margin that breaks whenever that gap
    # changes between breakpoints.
    #
    # Raw HTML without block delimiters: this file is included from inside the
    # menu's passthrough block, which already applies attribute substitution.
    # Splitting that block to include it as a block of its own would change the
    # whitespace of every rendered page.
    ['        <li class="language-switch">',
     *entries,
     '        </li>',
     ''].join("\n")
  end

  def clean_generated_language_switchers
    Dir.glob(profile_dir.join('**', 'generated', '*-langswitch.adoc').to_s).each do |path|
      File.delete(path)
    end
  end

  # The rendered site has no metadata, so the translation groups are handed to
  # the metadata injector as output paths it can match against the files it walks.
  def generate_language_alternates(artifacts, output:)
    groups = translation_groups(artifacts).values.select { |variants| variants.length > 1 }

    entries = groups.map do |variants|
      variants.sort_by { |variant| artifact_language(variant) }.to_h do |variant|
        [artifact_language(variant), artifact_output_path(variant)]
      end
    end

    output_path = root.join(output)
    FileUtils.mkdir_p(output_path.dirname)
    output_path.write(
      "#{JSON.pretty_generate({ 'schema_version' => 1, 'default_language' => DEFAULT_LANGUAGE, 'groups' => entries })}\n",
      encoding: 'UTF-8'
    )
    output_path
  end

  # Output path of a page artifact relative to the site root, or nil when the
  # artifact is not rendered as a site page. Derived from the resolved source
  # path rather than the raw metadata string, so it follows profile_dir like the
  # rest of the generator instead of assuming a fixed repository layout.
  def artifact_output_path(artifact)
    path = article_source_path(artifact)
    return nil unless path.to_s.end_with?('.adoc')

    relative = path.relative_path_from(profile_dir).to_s
    return nil if relative.start_with?('..')

    source_root = SITE_SOURCE_ROOTS.find { |name| relative.start_with?("#{name}/") }
    return nil if source_root.nil?

    relative.delete_prefix("#{source_root}/").sub(/\.adoc\z/, '.html')
  rescue ArgumentError
    nil
  end

  # Writes one provenance note per article next to it, empty for originals.
  # A translation always says what it came from; an outdated or deliberately
  # divergent one additionally says how it relates to that text. Both notes can
  # appear together, because staleness and intent are independent.
  def generate_translation_notes(artifacts)
    articles = artifacts.select { |artifact| artifact.metadata['type'] == 'Article' }
    by_id = index_by_id(artifacts)

    clean_generated_translation_notes

    articles.map do |article|
      notes_dir = article_source_path(article).dirname.join('generated')
      FileUtils.mkdir_p(notes_dir)
      path = notes_dir.join("#{article_slug(article)}-translation.adoc")
      path.write(render_translation_note(article, by_id), encoding: 'UTF-8')
      path
    end
  end

  # The freshness of a translation, derived by comparing the digest recorded at
  # translation time against the original's current source. The derived state is
  # a default, not a verdict: re-accepting the original clears it, which is the
  # intended answer to a cosmetic change such as a typo fix.
  def translation_state(article, by_id)
    original_id = article.metadata['translation_of']
    return nil if blank?(original_id)

    original = by_id[original_id]
    return nil if original.nil?

    recorded = article.metadata['translation_source_digest']
    outdated = !blank?(recorded) && recorded != source_digest(original)

    {
      original: original,
      outdated: outdated,
      divergent: !blank?(article.metadata['translation_divergence']),
      untracked: blank?(recorded)
    }
  end

  # Digest of an artifact's full source. The whole file counts, because a change
  # anywhere in it can change what the text says.
  def source_digest(artifact)
    path = article_source_path(artifact)
    return nil unless path.file?

    Digest::SHA256.hexdigest(path.read(encoding: 'UTF-8'))
  end

  def render_translation_note(article, by_id)
    state = translation_state(article, by_id)
    return '' if state.nil?

    href = h(article_link_href(article, state[:original]))
    title = h(state[:original].metadata['title'])

    lines = ['// Generated translation provenance. Do not edit manually.',
             '[subs="attributes"]',
             '++++',
             '<aside class="translation-note">',
             "  <p>{ui_translation_of} <a href=\"#{href}\">#{title}</a>.</p>"]
    lines << '  <p>{ui_translation_outdated}</p>' if state[:outdated]
    lines << '  <p>{ui_translation_divergent}</p>' if state[:divergent]
    lines.concat(['</aside>', '++++', ''])
    lines.join("\n")
  end

  def clean_generated_translation_notes
    Dir.glob(profile_dir.join('**', 'generated', '*-translation.adoc').to_s).each do |path|
      File.delete(path)
    end
  end

  # Outdated translations stay publishable, so they are reported to the author
  # rather than failing the build.
  def report_translation_states(artifacts)
    by_id = index_by_id(artifacts)

    artifacts.select { |artifact| artifact.metadata['type'] == 'Article' }.each do |article|
      state = translation_state(article, by_id)
      next if state.nil?

      location = relative(article.path)
      warnings << "#{location} is outdated: its original '#{state[:original].metadata['id']}' changed since " \
                  'the translation was accepted' if state[:outdated]
      warnings << "#{location} is a translation without a recorded 'translation_source_digest', so its " \
                  'freshness cannot be checked' if state[:untracked]
    end
  end

  # Records the original's current source digest for a translation without
  # touching the translation itself. This is the author override: it declares
  # that the change in the original needed no change here.
  def accept_translation(artifacts, artifact_id)
    by_id = index_by_id(artifacts)
    article = by_id[artifact_id]
    raise ArgumentError, "unknown artifact '#{artifact_id}'" if article.nil?

    original_id = article.metadata['translation_of']
    raise ArgumentError, "'#{artifact_id}' is not a translation" if blank?(original_id)

    original = by_id[original_id]
    raise ArgumentError, "unknown original '#{original_id}'" if original.nil?

    digest = source_digest(original)
    raise ArgumentError, "original '#{original_id}' has no readable source" if digest.nil?

    write_translation_digest(article, digest)
  end

  # The digest lives in the sidecar next to the translation, or in the front
  # matter when the artifact carries its metadata inline.
  def write_translation_digest(article, digest)
    path = article.path
    text = path.read(encoding: 'UTF-8')
    entry = "translation_source_digest: #{digest}"

    updated = if text.match?(/^(\s*)translation_source_digest:.*$/)
                text.sub(/^(\s*)translation_source_digest:.*$/) { "#{Regexp.last_match(1)}#{entry}" }
              else
                text.sub(/^(\s*)translation_of:.*$/) { "#{Regexp.last_match(0)}\n#{Regexp.last_match(1)}#{entry}" }
              end

    path.write(updated, encoding: 'UTF-8')
    path
  end

  # Writes one link registry per language into a generated include. Chrome and
  # content reference pages through these attributes instead of hard-coded paths,
  # so a reference resolves to the same-language page where one exists and to the
  # default language otherwise - always resolving, never leading nowhere.
  #
  # Values are prefixed with {basedir}, which every page already sets to the site
  # root. That keeps the registry independent of how deep a page sits and keeps
  # the relative paths the local and PDF builds rely on; root-relative URLs would
  # have broken both.
  def generate_link_registries(artifacts)
    registry_dir = profile_dir.join('includes', 'generated', 'i18n')
    FileUtils.rm_rf(registry_dir)
    FileUtils.mkdir_p(registry_dir)

    pages = site_pages
    # Languages come from the page tree as well as from the metadata: the keys
    # are derived from the file tree, so the language list has to be too, or a
    # language whose pages carry no sidecar would get no registry at all.
    page_languages = pages.keys.filter_map do |output|
      prefix = output.split('/').first
      prefix if LANGUAGES.include?(prefix) && prefix != DEFAULT_LANGUAGE
    end
    languages = ([DEFAULT_LANGUAGE] + page_languages + artifacts.map { |artifact| artifact_language(artifact) }).uniq

    languages.map do |language|
      entries = link_registry_entries(pages, language)
      report_link_fallbacks(entries, language)
      path = registry_dir.join("links-#{language}.adoc")
      path.write(entries.map { |entry| entry[:lines] }.join, encoding: 'UTF-8')
      path
    end
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

  # Warnings raised while generating, after the validation report was printed.
  def report_warnings(since:)
    new_warnings = warnings.drop(since)
    return if new_warnings.empty?

    puts "\nWarnings:"
    new_warnings.each { |warning| puts "  - #{warning}" }
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
      validate_string(artifact, 'translation_of', pattern: ARTIFACT_ID_PATTERN, required: false)
      validate_string(artifact, 'translation_source_digest', pattern: DIGEST_PATTERN, required: false)
      validate_string(artifact, 'translation_divergence', required: false)
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

  # Declared language of an artifact. Absent metadata means the default
  # language, so existing single-language content stays valid unchanged.
  def artifact_language(artifact)
    artifact.metadata['language'] || DEFAULT_LANGUAGE
  end

  # Language implied by an artifact's location. The first path segment naming a
  # non-default language marks a language subtree; everything else is the
  # default language. One rule covers site pages ('site/en/...'), fragments
  # ('includes/i18n/en/...') and CV variants ('cv/en/...') alike.
  def location_language(artifact)
    segments = artifact.path.relative_path_from(profile_dir).each_filename.to_a
    segments.find { |segment| LANGUAGES.include?(segment) && segment != DEFAULT_LANGUAGE } || DEFAULT_LANGUAGE
  end

  # Keeps the declared language and the file location in sync, so the language
  # of a page can be derived from either side without them drifting apart.
  def validate_languages(artifacts)
    artifacts.each do |artifact|
      declared = artifact.metadata['language']
      # An invalid value is already reported by the enum check.
      next unless declared.nil? || LANGUAGES.include?(declared)

      expected = location_language(artifact)
      next if declared == expected
      next if declared.nil? && expected == DEFAULT_LANGUAGE

      if declared.nil?
        errors << "#{relative(artifact.path)} lies in the '#{expected}' language subtree and must declare 'language: #{expected}'"
      else
        errors << "#{relative(artifact.path)} declares 'language: #{declared}', but its location implies '#{expected}'"
      end
    end
  end

  # Validates translation provenance: which artifact an artifact was translated
  # from, and that the translation fields only appear where they mean something.
  # The original may be in any language; it does not have to be the default one.
  def validate_translations(artifacts)
    by_id = index_by_id(artifacts)

    artifacts.each do |artifact|
      location = relative(artifact.path)
      target = artifact.metadata['translation_of']

      if blank?(target)
        %w[translation_source_digest translation_divergence].each do |field|
          next if blank?(artifact.metadata[field])
          errors << "#{location} field '#{field}' is only allowed on a translation, which requires 'translation_of'"
        end
        next
      end

      if target == artifact.metadata['id']
        errors << "#{location} field 'translation_of' must not reference the artifact itself"
        next
      end

      if translation_cycle?(artifact, by_id)
        errors << "#{location} field 'translation_of' forms a translation cycle through '#{target}'"
        next
      end

      original = by_id[target]
      if original.nil?
        errors << "#{location} field 'translation_of' references unknown artifact '#{target}'"
        next
      end

      unless blank?(original.metadata['translation_of'])
        errors << "#{location} field 'translation_of' must reference the original, but '#{target}' is itself a translation"
        next
      end

      if artifact_language(original) == artifact_language(artifact)
        errors << "#{location} is declared as a translation of '#{target}', but both are written in '#{artifact_language(artifact)}'"
      end
    end
  end

  # Content fragments deliberately do not fall back. A link leading to a German
  # page is still usable, so it falls back and says so; a German paragraph inside
  # an English page is not, so the build stops instead of producing a page in
  # mixed languages. This walks the include tree of every page and rejects any
  # fragment that is not available in the page's own language.
  def validate_fragment_languages
    fragment_root = profile_dir.join('includes', 'i18n')

    pages = page_sources
    pages.each do |page, language|
      walk_includes(page, language, fragment_root)
    end

    report_fragment_coverage(fragment_root, pages.values.uniq)
  end

  # Pages that carry a language: everything the site renders plus the readme.
  def page_sources
    sources = site_pages.values.map { |path| Pathname.new(path) }
    readme = profile_dir.join('readme', 'README.adoc')
    sources << readme if readme.file?

    sources.to_h { |path| [path, path_language(path)] }
  end

  # Language implied by a path, using the same language-subtree rule as the
  # metadata check.
  def path_language(path)
    segments = path.relative_path_from(profile_dir).each_filename.to_a
    segments.find { |segment| LANGUAGES.include?(segment) && segment != DEFAULT_LANGUAGE } || DEFAULT_LANGUAGE
  end

  # Follows include directives from a page, carrying the attributes defined along
  # the way so attribute-driven includes such as '{pe-description-file}' resolve.
  # Conditional blocks are not evaluated: every branch is walked, which can only
  # ask for more translations than a build needs, never fewer.
  def walk_includes(page, language, fragment_root)
    visited = Set.new
    queue = [[page, { 'includesdir' => profile_dir.join('includes').to_s, 'lang' => language }]]

    until queue.empty?
      current, attributes = queue.shift
      next unless visited.add?(current.to_s)
      next unless current.file?

      attributes = attributes.dup
      current.read(encoding: 'UTF-8').each_line do |line|
        if (definition = line.match(/\A:([a-z0-9_-]+):\s+(\S.*?)\s*\z/))
          attributes[definition[1]] = definition[2]
          next
        end

        target = include_target(line, attributes)
        next if target.nil?

        resolved = (current.dirname + target).cleanpath
        next unless check_fragment_language(resolved, page, language, fragment_root)

        queue << [resolved, attributes]
      end
    end
  end

  # The include target of a line, with known attributes substituted, or nil when
  # the line is not an include, is escaped, or stays unresolvable.
  def include_target(line, attributes)
    match = line.match(/\A(\\)?include::([^\[]+)\[/)
    return nil if match.nil? || match[1]

    target = match[2].gsub(/\{([a-z0-9_-]+)\}/) { attributes[Regexp.last_match(1)] || Regexp.last_match(0) }
    target.include?('{') ? nil : target
  end

  # Reports a fragment that belongs to another language or is missing in the
  # page's language. Returns whether the include tree should be followed further.
  def check_fragment_language(resolved, page, language, fragment_root)
    return true unless resolved.to_s.start_with?("#{fragment_root}/")

    fragment_language = resolved.relative_path_from(fragment_root).each_filename.first
    return true unless LANGUAGES.include?(fragment_language)

    relative_fragment = resolved.relative_path_from(fragment_root.join(fragment_language))

    if fragment_language != language
      errors << "#{relative(page)} is written in '#{language}' but includes the '#{fragment_language}' fragment " \
                "#{relative(resolved)}; a page may only include fragments of its own language"
      return false
    end

    unless resolved.file?
      errors << "#{relative(page)} is written in '#{language}', but the fragment '#{relative_fragment}' " \
                "is not available in '#{language}': #{relative(resolved)} is missing"
      return false
    end

    true
  end

  # Untranslated fragments are not an error on their own - only including one on
  # a page of another language is. Reporting them makes the gap visible before
  # someone writes the page that needs them.
  def report_fragment_coverage(fragment_root, languages_in_use)
    default_dir = fragment_root.join(DEFAULT_LANGUAGE)
    return unless default_dir.directory?

    default_fragments = Dir.glob(default_dir.join('**/*.adoc').to_s)
                           .map { |path| Pathname.new(path).relative_path_from(default_dir).to_s }
                           .sort

    # Reported for every language that has pages, whether or not its fragment
    # directory exists yet: a language with no fragments at all is the emptiest
    # coverage there is, not a reason to stay silent.
    (languages_in_use - [DEFAULT_LANGUAGE]).sort.each do |language|
      language_dir = fragment_root.join(language)
      missing = default_fragments.reject { |fragment| language_dir.join(fragment).file? }
      next if missing.empty?

      warnings << "#{language}: #{missing.length} of #{default_fragments.length} content fragment(s) are not " \
                  "translated yet"
    end
  end

  # Page references are attribute references resolved by the generated link
  # registry. A reference no page can satisfy would render as a dead link on
  # every page that carries it, so it is rejected at source level.
  def validate_link_references(artifacts)
    known = site_pages.keys
                                 .reject { |output| language_prefixed?(output) }
                                 .map { |output| link_registry_key(output) }
                                 .to_set

    source_paths.each do |path|
      path.read(encoding: 'UTF-8').each_line.with_index do |line, index|
        line.scan(/\{(url_[a-z0-9_]+)\}/).flatten.each do |reference|
          next if known.include?(reference.sub(/_(lang|marker|pdf)\z/, ''))

          errors << "#{relative(path)} line #{index + 1}: unknown page reference '{#{reference}}'"
        end
      end
    end
  end

  # Authored profile sources that can carry page references.
  def source_paths
    Dir.glob(profile_dir.join('**/*.{adoc,html}').to_s)
       .reject { |path| path.include?('/generated/') }
       .sort
       .map { |path| Pathname.new(path) }
  end

  # Source roots the site build renders into the site root. Every AsciiDoc file
  # below them becomes a page, so the registry is derived from the file tree
  # rather than from metadata: a page without a sidecar - the toolkit, legal and
  # overview pages - still has to be linkable.
  SITE_SOURCE_ROOTS = %w[site cv].freeze

  # Site pages keyed by their output path relative to the site root. Language
  # variants live below their language prefix and are matched to their
  # default-language page by the remaining path.
  def site_pages
    SITE_SOURCE_ROOTS.each_with_object({}) do |source_root, pages|
      dir = profile_dir.join(source_root)
      next unless dir.directory?

      Dir.glob(dir.join('**/*.adoc').to_s).sort.each do |path|
        relative_source = Pathname.new(path).relative_path_from(dir).to_s
        next if relative_source.include?('generated/')
        # Editor configuration, not a page.
        next if File.basename(relative_source).start_with?('.')

        pages[relative_source.sub(/\.adoc\z/, '.html')] = path
      end
    end
  end

  # Attribute name for a page, derived from its output path so every site page
  # has a stable key without a hand-maintained mapping.
  def link_registry_key(output_path)
    "url_#{output_path.sub(/\.html\z/, '').gsub(%r{[/\-.]}, '_')}"
  end

  def link_registry_entries(pages, language)
    default_pages = pages.reject { |output, _| language_prefixed?(output) }

    default_pages.keys.sort.map do |output|
      variant = language == DEFAULT_LANGUAGE ? nil : pages["#{language}/#{output}"]
      target = variant ? "#{language}/#{output}" : output
      resolved = variant ? language : DEFAULT_LANGUAGE
      key = link_registry_key(output)

      # A link that falls back is marked with the language it leads to. The
      # marker is plain text, because attribute values are substituted into HTML
      # passthrough blocks where markup would be escaped. It starts with {nbsp}
      # rather than a space: AsciiDoc strips leading whitespace from attribute
      # values, and putting the space in the markup instead would leave a
      # trailing space on every default-language page.
      marker = resolved == language ? '' : "{nbsp}(#{DEFAULT_LANGUAGE})"

      # An attribute entry needs the space after the colon; ':name:value' is not
      # one and would end the document header, leaving every later reference
      # unresolved. An empty value is written as a bare ':name:'.
      marker_line = marker.empty? ? ":#{key}_marker:" : ":#{key}_marker: #{marker}"

      lines = ":#{key}: {basedir}/#{target}\n:#{key}_lang: #{resolved}\n#{marker_line}\n"

      # The CV is the only page that also ships as a PDF, and the PDF is written
      # next to its HTML. Giving it a registry entry keeps the download link in
      # the shared CV chrome language-aware like every other reference.
      lines += ":#{key}_pdf: {basedir}/#{target.sub(/\.html\z/, '.pdf')}\n" if output == 'cv.html'

      {
        key: key,
        output: output,
        resolved: resolved,
        fallback: resolved != language,
        lines: lines
      }
    end
  end

  def language_prefixed?(output_path)
    prefix = output_path.split('/').first
    LANGUAGES.include?(prefix) && prefix != DEFAULT_LANGUAGE
  end

  # Falling back is legitimate, but it is worth knowing about: it is the list of
  # pages a reader in that language still gets in the default language.
  def report_link_fallbacks(entries, language)
    return if language == DEFAULT_LANGUAGE

    falling_back = entries.select { |entry| entry[:fallback] }
    return if falling_back.empty?

    warnings << "#{language}: #{falling_back.length} of #{entries.length} page reference(s) fall back to " \
                "'#{DEFAULT_LANGUAGE}': #{falling_back.map { |entry| entry[:output] }.sort.join(', ')}"
  end

  # Interface terms must be complete per language. Content references may fall
  # back to the default language and say so, but a menu label or a status message
  # has nowhere to say it, so a missing key is an error rather than a fallback.
  def validate_ui_terms(artifacts)
    i18n_dir = profile_dir.join('includes', 'i18n')

    # Checked without testing the directory first: docheader.adoc includes the
    # default terms unconditionally, so a missing directory breaks every page and
    # must produce the same contract error as a missing file.
    default_path = ui_terms_path(i18n_dir, DEFAULT_LANGUAGE)
    unless default_path.file?
      errors << "missing interface terms for the default language: #{relative(default_path)}"
      return
    end

    default_keys = ui_terms_keys(default_path)
    if default_keys.empty?
      errors << "#{relative(default_path)} defines no 'ui_*' interface terms"
      return
    end

    languages_in_use = artifacts.map { |artifact| artifact_language(artifact) }.uniq

    (LANGUAGES - [DEFAULT_LANGUAGE]).each do |language|
      path = ui_terms_path(i18n_dir, language)

      unless path.file?
        # Only a language that content actually uses needs its interface terms.
        errors << "#{language} content exists, but its interface terms are missing: #{relative(path)}" if languages_in_use.include?(language)
        next
      end

      keys = ui_terms_keys(path)
      missing = default_keys - keys
      unknown = keys - default_keys

      errors << "#{relative(path)} is missing interface term(s): #{missing.sort.join(', ')}" unless missing.empty?
      errors << "#{relative(path)} defines interface term(s) unknown to #{relative(default_path)}: #{unknown.sort.join(', ')}" unless unknown.empty?
    end

    ([DEFAULT_LANGUAGE] + LANGUAGES).uniq.each do |language|
      path = ui_terms_path(i18n_dir, language)
      validate_ui_terms_format(path) if path.file?
    end
  end

  # Interface term files are included into the AsciiDoc document header, where a
  # blank line - and a comment line inside an include - ends the header. Anything
  # after that point silently stops being a header attribute, which disables
  # ':stylesheet:' and ':copycss:' and makes the site render with the default
  # Asciidoctor theme. The symptom looks nothing like the cause, so the format is
  # validated rather than left to memory.
  def validate_ui_terms_format(path)
    path.read(encoding: 'UTF-8').lines.each_with_index do |line, index|
      next if line.match?(/\A:ui_[a-z0-9_]+:\s/)

      reason = if line.strip.empty?
                 'a blank line ends the AsciiDoc header'
               elsif line.start_with?('//')
                 'a comment line inside a header include ends the header'
               else
                 'only attribute entries are allowed'
               end
      errors << "#{relative(path)} line #{index + 1}: #{reason}; interface term files must contain nothing but ':ui_*:' entries"
    end
  end

  def ui_terms_path(i18n_dir, language)
    i18n_dir.join("ui-#{language}.adoc")
  end

  # Interface terms as values, resolved the same way the AsciiDoc cascade does:
  # the default language defines every key, the page language overrides what it
  # translates. Used where a value has to be baked into generated output because
  # no page header is available to resolve an attribute reference.
  def ui_terms_values(language)
    i18n_dir = profile_dir.join('includes', 'i18n')
    [DEFAULT_LANGUAGE, language].uniq.each_with_object({}) do |candidate, terms|
      path = ui_terms_path(i18n_dir, candidate)
      next unless path.file?

      path.read(encoding: 'UTF-8').lines.each do |line|
        match = line.match(/\A:(ui_[a-z0-9_]+):\s+(\S.*?)\s*\z/)
        terms[match[1]] = match[2] if match
      end
    end
  end

  # Attribute names defined in an interface term file, ignoring comments.
  def ui_terms_keys(path)
    path.read(encoding: 'UTF-8').lines.filter_map do |line|
      match = line.match(/\A:(ui_[a-z0-9_]+):/)
      match && match[1]
    end
  end

  # Walks the translation_of chain and reports whether it revisits an artifact.
  def translation_cycle?(artifact, by_id)
    seen = [artifact.metadata['id']].compact
    current = artifact

    loop do
      target = current.metadata['translation_of']
      return false if blank?(target)
      return true if seen.include?(target)

      seen << target
      current = by_id[target]
      return false if current.nil?
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

  # The articles directory a set of articles belongs to; the listings live
  # beneath it. Derived from the enclosing 'articles' directory rather than from
  # the common ancestor of the sources: with a single article in one language the
  # common ancestor is that article's own subdirectory, which would bury that
  # language's listings one level too deep.
  def articles_base_dir(articles)
    dirs = articles.map { |article| article_source_path(article).dirname }
    return nil if dirs.empty?

    roots = dirs.filter_map { |dir| enclosing_articles_dir(dir) }.uniq
    return roots.min_by { |dir| dir.to_s.length } unless roots.empty?

    dirs.reduce { |common, dir| common_ancestor(common, dir) }
  end

  # Nearest ancestor directory named 'articles', or nil when the sources do not
  # follow that convention.
  def enclosing_articles_dir(dir)
    current = dir
    until current.basename.to_s == 'articles'
      parent = current.parent
      return nil if parent == current

      current = parent
    end
    current
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

  # Names the other languages that publish articles for this listing. Deliberately
  # without a count: a number would be a claim about how much is on the other side,
  # and 'one further article' is already wrong when that language has fewer. Naming
  # the languages stays true for any number of articles and any number of languages.
  def other_languages_note(language, others, terms)
    return '' if others.empty?

    names = others.sort.map { |other| terms.fetch("ui_language_name_#{other}", other) }
    sentence = terms.fetch('ui_article_list_other_languages', '').sub('%languages%', names.join(', '))
    return '' if sentence.empty?

    "<p class=\"article-list-languages\">#{h(sentence)}</p>"
  end

  def render_list_page(title:, articles:, output_dir:, articles_dir:, language:, other_languages: [])
    body = [other_languages_note(language, other_languages, ui_terms_values(language)),
            '<p class="article-list-back"><a href="../articles.html">&#8592; {ui_article_list_back}</a></p>',
            article_list_html(articles, from_dir: output_dir, articles_dir: articles_dir, language: language)]
           .reject(&:empty?).join("\n")

    ['// Generated article list page. Do not edit manually.',
     "= #{title}",
     ':lang: ' + language,
     'ifdef::buildsite[]',
     ":basedir: #{site_root_relative_prefix(output_dir)}",
     'endif::[]',
     'include::{includesdir}/../../revinfo.adoc[]',
     ':revdate!:',
     ':revnumber!:',
     ':revremark!:',
     ':active: articles',
     'include::{includesdir}/docheader.adoc[]',
     '',
     '[subs="attributes"]',
     '++++',
     body,
     '++++',
     ''].join("\n")
  end

  # Relative prefix from an output directory back to the site root, used as
  # {basedir}. A hard-coded '../..' only holds for the default language, which
  # sits directly under the site root; a language subtree is one level deeper and
  # would resolve its stylesheet and menu links inside its own directory.
  def site_root_relative_prefix(output_dir)
    relative = site_relative_dir(output_dir)
    return '../..' if relative.nil?

    depth = relative.each_filename.count
    depth.zero? ? '.' : Array.new(depth, '..').join('/')
  end

  # Path of a directory relative to the site root it belongs to, or nil when it
  # is outside the rendered source roots.
  def site_relative_dir(dir)
    SITE_SOURCE_ROOTS.each do |source_root|
      root = profile_dir.join(source_root)
      next unless dir.to_s == root.to_s || dir.to_s.start_with?("#{root}/")

      return dir.relative_path_from(root)
    end
    nil
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

    # Status wording for the browser script. The values stay AsciiDoc attribute
    # references so the block's "subs=attributes" resolves them against the page's
    # own interface terms, which makes the script itself free of any wording.
    comment_terms = {
      'i18n-empty' => '{ui_comments_empty}',
      'i18n-loading' => '{ui_comments_loading}',
      'i18n-error' => '{ui_comments_error}',
      'i18n-count-one' => '{ui_comments_count_one}',
      'i18n-count-many' => '{ui_comments_count_many}'
    }.map { |name, value| "data-#{name}=\"#{value}\"" }.join(' ')

    ['// Generated article comments. Do not edit manually.',
     'ifdef::buildsite[]',
     '[subs="attributes"]',
     '++++',
     "<section class=\"article-comments\" data-article-comments data-repository=\"#{h(ARTICLE_COMMENTS_REPOSITORY)}\" data-article-id=\"#{h(article_id)}\" #{comment_terms}>",
     '  <h2>{ui_comments_heading}</h2>',
     '  <p>{ui_comments_intro}</p>',
     "  <p><a class=\"article-comment-create fingerPointsTo\" href=\"#{h(new_issue_url)}\" target=\"_blank\" rel=\"noopener noreferrer\">{ui_comments_create}</a></p>",
     '  <button class="article-comments-load" type="button">{ui_comments_load}</button>',
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
    # The wording comes from the interface terms of the page this include
    # lands on, so a translated article gets translated navigation.
    lines << '[subs="attributes"]'
    lines << '++++'
    lines << '<nav class="article-nav" aria-label="{ui_article_nav_label}">'
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
      "    <a href=\"#{href}\" rel=\"prev\"><span class=\"article-nav-label\">&#8592; {ui_article_nav_prev}</span>" \
      "<span class=\"article-nav-title\">#{title}</span></a>\n" \
      '  </div>'
  end

  def nav_next_html(from_article, target)
    return nil if target.nil?

    href = h(article_link_href(from_article, target))
    title = h(target.metadata['title'])
    "  <div class=\"article-nav-next\">\n" \
      "    <a href=\"#{href}\" rel=\"next\"><span class=\"article-nav-label\">{ui_article_nav_next} &#8594;</span>" \
      "<span class=\"article-nav-title\">#{title}</span></a>\n" \
      '  </div>'
  end

  def nav_related_html(from_article, related)
    return nil if related.empty?

    page_language = artifact_language(from_article)
    items = related.map do |target|
      marker = artifact_language(target) == page_language ? '' : "&#160;(#{artifact_language(target)})"
      "      <li><a href=\"#{h(article_link_href(from_article, target))}\">#{h(target.metadata['title'])}#{marker}</a></li>"
    end
    ['  <div class="article-nav-related">',
     '    <span class="article-nav-heading">{ui_article_nav_related}</span>',
     '    <ul>',
     *items,
     '    </ul>',
     '  </div>'].join("\n")
  end

  def related_articles(article, all_articles)
    self_id = article.metadata['id']
    # Translations of this article are excluded along with the article itself.
    # They share its tags, and resolving a suggestion to the reader's language
    # would otherwise turn a variant of this very article into a recommendation
    # to read it.
    self_group = translation_group_key(article)
    own_variants = all_articles.select { |candidate| translation_group_key(candidate) == self_group }
                               .map { |candidate| candidate.metadata['id'] }
    excluded = (own_variants + [self_id, article.metadata['previous'], article.metadata['next']]).compact.to_set
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

    ranked = scored.sort_by do |entry|
      [entry[:linked] ? 0 : 1, -entry[:shared], -date_ordinal(entry[:article]), entry[:article].metadata['id'].to_s]
    end.map { |entry| entry[:article] }

    prefer_same_language(ranked, artifact_language(article), all_articles).first(RELATED_LIMIT)
  end

  # Recommendations are resolved like page references: the same-language variant
  # of a suggested article wins, and a suggestion that exists only in the default
  # language is still offered rather than dropped - a reader can follow it, and
  # the link says which language it leads to.
  def prefer_same_language(articles, language, all_articles)
    groups = all_articles.group_by { |candidate| translation_group_key(candidate) }
    seen = Set.new

    articles.filter_map do |candidate|
      key = translation_group_key(candidate)
      next unless seen.add?(key)

      variant = groups.fetch(key, []).find { |sibling| artifact_language(sibling) == language }
      variant || candidate
    end
  end

  # Articles that are translations of one another share a group key, so a
  # suggestion can be swapped for its variant in the reader's language.
  def translation_group_key(article)
    article.metadata['translation_of'] || article.metadata['id']
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

  # Relative href between two pages, computed on their rendered locations rather
  # than their sources. Generated listing pages are authored under
  # 'generated/pages' but rendered into 'lists', so source paths would give the
  # wrong depth.
  def page_link_href(from_source, to_source)
    from = page_output_path(from_source)
    to = page_output_path(to_source)
    to.relative_path_from(from.dirname).to_s
  end

  def page_output_path(source)
    dir = source.dirname
    return dir.parent.parent.join('lists', source.basename('.adoc').to_s + '.html') if listing_source?(dir)

    source.sub_ext('.html')
  end

  def listing_source?(dir)
    dir.basename.to_s == 'pages' && dir.parent.basename.to_s == 'generated'
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
    output: nil,
    article_comment_allowlist: nil,
    accept_translation: nil,
    language_alternates: nil
  }
  OptionParser.new do |parser|
    parser.on('--root PATH') { |value| options[:root] = Pathname.new(value) }
    parser.on('--profile-dir PATH') { |value| options[:profile_dir] = Pathname.new(value) }
    parser.on('--generate') { options[:generate] = true }
    parser.on('--output PATH') { |value| options[:output] = value }
    parser.on('--article-comment-allowlist PATH') { |value| options[:article_comment_allowlist] = value }
    parser.on('--accept-translation ID') { |value| options[:accept_translation] = value }
    parser.on('--language-alternates PATH') { |value| options[:language_alternates] = value }
  end.parse!

  root = options[:root]
  profile_dir = options[:profile_dir] || root.join('src-content/profile')
  output = options[:output] || 'src-content/profile/generated/profile-artifact-index.adoc'

  validator = ProfileArtifactValidator.new(root: root, profile_dir: profile_dir)
  artifacts = validator.validate
  validator.report(artifacts)
  exit(1) unless validator.errors.empty?

  if options[:accept_translation]
    path = validator.accept_translation(artifacts, options[:accept_translation])
    puts "Accepted current original for #{options[:accept_translation]}: #{path.relative_path_from(root)}"
    exit(0)
  end

  warnings_before_generate = validator.warnings.length
  if options[:generate]
    path = validator.generate(artifacts, output: output)
    puts "Generated: #{path.relative_path_from(root)}"
    nav_paths = validator.generate_article_navigation(artifacts)
    puts "Generated #{nav_paths.length} article navigation include(s)."
    tag_paths = validator.generate_article_tag_includes(artifacts)
    puts "Generated #{tag_paths.length} article tag include(s)."
    comment_paths = validator.generate_article_comment_includes(artifacts)
    puts "Generated #{comment_paths.length} article comment include(s)."
    allowlist_path = validator.generate_article_comment_allowlist(
      artifacts,
      output: options[:article_comment_allowlist] || 'build/article-comments/allowed-article-ids.json'
    )
    puts "Generated article comment allowlist: #{allowlist_path.relative_path_from(root)}"
    list_paths = validator.generate_article_lists(artifacts)
    puts "Generated #{list_paths.length} article list file(s)."
    note_paths = validator.generate_translation_notes(artifacts)
    puts "Generated #{note_paths.length} translation note(s)."
    switcher_paths = validator.generate_language_switchers(artifacts)
    puts "Generated #{switcher_paths.length} language switcher(s)."
    alternates_path = validator.generate_language_alternates(
      artifacts,
      output: options[:language_alternates] || 'build/site-metadata/language-alternates.json'
    )
    puts "Generated language alternates: #{alternates_path.relative_path_from(root)}"
    registry_paths = validator.generate_link_registries(artifacts)
    puts "Generated #{registry_paths.length} link registry file(s)."
    validator.report_translation_states(artifacts)
    validator.report_warnings(since: warnings_before_generate)
  end
end
