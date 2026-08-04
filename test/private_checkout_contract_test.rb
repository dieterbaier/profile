# frozen_string_literal: true

# Behaviour specification bridge for the sibling-checkout contract of the
# private target.
#
# These scenarios are Gradle-level: the rules live in the build, so the only
# honest verification runs the build. Each test invokes the real task with
# PROFILE_PRIVATE_DIR pointed at a temporary tree, so the sibling arrangement is
# exercised without the real private repository.
#
# This costs a Gradle start per test, which is why it is a separate file with its
# own task rather than part of the fast metadata suite.
#
# Bridged from features/private-content-target.feature by the sanitized
# scenario title.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'open3'

class PrivateCheckoutContractTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def gradle(task, private_dir:)
    Open3.capture3(
      { 'PROFILE_PRIVATE_DIR' => private_dir.to_s },
      './gradlew', '--quiet', '--console=plain', task,
      chdir: ROOT
    )
  end

  def content_root(dir)
    path = Pathname.new(dir) + 'src-content/profile/site/articles'
    path.mkpath
    path
  end

  def test_a_missing_sibling_checkout_names_the_path_it_expected
    # Given: no checkout at the configured path
    missing = File.join(Dir.tmpdir, 'profile-private-absent-on-purpose')
    refute File.exist?(missing)

    # When: the private target is asked for
    _out, err, status = gradle('checkPrivateCheckout', private_dir: missing)

    # Then: the build stops naming what it expected and where
    refute_predicate status, :success?
    assert_includes err, 'private content checkout was not found'
    assert_includes err, missing
  end

  def test_a_checkout_without_a_content_root_names_the_directory_it_expected
    # Given: a checkout that exists but carries no content root
    Dir.mktmpdir('profile-private-empty') do |dir|
      # When: the private target is asked for
      _out, err, status = gradle('checkPrivateCheckout', private_dir: dir)

      # Then: the build stops naming the content root it expected
      refute_predicate status, :success?
      assert_includes err, 'no content root'
      assert_includes err, File.join(dir, 'src-content/profile/site')
    end
  end

  def test_a_checkout_carrying_its_own_tooling_stops_the_build
    # Given: a private checkout with a schema of its own
    Dir.mktmpdir('profile-private-with-tooling') do |dir|
      content_root(dir)
      (Pathname.new(dir) + 'metamodel').mkpath
      (Pathname.new(dir) + 'metamodel/profile-artifact.schema.yaml').write("type: object\n")

      # When: the private target is asked for
      _out, err, status = gradle('checkPrivateCheckout', private_dir: dir)

      # Then: the build stops and names the copy it found
      refute_predicate status, :success?
      assert_includes err, 'carries its own tooling'
      assert_includes err, 'metamodel'
    end
  end

  def test_an_absent_sibling_leaves_the_rest_of_the_build_alone
    # Given: no private checkout at the configured path
    missing = File.join(Dir.tmpdir, 'profile-private-absent-on-purpose')
    refute File.exist?(missing)

    # When: a task that has nothing to do with the private target runs
    _out, err, status = gradle('validateProfileMetamodel', private_dir: missing)

    # Then: it succeeds, because a checkout without the sibling is an ordinary
    # state of this repository rather than a broken one
    assert_predicate status, :success?, err
  end
end
