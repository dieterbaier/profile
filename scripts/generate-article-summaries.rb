#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cgi'
require 'date'
require 'fileutils'
require 'optparse'
require 'pathname'
require 'yaml'

class ArticleSummaryGenerator
  ENCODING = 'UTF-8'
  MAX_LINKEDIN_CHARS = 2_000
  SUMMARY_TARGETS = %w[linkedin substack].freeze

  Article = Struct.new(:metadata_path, :metadata, :source_path, :slug, :title, :revremark, :paragraphs, :takeaways, :conclusion, keyword_init: true)

  attr_reader :root, :articles_dir, :template_dir, :output_dir, :errors

  def initialize(root:, articles_dir:, template_dir:, output_dir:)
    @root = Pathname.new(root).expand_path
    @articles_dir = Pathname.new(articles_dir).expand_path
    @template_dir = Pathname.new(template_dir).expand_path
    @output_dir = Pathname.new(output_dir).expand_path
    @errors = []
  end

  def generate
    articles = scan_articles
    FileUtils.rm_rf(output_dir)
    FileUtils.mkdir_p(output_dir)

    generated = articles.flat_map do |article|
      SUMMARY_TARGETS.map do |target|
        output = output_dir.join("#{article.slug}_summary_#{target}.html")
        output.write(render(target, article), encoding: ENCODING)
        output
      end
    end

    generated
  end

  private

  def scan_articles
    Dir.glob(articles_dir.join('**/*.profile.y{a,}ml').to_s).sort.map do |metadata_path|
      metadata_path = Pathname.new(metadata_path)
      metadata = YAML.safe_load(read_text(metadata_path), permitted_classes: [Date], aliases: false)
      next unless metadata.is_a?(Hash) && metadata['type'] == 'Article'

      source = metadata['source'] ? root.join(metadata['source']) : metadata_path.sub_ext('.adoc')
      unless source.exist?
        errors << "#{relative(metadata_path)} references missing article source #{relative(source)}"
        next
      end

      parse_article(metadata_path, metadata, source)
    rescue Psych::SyntaxError => e
      errors << "#{relative(metadata_path)} has invalid YAML: #{e.message.lines.first.strip}"
      nil
    end.compact
  end

  def parse_article(metadata_path, metadata, source)
    text = read_text(source)
    title = text.lines.find { |line| line.start_with?('= ') }&.sub(/^=+\s*/, '')&.strip || metadata['title']
    revremark = text[/^:revremark:\s*(.+)$/, 1]&.strip
    paragraphs = extract_paragraphs(text)
    takeaways = extract_takeaways(text)
    conclusion_section = extract_section(text, 'Fazit')
    conclusion = extract_paragraphs(conclusion_section).first(2)

    Article.new(
      metadata_path: metadata_path,
      metadata: metadata,
      source_path: source,
      slug: source.basename('.adoc').to_s,
      title: title,
      revremark: revremark,
      paragraphs: paragraphs,
      takeaways: takeaways,
      conclusion: conclusion,
    )
  end

  def render(target, article)
    case target
    when 'linkedin'
      render_linkedin(article)
    when 'substack'
      render_substack(article)
    else
      raise ArgumentError, "unknown summary target: #{target}"
    end
  end

  def render_linkedin(article)
    title = "#{article.title}: #{article.revremark || 'Eine praktische Einordnung'}"
    body = [
      first_present(article.paragraphs),
      article.paragraphs[1],
      article.conclusion.first,
    ].compact
    tags = '#DocsAsCode #SoftwareArchitektur #Dokumentation #AsciiDoc #Softwareentwicklung'
    cta = 'Den vollständigen Artikel gibt es hier: [Artikel-Link einsetzen]'

    copy = ([title] + body + [cta, tags]).join("\n\n")
    if copy.length > MAX_LINKEDIN_CHARS
      body = body.first(2)
      copy = ([title] + body + [cta, tags]).join("\n\n")
    end

    render_template('linkedin', {
      'title' => h(title),
      'summary' => render_paragraphs(body),
      'cta' => h(cta),
      'tags' => h(tags),
      'notes' => render_notes([
        "Automatisch aus #{relative(article.source_path)} erzeugt.",
        'Kein kanonischer Artikel-Link angegeben; Platzhalter gesetzt.',
        "LinkedIn-Zeichen ohne notes: #{copy.length}."
      ])
    })
  end

  def render_substack(article)
    subtitle = article.revremark || article.metadata['summary'] || 'Ein kurzer Einstieg in den vollständigen Artikel.'
    body = [
      first_present(article.paragraphs),
      article.paragraphs[1],
      article.paragraphs[2],
      article.conclusion.first,
    ].compact.uniq

    render_template('substack', {
      'title' => h(article.title),
      'subtitle' => h(subtitle),
      'summary' => render_paragraphs(body),
      'cta' => 'Den vollständigen Artikel lesen: [Artikel-Link einsetzen]',
      'tags' => h(Array(article.metadata['tags']).join(', ')),
      'notes' => render_notes([
        "Automatisch aus #{relative(article.source_path)} erzeugt.",
        'Kein kanonischer Artikel-Link angegeben; Platzhalter gesetzt.'
      ])
    })
  end

  def render_template(target, values)
    template = template_dir.join("#{target}.html")
    raise "missing summary template: #{relative(template)}" unless template.exist?

    values.reduce(read_text(template)) do |content, (key, value)|
      content.gsub("{{#{key}}}", value)
    end
  end

  def read_text(path)
    path.read(encoding: ENCODING)
  end

  def render_paragraphs(paragraphs)
    paragraphs.map { |paragraph| "    <p>#{h(paragraph)}</p>" }.join("\n")
  end

  def render_notes(notes)
    notes.map { |note| "      <li>#{h(note)}</li>" }.join("\n")
  end

  def extract_paragraphs(text)
    cleaned = text
      .gsub(/\[source,[\s\S]*?----\n[\s\S]*?\n----/, "\n")
      .gsub(/plantuml::[^\n]+/, "\n")
      .gsub(/include::[^\n]+/, "\n")
      .gsub(/toc::\[\]/, "\n")
      .gsub(/^[:\w-]+:.*$/, "\n")
      .gsub(/^\[.*\]$/, "\n")
      .gsub(/^_{4}$|^-{2}$|^={2,}.*$|^\|===.*$/, "\n")

    cleaned.split(/\n{2,}/)
      .map { |paragraph| normalize_asciidoc(paragraph) }
      .select { |paragraph| paragraph.length > 80 }
      .reject { |paragraph| paragraph.start_with?('ifdef::', 'endif::', 'ifeval::') }
  end

  def extract_takeaways(text)
    extract_section(text, 'Key Takeaways').lines.grep(/^\*\s+/).map { |line| normalize_asciidoc(line.sub(/^\*\s+/, '')) }
  end

  def extract_section(text, title)
    marker = /^==\s+#{Regexp.escape(title)}\s*$/
    lines = text.lines
    start = lines.index { |line| line.match?(marker) }
    return '' unless start

    section = lines[(start + 1)..-1] || []
    stop = section.index { |line| line.start_with?('== ') } || section.length
    section.first(stop).join
  end

  def normalize_asciidoc(text)
    text
      .gsub(/\n+/, ' ')
      .gsub(/https:\/\/\{lang\}\.wikipedia\.org\/wiki\/Clean_Code\[Clean Code Prinzipien\^\]/, 'Clean-Code-Prinzipien')
      .gsub(/https?:\/\/[^\[]+\[([^\]]+)\]/, '\1')
      .gsub(/xref:[^\[]+\[([^\]]+)\]/, '\1')
      .gsub(/`([^`]+)`/, '\1')
      .gsub(/\*([^*]+)\*/, '\1')
      .gsub(/_([^_]+)_/, '\1')
      .gsub(/\s+/, ' ')
      .strip
  end

  def first_present(values)
    Array(values).find { |value| value && !value.empty? }
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
  root = Pathname.new(__dir__).join('..').expand_path
  options = {
    articles_dir: root.join('src-content/profile/site/articles'),
    template_dir: root.join('templates/article-summary-pack'),
    output_dir: root.join('build/summaries')
  }

  OptionParser.new do |parser|
    parser.on('--articles-dir PATH') { |value| options[:articles_dir] = Pathname.new(value) }
    parser.on('--template-dir PATH') { |value| options[:template_dir] = Pathname.new(value) }
    parser.on('--output-dir PATH') { |value| options[:output_dir] = Pathname.new(value) }
  end.parse!

  generator = ArticleSummaryGenerator.new(
    root: root,
    articles_dir: options[:articles_dir],
    template_dir: options[:template_dir],
    output_dir: options[:output_dir]
  )
  generated = generator.generate

  unless generator.errors.empty?
    warn "Article summary generation failed:\n- #{generator.errors.join("\n- ")}"
    exit 1
  end

  puts "Generated article summaries:"
  generated.each { |path| puts "  - #{path.relative_path_from(root)}" }
end
