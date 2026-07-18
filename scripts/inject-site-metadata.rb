# frozen_string_literal: true

require 'optparse'
require 'pathname'
require 'uri'

class SiteMetadataInjector
  attr_reader :site_dir, :base_url

  def initialize(site_dir:, base_url:)
    @site_dir = Pathname.new(site_dir).expand_path
    @base_url = normalize_base_url(base_url)
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
    html_path.write(updated, encoding: 'UTF-8')
  end
end

if $PROGRAM_NAME == __FILE__
  options = { required: false }
  OptionParser.new do |parser|
    parser.on('--site-dir PATH') { |value| options[:site_dir] = value }
    parser.on('--base-url URL') { |value| options[:base_url] = value }
    parser.on('--required') { options[:required] = true }
  end.parse!

  if options[:base_url].nil? || options[:base_url].strip.empty?
    abort 'SITE_BASE_URL is required for this build' if options[:required]
    warn 'SITE_BASE_URL is not set; canonical links are omitted'
    exit 0
  end

  abort '--site-dir is required' unless options[:site_dir]
  SiteMetadataInjector.new(site_dir: options[:site_dir], base_url: options[:base_url]).inject
end
