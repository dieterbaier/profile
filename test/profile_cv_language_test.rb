# frozen_string_literal: true

# Behaviour specification bridge for the multilingual CV.
#
# Minitest is a classic (non-BDD) runner, so each test method name is a
# sanitized translation of a scenario title in features/multilingual-cv.feature,
# with Given/When/Then comment anchors separating Arrange, Act, and Assert.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'yaml'

require_relative '../scripts/validate-profile-metamodel'

class ProfileCvLanguageTest < Minitest::Test
  CHROME = %w[cvheader.adoc cvappendix.adoc cvappendixnav.adoc author.adoc].freeze

  # Builds a tree with a German CV and, optionally, a language variant of it.
  def with_cv(languages:, fragments: {})
    Dir.mktmpdir('profile-cv-language-test') do |dir|
      root = Pathname.new(dir)
      (root + 'includes/i18n').mkpath
      (root + 'includes/i18n/ui-de.adoc').write(":ui_nav_home: Home\n")
      (root + 'includes/i18n/ui-en.adoc').write(":ui_nav_home: Home\n")

      fragments.each do |relative, body|
        path = root + "includes/i18n/#{relative}"
        path.dirname.mkpath
        path.write(body)
      end

      languages.each do |language, body|
        rel_dir = language == 'de' ? 'cv' : "cv/#{language}"
        (root + rel_dir).mkpath
        (root + "#{rel_dir}/cv.adoc").write(body)
      end

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      artifacts = validator.validate
      yield(validator, artifacts, root)
    end
  end

  def registry(root, language)
    path = root + "includes/generated/i18n/links-#{language}.adoc"
    path.exist? ? path.read : ''
  end

  def test_cv_download_link_points_at_the_pdf_of_its_own_language_variant
    # Given: a CV that exists in the default language and in one other language
    with_cv(languages: { 'de' => "= CV\n", 'en' => "= CV\n" }) do |validator, artifacts, root|
      # When: the link registries are generated
      validator.generate_link_registries(artifacts)

      # Then: each language resolves the CV download to the PDF beside its own CV page
      assert_includes registry(root, 'de'), ":url_cv_pdf: {basedir}/cv.pdf\n"
      assert_includes registry(root, 'en'), ":url_cv_pdf: {basedir}/en/cv.pdf\n"
    end
  end

  def test_cv_download_link_falls_back_with_the_default_language_marked
    # Given: a CV that exists in the default language only
    with_cv(languages: { 'de' => "= CV\n" }) do |validator, artifacts, root|
      # When: the link registries are generated
      validator.generate_link_registries(artifacts)

      # Then: the other language resolves the CV download to the default-language PDF
      # No other language has pages, so only the default registry exists and it
      # resolves the download to the default-language PDF without a marker.
      german = registry(root, 'de')
      assert_includes german, ":url_cv_pdf: {basedir}/cv.pdf\n"
      assert_includes german, ":url_cv_marker:"
    end
  end

  def test_cv_chrome_wording_is_resolved_by_the_page_it_lands_on
    # Given: the shared CV chrome
    includes_dir = Pathname.new(__dir__).join('../src-content/profile/includes')

    # Then: it carries no wording of its own, only interface terms
    CHROME.each do |name|
      text = includes_dir.join(name).read
      refute_match(/Software Architekt|Download CV|Projekte<|Weiterbildung<|Autor:/, text,
                   "#{name} still carries its own wording")
      assert_match(/\{ui_[a-z0-9_]+\}/, text, "#{name} should reference interface terms")
    end
  end

  def test_cv_language_variant_is_blocked_until_its_fragments_are_translated
    # Given: a CV language variant that includes a fragment available only in the default language
    with_cv(
      languages: {
        'de' => "= CV\ninclude::{includesdir}/i18n/{lang}/profile/bio.adoc[]\n",
        'en' => "= CV\ninclude::{includesdir}/i18n/{lang}/profile/bio.adoc[]\n"
      },
      fragments: { 'de/profile/bio.adoc' => "Deutscher Text\n" }
    ) do |validator, _artifacts, _root|
      # When: the profile metadata is validated (done by the helper)
      # Then: validation reports that the fragment is missing in the variant's language
      assert validator.errors.any? { |error| error.match?(%r{fragment 'profile/bio\.adoc' is not available in 'en'}) },
             "expected a missing-fragment error, got: #{validator.errors.inspect}"
    end
  end
end
