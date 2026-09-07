# frozen_string_literal: true

# Behaviour specification bridge for the theme browser baseline check.
#
# Minitest is a classic (non-BDD) runner, so each test method name is a
# sanitized translation of a scenario title in features/theme-browser-baseline.feature,
# with Given/When/Then comment anchors separating Arrange, Act, and Assert.
#
# The check reads file contents rather than a directory, so every test states a
# whole theme inline. That keeps each scenario readable as the stylesheet it is
# about, and it is why no temporary tree is needed here.

require 'minitest/autorun'

require_relative '../scripts/verify-theme-browser-baseline'

class ThemeBrowserBaselineTest < Minitest::Test
  FLAG = "\u{1F1E6}\u{1F1F9}"
  EMOJI_STACK = '"Noto Color Emoji", "Noto Sans", sans-serif'
  SWITCHER = '.mainnav ul .language-switch'

  def findings(css, terms: nil)
    stylesheets = { 'style.css' => css }
    interface = terms ? { 'ui-de.adoc' => terms } : {}

    ThemeBrowserBaseline.findings(stylesheets: stylesheets, interface_terms: interface)
  end

  def test_spacing_an_engine_below_the_baseline_drops_is_reported
    # Given: a rule that spaces its items with gap and says nothing about grid
    css = <<~CSS
      .mainnav ul {
          display: flex;
          gap: 2rem;
      }
    CSS

    # When: the theme is checked
    found = findings(css)

    # Then: the rule is reported with the property that carries the spacing
    assert_equal 1, found.length
    assert_equal :flex_gap, found.first.reason
    assert_equal '.mainnav ul', found.first.subject
    assert_equal 1, found.first.line
    assert_includes found.first.detail, '`gap`'
  end

  def test_row_spacing_is_reported_like_column_spacing
    # Given: a rule using row-gap and column-gap outside a grid
    css = <<~CSS
      .contactrow {
          display: flex;
          column-gap: 1rem;
          row-gap: 0.5rem;
      }
    CSS

    # When: the theme is checked
    found = findings(css)

    # Then: both properties are reported, because they are the same feature
    assert_equal %i[flex_gap flex_gap], found.map(&:reason)
    assert(found.any? { |finding| finding.detail.include?('`column-gap`') })
    assert(found.any? { |finding| finding.detail.include?('`row-gap`') })
  end

  def test_a_grid_container_may_space_its_items_with_gap
    # Given: a rule that declares a grid display and spaces its items with gap
    css = <<~CSS
      .article-nav {
          display: grid;
          gap: 1rem;
      }
    CSS

    # When: the theme is checked
    # Then: nothing is reported, because grid spacing predates the baseline
    assert_empty findings(css)
  end

  def test_a_grid_adjusted_without_repeating_its_display_is_still_a_grid
    # Given: a rule that only changes the tracks of a grid and its spacing
    css = <<~CSS
      footer .footer-box {
          grid-template-columns: 1fr;
          gap: 0.75rem;
      }
    CSS

    # When: the theme is checked
    # Then: nothing is reported, because the grid properties are the evidence
    assert_empty findings(css)
  end

  def test_spacing_written_as_margins_is_accepted
    # Given: a flex container whose items carry their spacing as margins
    css = <<~CSS
      .mainnav ul {
          display: flex;
          flex-wrap: wrap;
      }

      .mainnav ul > li {
          margin-right: 2rem;
      }
    CSS

    # When: the theme is checked
    # Then: nothing is reported
    assert_empty findings(css)
  end

  def test_an_emoji_rendered_as_text_is_reported
    # Given: a rule whose content is an emoji
    css = <<~CSS
      .languages li.flag-at:before {
          content: "#{FLAG}";
          margin-right: 0.25rem;
      }
    CSS

    # When: the theme is checked
    found = findings(css)

    # Then: the rule is reported, because no font can be assumed to draw it
    assert_equal 1, found.length
    assert_equal :emoji_text, found.first.reason
    assert_equal '.languages li.flag-at:before', found.first.subject
  end

  def test_naming_the_bundled_emoji_font_does_not_make_the_rule_acceptable
    # Given: the same rule with the emoji webfont in its font-family
    css = <<~CSS
      .languages li.flag-at:before {
          content: "#{FLAG}";
          font-family: #{EMOJI_STACK};
      }
    CSS

    # When: the theme is checked
    found = findings(css)

    # Then: it is still reported, because that font is one Chromium cannot draw
    assert_equal [:emoji_text], found.map(&:reason)
  end

  def test_a_flag_drawn_as_an_image_is_accepted
    # Given: a rule that draws the flag as a background image
    css = <<~CSS
      .languages li.flag-at:before {
          content: "";
          background-image: url("data:image/svg+xml,%3Csvg/%3E");
      }
    CSS

    # When: the theme is checked
    # Then: nothing is reported
    assert_empty findings(css)
  end

  def test_an_interface_term_carrying_an_emoji_is_reported
    # Given: a term whose value is a flag
    terms = ":ui_language_flag_de: #{FLAG}\n"

    # When: the theme is checked
    found = findings('', terms: terms)

    # Then: it is reported, because a term reaches the page as text
    assert_equal 1, found.length
    assert_equal :emoji_text, found.first.reason
    assert_equal 'ui_language_flag_de', found.first.subject
    assert_equal 1, found.first.line
  end

  def test_a_term_that_carries_no_emoji_is_left_alone
    # Given: the interface terms of a language without a flag among them
    terms = ":ui_language_name_de: Deutsch\n:ui_nav_home: Home\n"

    # When: the theme is checked
    # Then: nothing is reported
    assert_empty findings('', terms: terms)
  end

  def test_a_recorded_exception_is_reported_without_failing_the_check
    # Given: a rule that renders an emoji and is recorded against its own issue
    recorded = ThemeBrowserBaseline::RECORDED.first
    css = "#{recorded} { content: \"\u{1F4A1}\"; }\n"

    # When: the theme is checked
    found = findings(css)

    # Then: it is reported apart from the findings that fail
    assert_equal [:emoji_text_recorded], found.map(&:reason)
    assert_equal recorded, found.first.subject
  end

  def test_a_comment_is_not_read_as_a_rule
    # Given: a comment that talks about gap and about an emoji
    css = <<~CSS
      /* Spacing is written as margins rather than `gap`, and the flag #{FLAG}
         needs the bundled emoji font. */
      .mainnav ul {
          display: flex;
      }

      .article-list {
          display: flex;
          gap: 1rem;
      }
    CSS

    # When: the theme is checked
    found = findings(css)

    # Then: nothing is reported, and the reported lines still match the file
    assert_equal 1, found.length
    assert_equal '.article-list', found.first.subject
    assert_equal 7, found.first.line
  end
end
