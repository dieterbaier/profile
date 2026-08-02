# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pathname'
require 'uri'

class SiteMetadataInjector
  attr_reader :site_dir, :base_url, :alternates, :default_language

  # The rendered site carries no metadata, so the translation groups are handed
  # in as output paths: a map of language to path, produced by the profile
  # generator, which is the only place that knows which pages are variants of
  # one another. A page that merely falls back to another language is not in it.
  def initialize(site_dir:, base_url:, alternates: nil)
    @site_dir = Pathname.new(site_dir).expand_path
    @base_url = normalize_base_url(base_url)
    @default_language = alternates && alternates['default_language']
    @alternates = index_alternates(alternates)
  end

  def index_alternates(alternates)
    return {} if alternates.nil?

    Array(alternates['groups']).each_with_object({}) do |group, index|
      group.each_value { |path| index[path] = group }
    end
  end

  # Alternate links for one output path, or an empty list when the page has no
  # variants. Every variant of a group links to all variants including itself,
  # which is what search engines expect, plus x-default for the default language.
  def alternate_links(relative_path)
    group = alternates[relative_path]
    return [] if group.nil?

    links = group.map do |language, path|
      %(<link rel="alternate" hreflang="#{language}" href="#{canonical_url(site_dir.join(path))}">)
    end

    fallback = group[default_language]
    links << %(<link rel="alternate" hreflang="x-default" href="#{canonical_url(site_dir.join(fallback))}">) if fallback
    links
  end

  def inject
    raise ArgumentError, "site directory does not exist: #{site_dir}" unless site_dir.directory?

    site_dir.glob('**/*.html').sort.each do |html_path|
      inject_file(html_path)
    end
  end

  def canonical_url(html_path)
    relative = html_path.relative_path_from(site_dir).to_s.tr('\\', '/')
    public_path = if relative == 'index.html'
                    ''
                  elsif relative.end_with?('/index.html')
                    relative.delete_suffix('index.html')
                  else
                    relative
                  end

    encoded_path = public_path.split('/', -1).map { |segment| encode_path_segment(segment) }.join('/')
    URI.join("#{base_url}/", encoded_path).to_s
  end

  private

  def encode_path_segment(segment)
    URI::DEFAULT_PARSER.escape(segment, /[^A-Za-z0-9\-._~]/)
  end

  def normalize_base_url(value)
    raise ArgumentError, 'base URL must not be empty' if value.nil? || value.strip.empty?

    uri = URI.parse(value.strip)
    unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.query && !uri.fragment
      raise ArgumentError, 'base URL must be an absolute HTTPS URL without credentials, query, or fragment'
    end

    normalized_path = uri.path.to_s.sub(%r{/+$}, '')
    uri.path = normalized_path
    uri.to_s.sub(%r{/+$}, '')
  rescue URI::InvalidURIError => e
    raise ArgumentError, "invalid base URL: #{e.message}"
  end

  def inject_file(html_path)
    content = html_path.read(encoding: 'UTF-8')
    return unless content.include?('</head>')

    canonical = %(<link rel="canonical" href="#{canonical_url(html_path)}">)
    canonical_link_pattern = %r{<link\b[^>]*\brel\s*=\s*["']canonical["'][^>]*>}i
    updated = if content.match?(canonical_link_pattern)
                content.sub(canonical_link_pattern) { canonical }
              else
                content.sub('</head>') { "#{canonical}\n</head>" }
              end

    # Injection is idempotent: previously written alternates are replaced rather
    # than appended, because the listing pages re-run this step.
    updated = updated.gsub(%r{^<link\b[^>]*\brel="alternate"[^>]*>\n}, '')
    links = alternate_links(html_path.relative_path_from(site_dir).to_s.tr('\\', '/'))
    updated = updated.sub('</head>') { "#{links.join("\n")}\n</head>" } unless links.empty?

    html_path.write(updated, encoding: 'UTF-8')
  end
end

if $PROGRAM_NAME == __FILE__
  options = { required: false }
  OptionParser.new do |parser|
    parser.on('--site-dir PATH') { |value| options[:site_dir] = value }
    parser.on('--base-url URL') { |value| options[:base_url] = value }
    parser.on('--required') { options[:required] = true }
    parser.on('--alternates PATH') { |value| options[:alternates] = value }
  end.parse!

  if options[:base_url].nil? || options[:base_url].strip.empty?
    abort 'SITE_BASE_URL is required for this build' if options[:required]
    warn 'SITE_BASE_URL is not set; canonical links are omitted'
    exit 0
  end

  abort '--site-dir is required' unless options[:site_dir]

  alternates = nil
  if options[:alternates] && File.file?(options[:alternates])
    alternates = JSON.parse(File.read(options[:alternates], encoding: 'UTF-8'))
  end

  SiteMetadataInjector.new(
    site_dir: options[:site_dir], base_url: options[:base_url], alternates: alternates
  ).inject
end
