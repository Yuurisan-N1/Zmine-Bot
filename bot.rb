require "json"
require "fileutils"
require "net/http"
require "uri"
require "async"
require "async/http/internet"
require "faker"
require_relative "utils/banner"

RESET = "\033[0m"
BOLD = "\033[1m"
RED = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"

MY_PROJECT = "Zmine Referral"
BASE_URL = "https://zmine.si/api/v1"
ACCOUNT_DIR = "account"

def log_green(msg)
  puts "#{GREEN}#{BOLD}#{msg}#{RESET}"
  $stdout.flush
end

def log_yellow(msg)
  puts "#{YELLOW}#{BOLD}#{msg}#{RESET}"
  $stdout.flush
end

def log_red(msg)
  puts "#{RED}#{BOLD}#{msg}#{RESET}"
  $stdout.flush
end

Signal.trap("INT") do
  puts
  log_red("Script stopped by user")
  exit(0)
end

def ensure_dirs
  FileUtils.mkdir_p(ACCOUNT_DIR)
end

def load_config
  defaults = { "settings" => { "sleep_seconds" => 3600 } }
  return defaults unless File.exist?("config.json")

  begin
    loaded = JSON.parse(File.read("config.json"))
  rescue
    return defaults
  end

  settings = loaded["settings"]
  return defaults unless settings.is_a?(Hash)

  merged = defaults["settings"].merge(settings)
  { "settings" => merged }
end

def load_lines(filename)
  return [] unless File.exist?(filename)
  File.readlines(filename).map(&:strip).reject(&:empty?)
end

def normalize_proxy(proxy_line)
  return nil if proxy_line.nil? || proxy_line.strip.empty?

  value = proxy_line.strip
  return value if value.include?("://")

  parts = value.split(":")
  if parts.length == 4
    host, port, user, password = parts
    return "http://#{user}:#{password}@#{host}:#{port}"
  end
  if parts.length == 3
    host, port, user = parts
    return "http://#{user}@#{host}:#{port}"
  end
  "http://#{value}"
end

def mask_proxy(proxy_url)
  begin
    value = proxy_url.split("://").last
    after_at = value.split("@").last
    host_part = after_at.split(":").first
    port_part = after_at.include?(":") ? after_at.split(":")[1] : ""
    octets = host_part.split(".")
    masked_host = if octets.length == 4
      "#{octets[0]}*****#{octets[3]}"
    elsif host_part.length > 4
      "#{host_part[0..1]}*****#{host_part[-2..]}"
    else
      "***"
    end
    suffix = port_part.empty? ? "" : ":#{port_part}"
    "http://user:pass@#{masked_host}#{suffix}"
  rescue
    "http://user:pass@***:***"
  end
end

def countdown(seconds, label)
  seconds.downto(1) do |remaining|
    h = remaining / 3600
    m = (remaining % 3600) / 60
    s = remaining % 60
    print "\r#{YELLOW}#{BOLD}#{label} #{format("%02d:%02d:%02d", h, m, s)}#{RESET}"
    $stdout.flush
    sleep(1)
  end
  puts
  $stdout.flush
end

def random_display_name
  style = rand(1..4)
  case style
  when 1
    Faker::Name.first_name + Faker::Name.last_name
  when 2
    Faker::Internet.username
  when 3
    Faker::Name.first_name + rand(10..9999).to_s
  else
    Faker::Name.last_name + Faker::Name.first_name
  end
end

USER_AGENT_POOL = begin
  os_list = [
    "Windows NT 10.0; Win64; x64",
    "Windows NT 11.0; Win64; x64",
    "Macintosh; Intel Mac OS X 10_15_7",
    "Macintosh; Intel Mac OS X 13_0",
    "Macintosh; Intel Mac OS X 14_0",
    "X11; Linux x86_64",
    "X11; Ubuntu; Linux x86_64",
  ]
  chrome_versions = (120..155).to_a
  webkit = "537.36"

  os_list.flat_map do |os|
    chrome_versions.sample(5).map do |v|
      "Mozilla/5.0 (#{os}) AppleWebKit/#{webkit} (KHTML, like Gecko) Chrome/#{v}.0.0.0 Safari/#{webkit}"
    end
  end.shuffle
end

def random_user_agent
  USER_AGENT_POOL.sample
end

