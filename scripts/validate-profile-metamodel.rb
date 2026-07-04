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
  TYPES = %w[ProfilePage Article ShortThought CV Project ProfessionalExperience Education Skill Contact ProfileFragment].freeze
  STATUSES = %w[draft proposed reviewed published archived deprecated].freeze
  RELATION_TYPES = %w[addresses depends_on constrains refines supersedes conflicts_with mitigates introduces_risk affects verifies documents relates_to].freeze

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
      REQUIRED.each do |field|
        errors << "#{relative(artifact.path)} missing required field '#{field}'" if blank?(artifact.metadata[field])
      end
      errors << "#{relative(artifact.path)} unknown type '#{artifact.metadata['type']}'" if artifact.metadata['type'] && !TYPES.include?(artifact.metadata['type'])
      errors << "#{relative(artifact.path)} unknown status '#{artifact.metadata['status']}'" if artifact.metadata['status'] && !STATUSES.include?(artifact.metadata['status'])
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
        errors << "#{location} missing type" if blank?(type)
        errors << "#{location} missing target" if blank?(target)
        errors << "#{location} missing status" if blank?(relation['status'])
        errors << "#{location} unknown type '#{type}'" if type && !RELATION_TYPES.include?(type)
        warnings << "#{location} references external artifact '#{target}'" if target && !known.include?(target)
      end
    end
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
