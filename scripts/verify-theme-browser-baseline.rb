#!/usr/bin/env ruby
# frozen_string_literal: true

# Asks the theme stylesheets whether they stay inside the browser baseline the
# published site is read on.
#
# This exists because of a failure mode a stylesheet shares with a missing
# image: nothing reports it. A CSS declaration an engine does not understand is
# dropped silently, by design — that is what makes CSS forward compatible. The
# build renders, the validators pass, the page loads, and the layout the
# declaration was carrying is simply gone. The only party that finds out is a
# reader, on a device nobody develops on.
#
# Two such declarations were found on a television browser and are what this
# checks for.
#
# `gap` in a flex container needs Chromium 84. Television browsers are far
# behind: LG webOS 5 ships Chromium 68, webOS 6 ships 79, Samsung Tizen 6 ships
# 76. A menu whose entry spacing lives only in `gap` therefore renders with no
# spacing at all there, and its underlines run into one another. In a grid
# container the same property is fine, because grid `gap` has been supported
# since Chromium 57.
#
# The check is therefore written as "a rule using `gap` has to show that it is a
# grid" rather than "a flex container must not use `gap`". The two are not the
# same question: a container declares its display in one rule and adjusts its
# spacing in another, so a rule carrying a `gap` frequently says nothing about
# the layout mode it belongs to, and only the grid side can be proven locally.
#
# An emoji rendered as text is the other one, and it is a stricter rule than it
# first looks. A flag is a pair of regional indicator characters, and only a font
# carrying the flag ligature turns them into a flag; every other font shows the
# two letters. Desktop systems hide that behind a system emoji font, television
# systems frequently ship none.
#
# Naming the bundled webfont is not the fix it appears to be, and the first
# attempt at this check said it was. That font is the OT-SVG build of Noto Color
# Emoji, which Chromium does not draw at all — and naming it makes matters
# worse, because the browser then finds the character in the webfont's cmap and
# stops falling back to the system font it could have drawn. The rule is
# therefore about the character, not about the font: an emoji the theme renders
# has to be an image.
#
# Interface terms are read alongside the stylesheets, because a flag reached the
# page as an attribute value rather than through a `content` declaration. Asking
# only the stylesheet would leave exactly the case that was reported unchecked.

require 'optparse'
require 'pathname'

