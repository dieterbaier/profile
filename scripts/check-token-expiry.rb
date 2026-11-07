#!/usr/bin/env ruby
# frozen_string_literal: true

# Fails when a GitHub token is rejected or expires soon, so that it can be
# renewed before a deployment depends on it. GitHub reports the expiry date of a
# token in a response header; a token without an expiry date has no such header.

require 'net/http'
require 'time'
require 'uri'

module TokenExpiry
  HEADER = 'github-authentication-token-expiration'
  WARNING_DAYS = 14
  SECONDS_PER_DAY = 86_400

  Verdict = Struct.new(:ok, :message)

  def self.verdict(status:, expiry:, now: Time.now)
    return Verdict.new(false, "token rejected (HTTP #{status})") unless status == 200
    return Verdict.new(true, 'token valid, no expiry date reported') if expiry.nil?

    expires_at = Time.parse(expiry)
    days = ((expires_at - now) / SECONDS_PER_DAY).floor
    message = "token expires on #{expires_at.utc.strftime('%F')}, in #{days} days"
    Verdict.new(days >= WARNING_DAYS, message)
  end

  def self.fetch(repository, token)
    uri = URI("https://api.github.com/repos/#{repository}")
    request = Net::HTTP::Head.new(uri)
    request['Authorization'] = "Bearer #{token}"
    request['User-Agent'] = 'profile-credential-check'
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    { status: response.code.to_i, expiry: response[HEADER] }
  end
end

if $PROGRAM_NAME == __FILE__
  result = TokenExpiry.verdict(**TokenExpiry.fetch(ARGV.fetch(0), ENV.fetch('CHECK_TOKEN')))
  puts result.message
  exit(result.ok ? 0 : 1)
end
