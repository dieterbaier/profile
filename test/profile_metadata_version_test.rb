# frozen_string_literal: true

# Behaviour specification bridge for the metadata contract version.
#
# Minitest is a classic (non-BDD) runner, so each test method name is a
# sanitized translation of a scenario title in
# features/metadata-contract-version.feature, with Given/When/Then comment
# anchors separating Arrange, Act, and Assert. Each test builds an isolated
# temporary profile tree so the real repository is never touched.

require 'minitest/autorun'
require 'tmpdir'
require 'pathname'
require 'yaml'

require_relative '../scripts/validate-profile-metamodel'

class ProfileMetadataVersionTest < Minitest::Test
  # A version this checkout accepts, taken from the schema rather than restated,
  # so raising the contract does not silently strand these tests on an old value.
  def accepted_version
    ProfileArtifactValidator.supported_metadata_versions.first
  end

  def with_artifact(spec)
    Dir.mktmpdir('profile-metadata-version-test') do |dir|
      root = Pathname.new(dir)
      (root + 'articles').mkpath
      (root + 'articles/sample.adoc').write("= Sample\n")
      (root + 'articles/sample.profile.yaml').write(metadata_yaml(spec))

      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      artifacts = validator.validate
      yield(validator, artifacts, root)
    end
  end

  def metadata_yaml(spec)
    metadata = {
      'id' => 'ART-901-sample',
      'type' => 'Article',
      'title' => 'Sample',
      'status' => 'draft',
      'owner' => 'Test Owner',
      'created' => '2026-01-01',
      'source' => 'articles/sample.adoc'
    }
    metadata['metadata_version'] = spec[:metadata_version] unless spec[:omit_metadata_version]
    metadata.to_yaml
  end

  # Writes a schema whose metadata_version field lists the given versions. `nil`
  # writes the field without an enum, which is a schema that cannot answer.
  def write_schema(path, versions)
    field = versions.nil? ? { 'type' => 'string' } : { 'type' => 'string', 'enum' => versions }
    path.dirname.mkpath
    path.write({ 'type' => 'object', 'properties' => { 'metadata_version' => field } }.to_yaml)
    path
  end

  def contract_errors(validator)
    validator.errors.grep(/metadata_version/)
  end

  def test_an_artifact_declaring_an_accepted_contract_version_passes_validation
    # Given: an artifact declaring a contract version this checkout accepts
    with_artifact(metadata_version: accepted_version) do |validator, _artifacts, _root|
      # When: the profile metadata is validated (in with_artifact)
      # Then: validation reports no error about the contract version
      assert_empty contract_errors(validator)
    end
  end

  def test_an_artifact_declaring_an_unsupported_contract_version_is_rejected_by_name
    # Given: an artifact declaring a contract version this checkout does not accept
    unsupported = '0.9'
    refute_includes ProfileArtifactValidator.supported_metadata_versions, unsupported

    with_artifact(metadata_version: unsupported) do |validator, _artifacts, _root|
      # When: the profile metadata is validated (in with_artifact)
      # Then: validation fails naming the artifact, the declared version, and the
      # accepted versions
      errors = contract_errors(validator)
      assert_equal 1, errors.length
      error = errors.first
      assert_includes error, 'articles/sample.profile.yaml'
      assert_includes error, "'#{unsupported}'"
      ProfileArtifactValidator.supported_metadata_versions.each do |version|
        assert_includes error, version
      end
    end
  end

  def test_an_artifact_that_declares_no_contract_version_fails_validation
    # Given: an artifact with no contract version at all
    with_artifact(omit_metadata_version: true) do |validator, _artifacts, _root|
      # When: the profile metadata is validated (in with_artifact)
      # Then: validation fails naming the artifact and the missing field
      errors = contract_errors(validator)
      refute_empty errors
      assert(errors.any? { |error| error.include?('articles/sample.profile.yaml') && error.include?('missing required field') })
    end
  end

  def test_the_accepted_versions_come_from_the_metamodel_schema
    # Given: a metamodel schema listing the contract versions it accepts
    Dir.mktmpdir('profile-metadata-schema-test') do |dir|
      schema = write_schema(Pathname.new(dir) + 'profile-artifact.schema.yaml', %w[1.0 2.0])

      # When: the accepted versions are read
      versions = ProfileArtifactValidator.supported_metadata_versions(schema)

      # Then: they are the versions the schema lists
      assert_equal %w[1.0 2.0], versions
    end
  end

  def test_a_schema_that_names_no_accepted_versions_stops_the_validator
    # Given: a metamodel schema whose contract version field lists no versions
    Dir.mktmpdir('profile-metadata-schema-test') do |dir|
      schema = write_schema(Pathname.new(dir) + 'profile-artifact.schema.yaml', nil)

      # When: the accepted versions are read
      error = assert_raises(ProfileArtifactValidator::UnreadableMetadataContract) do
        ProfileArtifactValidator.supported_metadata_versions(schema)
      end

      # Then: reading fails naming the schema instead of assuming a version
      assert_includes error.message, schema.to_s
      assert_includes error.message, 'metadata_version'
    end
  end

  def test_content_is_judged_by_the_contract_of_the_checkout_validating_it
    # Given: content whose own metamodel accepts a version this checkout does not
    unsupported = '0.9'
    refute_includes ProfileArtifactValidator.supported_metadata_versions, unsupported

    with_artifact(metadata_version: unsupported) do |validator, _artifacts, root|
      write_schema(root + 'metamodel/profile-artifact.schema.yaml', [unsupported])

      # When: the profile metadata is validated
      validator = ProfileArtifactValidator.new(root: root, profile_dir: root)
      validator.validate

      # Then: the declared version is rejected against this checkout's accepted
      # versions, not against the metamodel sitting beside the content
      errors = contract_errors(validator)
      assert_equal 1, errors.length
      assert_includes errors.first, ProfileArtifactValidator.supported_metadata_versions.join(', ')
    end
  end
end
