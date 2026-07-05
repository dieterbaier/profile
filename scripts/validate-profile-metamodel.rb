#!/usr/bin/env ruby
# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'optparse'
require 'pathname'
require 'set'
require 'yaml'

class ProfileArtifactValidator
  REQUIRED = %w[id type title status owner created].freeze
  PROPERTIES = %w[id type title status owner created updated reviewed generated language audience channels summary source tags relations metadata_version].freeze
  TYPES = %w[ProfilePage Article ShortThought CV Project ProfessionalExperience Education Skill Contact ProfileFragment].freeze
  STATUSES = %w[draft proposed reviewed published archived deprecated].freeze
  LANGUAGES = %w[de en mixed].freeze
  CHANNELS = %w[website cv readme github gitlab markdown-export pdf].freeze
  RELATION_TYPES = %w[addresses depends_on constrains refines supersedes conflicts_with mitigates introduces_risk affects verifies documents relates_to].freeze
  RELATION_STATUSES = %w[proposed reviewed accepted rejected].freeze
  RELATION_KEYS = %w[type target status rationale evidence reviewed].freeze
  ARTIFACT_ID_PATTERN = /\A[A-Z]+-[0-9]{3,}(-[a-z0-9]+)*\z/
  TAG_PATTERN = /\A[a-z0-9][a-z0-9-]*\z/

  Artifact = Struct.new(:path, :metadata, keyword_init: true)
  attr_reader :errors, :warnings, :root, :profile_dir

  def initialize(root:, profile_dir:)
    @root = Pathname.new(root).expand_path
    @profile_dir = Pathname.new(profile_dir).expand_path
    @errors = []
    @warnings = []
  end

  def validate
    artifacts = scan
    validate_fields(artifacts)
    validate_ids(artifacts)
    validate_relations(artifacts)
    artifacts
  end

  def generate(artifacts, output:)
    output_path = @root.join(output)
    FileUtils.mkdir_p(output_path.dirname)
    output_path.write(render_index(artifacts, output_path))
    output_path
  end

  def report(artifacts)
    puts 'Profile metamodel validation report'
    puts "Profile target: #{relative(profile_dir)}"
    puts "Artifacts scanned: #{artifacts.length}"
    puts "Errors: #{errors.length}"
    puts "Warnings: #{warnings.length}"
    unless errors.empty?
      puts "\nErrors:"
      errors.each { |error| puts "  - #{error}" }
    end
    unless warnings.empty?
      puts "\nWarnings:"
      warnings.each { |warning| puts "  - #{warning}" }
    end
    puts
    puts(errors.empty? ? 'Validation passed.' : 'Validation failed.')
  end

  private

  def scan
    paths = Dir.glob(profile_dir.join('**/*.{adoc,yaml,yml}').to_s).reject { |path| path.include?('/generated/') }.sort
      paths.map do |path|
        path = Pathname.new(path)
        metadata = if path.extname == '.adoc'
                     front_matter(path)
                   elsif path.basename.to_s.end_with?('.profile.yaml', '.profile.yml')
                     YAML.safe_load(path.read, permitted_classes: [Date], aliases: false)
                   end
        Artifact.new(path: path, metadata: stringify(metadata)) if metadata
      rescue Psych::SyntaxError => e
        errors << "#{relative(path)} has invalid YAML: #{e.message.lines.first.strip}"
        nil
      end.compact
  end

  def front_matter(path)
    text = path.read
    return nil unless text.start_with?("---\n")
    parts = text.split(/^---\s*$/, 3)
    return nil if parts.length < 3
    YAML.safe_load(parts[1], permitted_classes: [Date], aliases: false)
  end

  def stringify(value)
    return nil unless value.is_a?(Hash)
    value.transform_keys(&:to_s)
  end

  def validate_fields(artifacts)
    artifacts.each do |artifact|
      unknown_keys = artifact.metadata.keys - PROPERTIES
      errors << "#{relative(artifact.path)} has unknown field(s): #{unknown_keys.sort.join(', ')}" unless unknown_keys.empty?

      REQUIRED.each do |field|
        errors << "#{relative(artifact.path)} missing required field '#{field}'" if blank?(artifact.metadata[field])
      end

      validate_string(artifact, 'id', pattern: ARTIFACT_ID_PATTERN)
      validate_string(artifact, 'title')
      validate_string(artifact, 'owner')
      validate_string(artifact, 'summary', required: false)
      validate_string(artifact, 'source', required: false)
      validate_string(artifact, 'metadata_version', required: false)
      validate_enum(artifact, 'type', TYPES)
      validate_enum(artifact, 'status', STATUSES)
      validate_enum(artifact, 'language', LANGUAGES, required: false)
      validate_date(artifact, 'created')
      validate_date(artifact, 'updated', required: false)
      validate_boolean(artifact, 'reviewed')
      validate_boolean(artifact, 'generated')
      validate_string_array(artifact, 'audience')
      validate_string_array(artifact, 'channels', allowed: CHANNELS)
      validate_tags(artifact)
      validate_relations_field(artifact)

      if artifact.metadata['source']
        source = root.join(artifact.metadata['source'])
        errors << "#{relative(artifact.path)} source does not exist: #{artifact.metadata['source']}" unless source.exist?
      end
    end
  end

  def validate_ids(artifacts)
    by_id = artifacts.group_by { |artifact| artifact.metadata['id'] }
    by_id.each do |id, matches|
      next if blank?(id) || matches.length == 1
      errors << "duplicate profile artifact id '#{id}' in #{matches.map { |m| relative(m.path) }.join(', ')}"
    end
  end

  def validate_relations(artifacts)
    known = artifacts.map { |artifact| artifact.metadata['id'] }.compact.to_set
    artifacts.each do |artifact|
      Array(artifact.metadata['relations']).each_with_index do |relation, index|
        location = "#{relative(artifact.path)} relation ##{index + 1}"
        unless relation.is_a?(Hash)
          errors << "#{location} must be a mapping"
          next
        end
        type = relation['type']
        target = relation['target']
        unknown_keys = relation.keys - RELATION_KEYS
        errors << "#{location} has unknown key(s): #{unknown_keys.sort.join(', ')}" unless unknown_keys.empty?
        errors << "#{location} missing type" if blank?(type)
        errors << "#{location} missing target" if blank?(target)
        errors << "#{location} missing status" if blank?(relation['status'])
        errors << "#{location} unknown type '#{type}'" if type && !RELATION_TYPES.include?(type)
        errors << "#{location} unknown status '#{relation['status']}'" if relation['status'] && !RELATION_STATUSES.include?(relation['status'])
        errors << "#{location} target must match #{ARTIFACT_ID_PATTERN.inspect}" if target && target !~ ARTIFACT_ID_PATTERN
        errors << "#{location} rationale must be a string" if relation.key?('rationale') && !relation['rationale'].is_a?(String)
        errors << "#{location} evidence must be a string" if relation.key?('evidence') && !relation['evidence'].is_a?(String)
        errors << "#{location} reviewed must be true or false" if relation.key?('reviewed') && !boolean?(relation['reviewed'])
        warnings << "#{location} references external artifact '#{target}'" if target && !known.include?(target)
      end
    end
  end

  def validate_string(artifact, field, pattern: nil, required: true)
    value = artifact.metadata[field]
    return if !required && value.nil?

    unless value.is_a?(String) && !value.empty?
      errors << "#{relative(artifact.path)} field '#{field}' must be a non-empty string"
      return
    end

    errors << "#{relative(artifact.path)} field '#{field}' must match #{pattern.inspect}" if pattern && value !~ pattern
  end

  def validate_enum(artifact, field, allowed, required: true)
    value = artifact.metadata[field]
    return if !required && value.nil?

    errors << "#{relative(artifact.path)} unknown #{field} '#{value}'" unless allowed.include?(value)
  end

  def validate_date(artifact, field, required: true)
    value = artifact.metadata[field]
    return if !required && value.nil?

    if value.is_a?(Date)
      return
    elsif value.is_a?(String)
      begin
        parsed = Date.iso8601(value)
        return if parsed.to_s == value
      rescue Date::Error
        # handled below
      end
    end

    errors << "#{relative(artifact.path)} field '#{field}' must be an ISO-8601 date"
  end

  def validate_boolean(artifact, field)
    value = artifact.metadata[field]
    return if value.nil?

    errors << "#{relative(artifact.path)} field '#{field}' must be true or false" unless boolean?(value)
  end

  def validate_string_array(artifact, field, allowed: nil)
    value = artifact.metadata[field]
    return if value.nil?

    unless value.is_a?(Array)
      errors << "#{relative(artifact.path)} field '#{field}' must be an array"
      return
    end

    value.each_with_index do |item, index|
      unless item.is_a?(String)
        errors << "#{relative(artifact.path)} field '#{field}' item ##{index + 1} must be a string"
        next
      end
      errors << "#{relative(artifact.path)} field '#{field}' item ##{index + 1} unknown value '#{item}'" if allowed && !allowed.include?(item)
    end
  end

  def validate_tags(artifact)
    tags = artifact.metadata['tags']
    return if tags.nil?

    unless tags.is_a?(Array)
      errors << "#{relative(artifact.path)} field 'tags' must be an array"
      return
    end

    duplicates = tags.group_by(&:itself).select { |_tag, matches| matches.length > 1 }.keys
    errors << "#{relative(artifact.path)} field 'tags' contains duplicate value(s): #{duplicates.join(', ')}" unless duplicates.empty?

    tags.each_with_index do |tag, index|
      unless tag.is_a?(String) && tag =~ TAG_PATTERN
        errors << "#{relative(artifact.path)} field 'tags' item ##{index + 1} must match #{TAG_PATTERN.inspect}"
      end
    end
  end

  def validate_relations_field(artifact)
    relations = artifact.metadata['relations']
    return if relations.nil? || relations.is_a?(Array)

    errors << "#{relative(artifact.path)} field 'relations' must be an array"
  end

  def boolean?(value)
    value == true || value == false
  end

  def render_index(artifacts, output_path)
    lines = []
    lines << '[[profile-artifact-index]]'
    lines << '= Profile Artifact Index'
    lines << ''
    lines << '// Generated from profile artifact metadata. Do not edit manually.'
    lines << ''
    lines << '[cols="1,1,2,1,2,2", options="header"]'
    lines << '|==='
    lines << '| ID | Type | Title | Status | Channels | Source'
    artifacts.sort_by { |artifact| artifact.metadata['id'].to_s }.each do |artifact|
      metadata = artifact.metadata
      source = metadata['source'] || relative(artifact.path)
      lines << "| #{cell(metadata['id'])}"
      lines << "| #{cell(metadata['type'])}"
      lines << "| #{cell(metadata['title'])}"
      lines << "| #{cell(metadata['status'])}"
      lines << "| #{cell(Array(metadata['channels']).join(', '))}"
      lines << "| `#{cell(source)}`"
    end
    lines << '|==='
    lines << ''
    lines.join("\n")
  end

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end

  def cell(value)
    value.to_s.gsub('|', '\|').gsub("\n", ' ')
  end

  def relative(path)
    Pathname.new(path).expand_path.relative_path_from(root).to_s
  rescue ArgumentError
    path.to_s
  end
end

if $PROGRAM_NAME == __FILE__
  root = Pathname.new(__dir__).join('..').expand_path
  options = {
    profile_dir: root.join('src-content/profile'),
    generate: false,
    output: 'src-content/profile/generated/profile-artifact-index.adoc'
  }
  OptionParser.new do |parser|
    parser.on('--profile-dir PATH') { |value| options[:profile_dir] = Pathname.new(value) }
    parser.on('--generate') { options[:generate] = true }
    parser.on('--output PATH') { |value| options[:output] = value }
  end.parse!

  validator = ProfileArtifactValidator.new(root: root, profile_dir: options[:profile_dir])
  artifacts = validator.validate
  validator.report(artifacts)
  exit(1) unless validator.errors.empty?
  if options[:generate]
    path = validator.generate(artifacts, output: options[:output])
    puts "Generated: #{path.relative_path_from(root)}"
  end
end