def save_results(results)
  File.open("#{ACCOUNT_DIR}/loginKey.txt", "a") do |f|
    results.each do |r|
      f.puts(r["loginKey"]) if r && r["loginKey"]
    end
  end

  File.open("#{ACCOUNT_DIR}/recoveryPhrase.txt", "a") do |f|
    results.each do |r|
      f.puts(r["recoveryPhrase"]) if r && r["recoveryPhrase"]
    end
  end

  existing = []
  if File.exist?("#{ACCOUNT_DIR}/account.json")
    begin
      existing = JSON.parse(File.read("#{ACCOUNT_DIR}/account.json"))
    rescue
      existing = []
    end
  end

  results.each do |r|
    next unless r
    existing << {
      "displayName" => r["displayName"],
      "loginKey" => r["loginKey"],
      "recoveryPhrase" => r["recoveryPhrase"],
      "userAgent" => r["userAgent"],
    }
  end

  File.write("#{ACCOUNT_DIR}/account.json", JSON.pretty_generate(existing))
end

def register_account(display_name, referral_code, user_agent, proxy_url)
  url = URI("#{BASE_URL}/auth/register")

  if proxy_url
    proxy_uri = URI(proxy_url)
    http = Net::HTTP.new(url.host, url.port, proxy_uri.host, proxy_uri.port, proxy_uri.user, proxy_uri.password)
  else
    http = Net::HTTP.new(url.host, url.port)
  end

  http.use_ssl = url.scheme == "https"
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Post.new(url.path)
  request["accept"] = "*/*"
  request["accept-language"] = "en-JP,en;q=0.9,ja-JP;q=0.8,ja;q=0.7,id-ID;q=0.6,id;q=0.5,en-GB;q=0.4,en-US;q=0.3"
  request["cache-control"] = "no-cache"
  request["content-type"] = "application/json"
  request["origin"] = "https://zmine.si"
  request["pragma"] = "no-cache"
  request["priority"] = "u=1, i"
  request["referer"] = "https://zmine.si/register?ref=#{referral_code}"
  request["sec-ch-ua"] = '"Google Chrome";v="155", "Chromium";v="155", "Not(A:Brand";v="24"'
  request["sec-ch-ua-mobile"] = "?0"
  request["sec-ch-ua-platform"] = '"Windows"'
  request["sec-fetch-dest"] = "empty"
  request["sec-fetch-mode"] = "cors"
  request["sec-fetch-site"] = "same-origin"
  request["user-agent"] = user_agent

  payload = { "displayName" => display_name, "referralCode" => referral_code }
  request.body = JSON.generate(payload)

  response = http.request(request)
  JSON.parse(response.body)
end

def process_account(idx, total, proxy_url, referral_code)
  display_name = random_display_name
  user_agent = random_user_agent

  log_green("Registering account #{idx} of #{total} now")
  log_green("Generated display name is #{display_name}")

  begin
    data = register_account(display_name, referral_code, user_agent, proxy_url)

    unless data.is_a?(Hash) && data["loginKey"]
      log_red("Registration failed for account #{idx} unexpectedly")
      return nil
    end

    user = data["user"] || {}
    login_key = data["loginKey"] || ""
    recovery_phrase = data["recoveryPhrase"] || ""
    handle = user["handle"] || ""

    log_green("Registration successful for account #{idx} completed")
    log_green("Account handle assigned is #{handle}")
    log_green("Login key saved for account #{idx} successfully")

    {
      "displayName" => display_name,
      "loginKey" => login_key,
      "recoveryPhrase" => recovery_phrase,
      "userAgent" => user_agent,
    }
  rescue => e
    log_red("An error occurred while registering account #{idx}")
    nil
  end
end

def main_loop(referral_code, total, proxies, sleep_secs)
  cycle = 1
  loop do
    log_green("Starting registration cycle number #{cycle}")

    results = []
    (1..total).each do |idx|
      puts if idx > 1

      proxy_line = proxies.empty? ? nil : proxies[(idx - 1) % proxies.length]
      proxy_url = proxy_line ? normalize_proxy(proxy_line) : nil

      log_yellow("Using proxy #{mask_proxy(proxy_url)}") if proxy_url

      result = process_account(idx, total, proxy_url, referral_code)
      results << result
    end

    save_results(results)
    log_green("All accounts for cycle #{cycle} were saved successfully")

    cycle += 1
    countdown(sleep_secs, "Next cycle starts in")
    show_banner(MY_PROJECT)
  end
end

def main
  $stdout.sync = true
  $stderr.sync = true

  show_banner(MY_PROJECT)
  ensure_dirs

  settings = load_config["settings"]
  proxies = load_lines("proxy.txt")

  print "#{YELLOW}#{BOLD}Enter referral code: #{RESET}"
  referral_code = $stdin.gets.strip

  print "#{YELLOW}#{BOLD}Enter number of registrations: #{RESET}"
  count_input = $stdin.gets.strip

  unless referral_code && !referral_code.empty? && count_input.match?(/^\d+$/)
    log_red("Invalid input provided please try again")
    exit(1)
  end

  total = count_input.to_i
  main_loop(referral_code, total, proxies, settings["sleep_seconds"])
end

main