module ThemeBrowserBaseline
  # The oldest engine the published site is expected to render on. It is a
  # statement, not a detection: it says which features may be relied on, and it
  # is the reason each rule below exists.
  BASELINE = 'Chromium 68 (LG webOS 5)'

  # Rules that still render an emoji as text, recorded against the issue that
  # replaces them: https://github.com/dieterbaier/profile/issues/101
  #
  # They are reported on every run and do not fail the build. Written down, the
  # debt has a name and an end; left out of the rule, the check would pass for
  # the wrong reason and say nothing about what is missing on the page.
  RECORDED = [
    '.fingerPointsTo::before',
    '.highlight.info::before',
    '.highlight.warning::before',
    '.highlight.error::before',
    '.highlight.tip::before'
  ].freeze

  GAP_DECLARATION = /(?<![\w-])(gap|row-gap|column-gap)\s*:/.freeze

  # What makes a rule recognizably a grid container. A declared display is the
  # clear case; a `grid-template-*` or `grid-auto-*` property is the other one,
  # because a rule that only adjusts an existing grid inside a media query does
  # not repeat its display.
  #
  # The evidence has to be positive, and it has to be in the rule that carries
  # the `gap`. A flex container declares its display somewhere else just as
  # readily — `.mainnav > ul:first-child` adds `gap` inside a media query while
  # `display: flex` sits on `.mainnav ul` — so asking "is this flex?" cannot see
  # it. Asking "is this demonstrably grid?" can.
  GRID_DISPLAY = /display\s*:\s*(?:inline-)?grid\b/.freeze
  GRID_PROPERTY = /(?<![\w-])grid-[a-z-]+\s*:/.freeze

  # Pictographs, symbols, and the regional indicators that make up a flag. The
  # set is deliberately wider than the emoji this theme uses today, because the
  # rule is about the class of character, not about the ones already present.
  EMOJI = /[\u{1F000}-\u{1FAFF}\u{1F1E6}-\u{1F1FF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]/.freeze

  # A declaration block and its prelude. Innermost blocks only, which is what a
  # declaration ever lives in; an `@media` prelude carries no declarations of
  # its own and so never matches.
  RULE = /([^{}]+)\{([^{}]*)\}/m.freeze

  COMMENT = %r{/\*.*?\*/}m.freeze

  # An interface term as AsciiDoc attribute entry: `:name: value`.
  TERM = /^:([a-z0-9_]+):[ \t]*(.*)$/.freeze

  # `reason` separates rules that fail for unrelated causes, because they read
  # differently to whoever fixes them: one is a layout that silently disappears,
  # the other a character that silently turns into letters.
  Finding = Struct.new(:file, :line, :subject, :reason, :detail, keyword_init: true)

  module_function

  # Every innermost declaration block, with the line its prelude starts on.
  #
  # Comments are blanked rather than removed so the line numbers keep pointing
  # at the file as it is written, and so a comment that talks about a rule is
  # not mistaken for the rule itself.
  #
  # A prelude is cut at its last `;`, because the first block of a file absorbs
  # whatever statements precede it — an `@import`, a `@charset` — and those are
  # not part of the selector.
  def rules(text)
    stripped = text.gsub(COMMENT) { |comment| comment.gsub(/[^\n]/, ' ') }

    found = []
    offset = 0

    while (match = RULE.match(stripped, offset))
      raw = match[1]
      cut = raw.rindex(';')
      prelude = cut ? raw[(cut + 1)..] : raw

      # The line of the selector itself, not of the position the prelude starts
      # at: that position is wherever the previous rule ended, which is a line
      # nobody would look at.
      selector_at = match.begin(1) + (raw.length - prelude.length) +
                    (prelude.length - prelude.lstrip.length)

      found << {
        selector: prelude.strip.gsub(/\s+/, ' '),
        body: match[2],
        line: stripped[0...selector_at].count("\n") + 1
      }
      offset = match.end(0)
    end

    found
  end

  def grid_container?(rule)
    rule[:body].match?(GRID_DISPLAY) || rule[:body].match?(GRID_PROPERTY)
  end

  # Spacing that only an engine at or above Chromium 84 applies. Reported
  # regardless of which of the three properties carries it: all three are the
  # same feature, and a menu missing its row spacing fails the same way as one
  # missing its column spacing.
  def gap_findings(path, rule)
    return [] if grid_container?(rule)

    rule[:body].scan(GAP_DECLARATION).map do |(property)|
      Finding.new(
        file: path, line: rule[:line], subject: rule[:selector], reason: :flex_gap,
        detail: "`#{property}` outside a grid container needs Chromium 84; " \
                'space the items with margins instead'
      )
    end
  end

  # An emoji written into the stylesheet itself, which in practice means a
  # `content` declaration on a pseudo-element.
  def emoji_rule_findings(path, rule)
    return [] unless rule[:body].match?(EMOJI)

    recorded = RECORDED.include?(rule[:selector])

    [Finding.new(
      file: path, line: rule[:line], subject: rule[:selector],
      reason: recorded ? :emoji_text_recorded : :emoji_text,
      detail: 'renders an emoji as text; draw it as an image instead, because no ' \
              'font can be assumed to have it'
    )]
  end

  def stylesheet_findings(path, text)
    rules(text).flat_map do |rule|
      gap_findings(path, rule) + emoji_rule_findings(path, rule)
    end
  end

  # An interface term carrying an emoji. The term is substituted into markup as
  # text, so it is the same failure as a `content` declaration and is reported
  # the same way: a term states wording, and a flag is not wording.
  def term_findings(path, text)
    text.each_line.with_index(1).filter_map do |line, number|
      match = TERM.match(line)
      next unless match && match[2].match?(EMOJI)

      Finding.new(
        file: path, line: number, subject: match[1], reason: :emoji_text,
        detail: 'carries an emoji, which reaches the page as text; let the ' \
                'stylesheet draw it and name it here by class instead'
      )
    end
  end

  # `stylesheets` and `interface_terms` are maps of label to file content, so a
  # caller can check a checkout, a temporary tree, or a single file without this
  # having to know where any of it lives.
  def findings(stylesheets:, interface_terms: {})
    stylesheets.flat_map { |path, text| stylesheet_findings(path, text) } +
      interface_terms.flat_map { |path, text| term_findings(path, text) }
  end

  def read(paths)
    paths.sort.to_h { |path| [path.to_s, path.read] }
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}

  OptionParser.new do |parser|
    parser.on('--theme-dir PATH', 'Directory holding the theme stylesheets') { |value| options[:theme] = value }
    parser.on('--interface-dir PATH', 'Directory holding the interface terms') { |value| options[:terms] = value }
  end.parse!

  unless options[:theme]
    warn 'usage: verify-theme-browser-baseline.rb --theme-dir PATH [--interface-dir PATH]'
    exit(1)
  end

  theme = Pathname.new(options[:theme])
  unless theme.directory?
    warn "The theme directory '#{theme}' does not exist."
    exit(1)
  end

  stylesheets = ThemeBrowserBaseline.read(theme.glob('*.css'))
  terms = options[:terms] ? ThemeBrowserBaseline.read(Pathname.new(options[:terms]).glob('ui-*.adoc')) : {}

  found = ThemeBrowserBaseline.findings(stylesheets: stylesheets, interface_terms: terms)
  recorded, failing = found.partition { |finding| finding.reason == :emoji_text_recorded }

  unless recorded.empty?
    puts "#{recorded.length} recorded exception(s) still render an emoji as text:"
    recorded.each { |finding| puts "  - #{finding.file}:#{finding.line} #{finding.subject}" }
    puts '  Tracked as https://github.com/dieterbaier/profile/issues/101; not a failure here.'
  end

  if failing.empty?
    puts "The theme stays inside the supported browser baseline (#{ThemeBrowserBaseline::BASELINE})."
    exit(0)
  end

  warn "The theme leaves the supported browser baseline (#{ThemeBrowserBaseline::BASELINE}) in #{failing.length} place(s):"
  failing.each do |finding|
    warn "  - #{finding.file}:#{finding.line} #{finding.subject}"
    warn "      #{finding.detail}"
  end
  warn '  An engine that does not understand a declaration drops it without an error, so this'
  warn '  reaches a reader rather than the build unless it is reported here.'
  exit(1)
end
