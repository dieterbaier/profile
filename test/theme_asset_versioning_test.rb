# frozen_string_literal: true

# Behaviour specification bridge for the theme asset versioning check.
#
# Minitest is a classic (non-BDD) runner, so each test method name is a
# sanitized translation of a scenario title in features/theme-asset-versioning.feature,
# with Given/When/Then comment anchors separating Arrange, Act, and Assert.
#
# The version itself is asked of a hash of file contents, which needs no files
# on disk. The reference check reads a rendered target, so those scenarios build
# an isolated one in a temporary directory, the way the asset reference tests do.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'

require_relative '../scripts/theme-version'

class ThemeAssetVersioningTest < Minitest::Test
  THEME = {
    'style.css' => "body { color: #244055; }\n",
    'navigation.js' => "// nav\n"
  }.freeze

  # Builds an isolated rendered target from file bodies and yields what the
  # check reports about it.
  def with_target(files, assets: THEME, version: nil)
    version ||= ThemeVersion.version(assets)

    Dir.mktmpdir('theme-version-test') do |dir|
      root = Pathname.new(dir)

      files.each do |relative, body|
        path = root + relative
        path.dirname.mkpath
        path.write(body)
      end

      yield(ThemeVersion.stale(root, assets: assets, version: version))
    end
  end

  def test_the_version_follows_the_content_of_the_theme
    # Given: two themes whose stylesheets differ
    one = THEME
    other = THEME.merge('style.css' => "body { color: #000000; }\n")

    # When: each is versioned
    # Then: the versions differ
    refute_equal ThemeVersion.version(one), ThemeVersion.version(other)
  end

  def test_the_same_theme_is_versioned_the_same_way
    # Given: the same theme read twice
    once = THEME.dup
    again = THEME.dup

    # When: each is versioned
    # Then: the version is identical, so unchanged files keep their caches
    assert_equal ThemeVersion.version(once), ThemeVersion.version(again)
  end

  def test_renaming_a_file_changes_the_version
    # Given: a theme whose file was renamed but not edited
    renamed = { 'theme.css' => THEME.fetch('style.css'), 'navigation.js' => THEME.fetch('navigation.js') }

    # When: it is versioned
    # Then: the version changes, because the old name is now a different URL
    refute_equal ThemeVersion.version(THEME), ThemeVersion.version(renamed)
  end

  def test_only_stylesheets_and_scripts_are_versioned
    # Given: a theme holding a font and an image next to its stylesheet
    Dir.mktmpdir('theme-version-assets') do |dir|
      root = Pathname.new(dir)
      { 'style.css' => 'body {}', 'navigation.js' => '// nav',
        'noto.woff2' => 'binary', 'favicon.ico' => 'binary',
        'cv-theme.yml' => 'theme:' }.each { |name, body| (root + name).write(body) }

      # When: its assets are collected
      collected = ThemeVersion.assets(root)

      # Then: only the stylesheet and the script are among them
      assert_equal %w[navigation.js style.css], collected.keys.sort
    end
  end

  def test_a_reference_carrying_the_current_version_is_accepted
    # Given: a page linking the stylesheet with the current version
    version = ThemeVersion.version(THEME)
    pages = { 'index.html' => %(<link rel="stylesheet" href="./stylesheet/style.css?v=#{version}">\n) }

    with_target(pages) do |stale|
      # When: the target is checked
      # Then: nothing is reported
      assert_empty stale
    end
  end

  def test_a_reference_without_a_version_is_reported
    # Given: a page linking the stylesheet by its plain name
    pages = { 'index.html' => %(<head>\n<link rel="stylesheet" href="./stylesheet/style.css">\n</head>\n) }

    with_target(pages) do |stale|
      # When: the target is checked
      # Then: it is reported with the file and the line it stands on
      assert_equal 1, stale.length
      assert_equal 'index.html', stale.first.file
      assert_equal 2, stale.first.line
      assert_equal 'style.css', stale.first.asset
      assert_nil stale.first.found
    end
  end

  def test_a_reference_carrying_a_previous_version_is_reported
    # Given: a page linking the stylesheet with the version of an earlier deploy
    pages = { 'index.html' => %(<link rel="stylesheet" href="./stylesheet/style.css?v=0000000000">\n) }

    with_target(pages) do |stale|
      # When: the target is checked
      # Then: it is reported, because that URL serves what the reader already holds
      assert_equal ['style.css'], stale.map(&:asset)
      assert_equal '?v=0000000000', stale.first.found
    end
  end

  def test_a_stylesheet_importing_another_one_is_checked_like_a_page
    # Given: a stylesheet in the target importing the vendored framework
    assets = THEME.merge('asciidoctor.css' => "/* framework */\n")
    version = ThemeVersion.version(assets)
    files = {
      'index.html' => %(<link rel="stylesheet" href="./stylesheet/style.css?v=#{version}">\n),
      'stylesheet/style.css' => %(@import url("./asciidoctor.css");\n)
    }

    with_target(files, assets: assets, version: version) do |stale|
      # When: the target is checked
      # Then: its import is checked, because no page mentions that file
      assert_equal ['asciidoctor.css'], stale.map(&:asset)
      assert_equal 'stylesheet/style.css', stale.first.file
    end
  end

  def test_a_name_that_ends_in_another_assets_name_is_not_mistaken_for_it
    # Given: a page linking shortsmenuactivation.css with the current version
    assets = {
      'menuactivation.css' => "/* menu */\n",
      'shortsmenuactivation.css' => "/* shorts menu */\n"
    }
    version = ThemeVersion.version(assets)
    pages = { 'shorts.html' => %(<style>@import "../stylesheet/shortsmenuactivation.css?v=#{version}";</style>\n) }

    with_target(pages, assets: assets, version: version) do |stale|
      # When: the target is checked
      # Then: menuactivation.css is not reported inside it
      assert_empty stale
    end
  end

  def test_a_target_that_was_never_rendered_reports_nothing
    # Given: no rendered target at all
    Dir.mktmpdir('theme-version-missing') do |dir|
      absent = Pathname.new(dir) + 'never-rendered'

      # When: a directory that does not exist is checked
      # Then: nothing is reported
      assert_empty ThemeVersion.stale(absent, assets: THEME, version: ThemeVersion.version(THEME))
    end
  end
end
