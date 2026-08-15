#!/usr/bin/env ruby
# frozen_string_literal: true

# Asks a rendered target whether the files its pages ask for are actually in it.
#
# The selection that puts an asset into a target is metadata work, and it is
# tested as such. This checks the other end: what a page ends up requesting from
# the target it was rendered into. The two fail independently, which is the
# point — a correct selection copied to the wrong place, or a converter that
# rewrites references while it moves files, both produce a page that renders
# without complaint and shows a broken image.
#
# That failure mode is why this exists rather than a rule about copy tasks. A
# missing image raises no error anywhere in the build: asciidoctor does not
# resolve it, pandoc does not resolve it, and the browser reports it to a reader
# rather than to CI.

require 'optparse'
require 'pathname'
require 'cgi'

module RenderedAssetReferences
  # What a reader fetches as a second request, rather than what the build reads
  # while it renders. Only the former has to exist in the target.
  ASSET_EXTENSIONS = %w[.svg .png .jpg .jpeg .gif .webp .avif .ico].freeze

  # Anything the target does not host and cannot be asked about.
  EXTERNAL = %r{\A(?:[a-z][a-z0-9+.-]*:|//|#|\?)}i.freeze

  Reference = Struct.new(:page, :target, :line, keyword_init: true)

  module_function

  # HTML `src`/`href` and Markdown `![](…)`, which is what the two rendered
  # forms of an article use. Both appear in the Markdown export: pandoc keeps an
  # <img> tag wherever the source carried attributes it cannot express.
  def references(text)
    found = []
    text.each_line.with_index(1) do |line, number|
      line.scan(/(?:src|href)\s*=\s*["']([^"']+)["']/i) { |(target)| found << [target, number] }
      line.scan(/!\[[^\]]*\]\(([^)\s]+)/) { |(target)| found << [target, number] }
    end
    found
  end

  def asset?(target)
    return false if target.nil? || target.strip.empty?
    return false if target.match?(EXTERNAL)

    ASSET_EXTENSIONS.include?(File.extname(strip_url_suffix(target)).downcase)
  end

  def strip_url_suffix(target)
    target.split('#').first.to_s.split('?').first.to_s
  end

  # A reference is a URL, so it is percent-encoded and rooted at the target
  # rather than at the filesystem. Both have to be undone before it names a file.
  def resolve(target, page, root)
    relative = CGI.unescape(strip_url_suffix(target))
    base = relative.start_with?('/') ? Pathname.new(root) : page.dirname
    (base + relative.sub(%r{\A/}, '')).cleanpath
  end

  def unresolved(root)
    root = Pathname.new(root).expand_path
    return [] unless root.directory?

    missing = []
    Pathname.glob(root.join('**', '*.{html,md}')).sort.each do |page|
      references(page.read(encoding: 'UTF-8')).each do |target, line|
        next unless asset?(target)
        next if resolve(target, page, root).file?

        missing << Reference.new(page: page.relative_path_from(root).to_s, target: target, line: line)
      end
    rescue ArgumentError, Errno::EILSEQ
      # A page that cannot be read as text carries no reference this can judge.
      next
    end
    missing
  end
end

if $PROGRAM_NAME == __FILE__
  options = { target_dir: nil, label: nil }
  OptionParser.new do |parser|
    parser.on('--target-dir PATH') { |value| options[:target_dir] = value }
    parser.on('--label NAME') { |value| options[:label] = value }
  end.parse!

  unless options[:target_dir]
    warn 'usage: verify-rendered-asset-references.rb --target-dir PATH [--label NAME]'
    exit(1)
  end

  root = Pathname.new(options[:target_dir])
  label = options[:label] || root.basename.to_s

  unless root.directory?
    puts "The '#{label}' target was not rendered; no asset references to check."
    exit(0)
  end

  missing = RenderedAssetReferences.unresolved(root)
  if missing.empty?
    puts "Every asset the '#{label}' target asks for is in it."
    exit(0)
  end

  warn "The '#{label}' target asks for #{missing.length} file(s) it does not contain:"
  missing.each { |reference| warn "  - #{reference.page}:#{reference.line} -> #{reference.target}" }
  warn '  The page renders without complaint and shows a broken image, so this is reported here'
  warn '  rather than by the renderer.'
  exit(1)
end
