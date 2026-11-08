# frozen_string_literal: true

# Behaviour specification bridge for the README badges.
#
# Bridged from features/readme-badges.feature by the sanitized scenario title.

require 'minitest/autorun'

class ReadmeBadgesTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_badges_are_images_in_the_source
    # Given: the profile sources
    sources = Dir.glob(File.join(ROOT, 'src-content/profile/**/*.adoc')).reject { |path| path.include?('/generated/') }

    # When: they are searched for a badge written as an exclamation mark before a link
    tricks = sources.select { |path| File.read(path).include?('!link:') }

    # Then: none is found, because Pandoc 3 escapes that exclamation mark
    refute_empty sources
    assert_empty tricks.map { |path| path.delete_prefix("#{ROOT}/") }
  end

  def test_remote_badges_keep_their_url
    # Given: the Pandoc call that converts the README to Markdown
    task = File.read(File.join(ROOT, 'build.gradle'))[/abstract class PandocTask .*?\n}\n/m]

    # When: its options are read
    options = task.scan(/'(--[a-z-]+)/).flatten

    # Then: it does not extract media, so a badge keeps its shields.io URL
    assert_includes options, '--wrap'
    refute(options.any? { |option| option.start_with?('--extract-media') })
  end
end
