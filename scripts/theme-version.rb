#!/usr/bin/env ruby
# frozen_string_literal: true

# Gives the theme's stylesheets and scripts a URL that changes when they do, and
# checks that a rendered target actually uses it.
#
# Without this a deploy reaches a returning reader only in part. The stylesheet
# URL never changed, so a browser that still held the previous one kept using it
# against freshly fetched HTML. The two are not independent: since the language
# switcher draws its flag from a class rather than writing it as a character,
# markup and stylesheet have to be of the same generation, and a page that pairs
# new markup with an old stylesheet renders a switcher with nothing in it. That
# is what a phone showed after the flags were changed.
#
# The mismatch is not a caching mistake by the browser. The server sends neither
# `Cache-Control` nor `Expires` for these files, and a browser then caches
# heuristically — roughly a tenth of the age the file had when it was fetched.
# The stylesheet changed rarely and was therefore old and kept for a long time;
# the HTML changes on nearly every deploy and was kept briefly. The rule that
# produced the mismatch is the same rule for both files.
#
# One version for every stylesheet and script, rather than one per file. They
# are small, they change together in practice, and a single value is one thing
# to reason about at a URL. Fonts are left out: their names already carry the
# version they were vendored at, so their URLs change on their own.
#
# The version is the content, not the build. A timestamp or a commit would give
# every deploy new URLs and throw away caches that were still correct.

require 'digest'
require 'optparse'
require 'pathname'

module ThemeVersion
  # Extensions whose URL has to carry the version. A font or an image is
  # addressed by a name that already changes with its content.
  VERSIONED = %w[.css .js].freeze

  # Long enough that two different themes will not collide in the lifetime of
  # this site, short enough to read in a URL.
  LENGTH = 10

  Reference = Struct.new(:file, :line, :asset, :found, keyword_init: true)

  module_function

  # Every file whose URL the version stands for, by the name a reference uses.
  def assets(theme_dir)
    Pathname.new(theme_dir).children
            .select { |path| path.file? && VERSIONED.include?(path.extname) }
            .sort
            .to_h { |path| [path.basename.to_s, path.read] }
  end

  # The name is hashed along with the content, so renaming a file changes the
  # version even when nothing inside it did — a reference to the old name is
  # then a different URL rather than a silently identical one.
  def version(assets)
    digest = Digest::SHA256.new
    assets.each do |name, content|
      digest << name << "\0" << content << "\0"
    end
    digest.hexdigest[0, LENGTH]
  end

  # A reference to one of the assets, wherever a rendered file makes one: an
  # HTML `href`/`src`, or an `@import` in a stylesheet or an inline `<style>`.
  # Matching the file name rather than a URL shape keeps this indifferent to how
  # the reference was written and to how deep in the tree it sits.
  #
  # The lookbehind is what keeps `menuactivation.css` from matching inside
  # `shortsmenuactivation.css`.
  def reference_pattern(asset)
    /(?<![\w.-])#{Regexp.escape(asset)}(\?[^"'\s)>]*)?/
  end

  # References that do not carry the current version, so a browser holding the
  # previous file would go on using it.
  def stale(target_dir, assets:, version:)
    expected = "?v=#{version}"
    root = Pathname.new(target_dir)

    root.glob('**/*.{html,css}').sort.flat_map do |file|
      relative = file.relative_path_from(root).to_s
      stale_in(file.read, relative, assets.keys, expected)
    end
  end

  # A version belongs in a URL and never in a file name. AsciiDoc writes the
  # stylesheet to a file named by the same value that addresses it, so a value
  # meant as a URL can land on disk: `style.css?v=…` is a legal file name here
  # and is rejected by the artifact upload, which fails the build after it has
  # rendered. Asked of the target rather than of the settings that produced it,
  # because any of several of them can put it there.
  def misnamed(target_dir)
    root = Pathname.new(target_dir)
    return [] unless root.directory?

    root.glob('**/*')
        .select { |path| path.file? && path.basename.to_s.include?('?') }
        .map { |path| path.relative_path_from(root).to_s }
        .sort
  end

  def stale_in(text, relative, names, expected)
    found = []

    text.each_line.with_index(1) do |line, number|
      names.each do |asset|
        line.scan(reference_pattern(asset)) do
          query = Regexp.last_match(1)
          next if query == expected

          found << Reference.new(file: relative, line: number, asset: asset, found: query)
        end
      end
    end

    found
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}

  OptionParser.new do |parser|
    parser.on('--theme-dir PATH', 'Directory holding the theme stylesheets and scripts') do |value|
      options[:theme] = value
    end
    parser.on('--target-dir PATH', 'Rendered target to check; omit to print the version') do |value|
      options[:target] = value
    end
  end.parse!

  unless options[:theme]
    warn 'usage: theme-version.rb --theme-dir PATH [--target-dir PATH]'
    exit(1)
  end

  theme = Pathname.new(options[:theme])
  unless theme.directory?
    warn "The theme directory '#{theme}' does not exist."
    exit(1)
  end

  assets = ThemeVersion.assets(theme)
  if assets.empty?
    warn "The theme directory '#{theme}' holds no stylesheet or script to version."
    exit(1)
  end

  version = ThemeVersion.version(assets)

  # Printing the version is how the build learns it. Nothing else is written to
  # stdout in that mode, so the caller can read it directly.
  unless options[:target]
    puts version
    exit(0)
  end

  target = Pathname.new(options[:target])
  unless target.directory?
    puts "The target '#{target}' was not rendered; no theme references to check."
    exit(0)
  end

  misnamed = ThemeVersion.misnamed(target)
  unless misnamed.empty?
    warn "#{misnamed.length} file(s) in '#{target}' carry a version in their name rather than in a URL:"
    misnamed.each { |path| warn "  - #{path}" }
    warn '  A version addresses a file; it is not part of what the file is called.'
  end

  stale = ThemeVersion.stale(target, assets: assets, version: version)
  unless stale.empty?
    warn "#{stale.length} theme reference(s) in '#{target}' do not carry the current version (#{version}):"
    stale.each do |reference|
      warn "  - #{reference.file}:#{reference.line} #{reference.asset}#{reference.found}"
    end
    warn '  A reader holding the previous file keeps using it against this page, and nothing'
    warn '  reports the mismatch — the page renders, with the older stylesheet.'
  end

  exit(1) unless misnamed.empty? && stale.empty?

  puts "Every theme reference in '#{target}' carries the current version (#{version})."
  exit(0)
end
