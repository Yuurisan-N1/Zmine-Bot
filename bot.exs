Code.require_file("utils/json.ex", __DIR__)
Code.require_file("utils/banner.ex", __DIR__)

defmodule ZMine do
  @moduledoc false

  @my_project "ZMine Mining"
  @base_url "https://zmine.si/api/v1"

  @reset "\e[0m"
  @bold "\e[1m"
  @red "\e[31m"
  @green "\e[32m"
  @yellow "\e[33m"

  def run do
    :logger.set_primary_config(:level, :error)
    install_signal_handler()
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
    Banner.set_title(@my_project)
    Banner.show_banner(@my_project)

    keys = load_lines("data.txt")

    if keys == [] do
      red("File data.txt is empty, so no account could be started")
      System.halt(1)
    end

    proxies = load_lines("proxy.txt")
    settings = load_settings()
    green("The account file was loaded with #{plural(length(keys), "login key")}")
    loop(keys, proxies, settings, 1)
  end

  defp loop(keys, proxies, settings, cycle) do
    yellow("Starting automation cycle number #{cycle}")

    keys
    |> Enum.with_index()
    |> Enum.each(fn {key, index} ->
      if index > 0, do: IO.puts("")
      {device, proxy} = device_session(key, proxies, index)

      case proxy do
        nil -> :ok
        line -> yellow("Using proxy #{mask_proxy(line)}")
      end

      try do
        process_account(key, index, device, proxy)
      rescue
        _error -> red("Account #{index + 1} was skipped after an unexpected error")
      end
    end)

    yellow("All accounts were processed for cycle number #{cycle}")
    countdown(sleep_seconds(settings), "Next cycle starts in")
    Banner.show_banner(@my_project)
    loop(keys, proxies, settings, cycle + 1)
  end

  defp process_account(key, index, device, proxy) do
    label = Integer.to_string(index + 1)

    case login(key, device, proxy) do
      {:ok, cookie, user} ->
        green("Welcome back #{display_name(user)} on account number #{label}")
        ctx = %{label: label, key: key, cookie: cookie, proxy: proxy, user: user, device: device}
        open_account(ctx)

      {:error, _reason} ->
        red("Account #{label} could not log in with the given key")
    end
  end

  defp open_account(ctx) do
    case api(ctx, :get, "mining/overview", nil) do
      {:ok, data, ctx} ->
        miner = get(data, "miner", %{})
        power = get(data, "hashpower", %{})
        mined = get(miner, "totalMined", "0")
        streak = get(miner, "streakDays", 0)
        sessions = get(miner, "activations", 0)
        total = get(power, "totalMh", "0")

        green("Account #{ctx.label} mined #{mined} MINE with #{total} MH of hashpower")
        green("Mining streak for account #{ctx.label} reached #{plural(streak, "day")} in #{plural(sessions, "session")}")
        ctx = activate(ctx, data)
        si_loop(ctx, 0, 0)

      {:error, _reason} ->
        red("Mining overview for account #{ctx.label} could not be loaded this time")
    end
  end

  defp activate(ctx, data) do
    if get(data, "sessionActive", false) do
      yellow("Mining session for account #{ctx.label} is already running right now")
      ctx
    else
      case api(ctx, :post, "mining/activate", %{}) do
        {:ok, _body, ctx} ->
          green("Mining session for account #{ctx.label} was started for the next day")
          ctx

        {:error, _reason} ->
          yellow("Mining session for account #{ctx.label} was not started by the server")
          ctx
      end
    end
  end

  defp si_loop(ctx, credited, idle) do
    case api(ctx, :get, "si/tasks/next", nil) do
      {:ok, data, ctx} ->
        task = get(data, "task", nil)
        stats = get(data, "stats", %{})

        if is_map(task) do
          si_answer(ctx, task, stats, credited, idle)
        else
          si_idle(ctx, stats, credited, idle)
        end

      {:error, _reason} ->
        red("Question rail for account #{ctx.label} could not be reached this time")
        wallet(ctx, credited)
    end
  end

  defp si_idle(ctx, stats, credited, idle) do
    remaining = number(get(stats, "remainingToday", 0))
    cooldown = div(number(get(stats, "cooldownLeftMs", 0)), 1000)

    cond do
      remaining <= 0 ->
        yellow("Account #{ctx.label} answered every question, the cap is reached")
        wallet(ctx, credited)

      cooldown >= 300 ->
        yellow("Account #{ctx.label} has a long question cooldown, the next cycle waits")
        wallet(ctx, credited)

      idle >= 4 ->
        yellow("Account #{ctx.label} left the question rail idle, the next cycle waits")
        wallet(ctx, credited)

      cooldown >= 1 ->
        countdown(cooldown, "Next question in")
        si_loop(ctx, credited, idle + 1)

      true ->
        countdown(3, "Next question in")
        si_loop(ctx, credited, idle + 1)
    end
  end

  defp si_answer(ctx, task, stats, credited, idle) do
    prompt = get(task, "prompt", "")
    options = get(task, "options", [])
    token = get(task, "token", nil)

    case solve(prompt, options) do
      nil ->
        yellow("Question for account #{ctx.label} was skipped, the answer is unknown")
        si_loop(ctx, credited, idle + 1)

      index ->
        countdown(5, "Next answer submit in")

        case api(ctx, :post, "si/tasks/answer", %{"token" => token, "answer" => index}) do
          {:ok, body, ctx} ->
            si_result(ctx, body, stats, credited, idle)

          {:error, _reason} ->
            yellow("Answer for account #{ctx.label} was not accepted by the question rail")
            si_loop(ctx, credited, idle + 1)
        end
    end
  end

  defp si_result(ctx, body, stats, credited, idle) do
    correct = get(body, "correct", false)
    fast = get(body, "tooFast", false)
    mh = get(body, "creditedMh", "0")
    fresh = get(body, "stats", stats)
    remaining = number(get(fresh, "remainingToday", 0))

    cond do
      fast ->
        yellow("Account #{ctx.label} sent the answer too fast, so the question repeats")
        countdown(5, "Next answer submit in")
        si_loop(ctx, credited, idle + 1)

      correct and remaining <= 0 ->
        green("Answer for account #{ctx.label} was correct and #{mh} MH was credited")
        si_idle(ctx, fresh, credited + 1, idle)

      correct ->
        green("Answer for account #{ctx.label} was correct and #{mh} MH was credited")
        si_loop(ctx, credited + 1, 0)

      remaining <= 0 ->
        yellow("Answer for account #{ctx.label} was wrong, so no hashpower was credited")
        si_idle(ctx, fresh, credited, idle)

      true ->
        yellow("Answer for account #{ctx.label} was wrong, so no hashpower was credited")
        si_loop(ctx, credited, 0)
    end
  end

  defp wallet(ctx, credited) do
    green("Account #{ctx.label} collected #{plural(credited, "credited answer")} on this run")

    case api(ctx, :get, "wallet/balances", nil) do
      {:ok, data, ctx} ->
        mine = get(get(data, "MINE", %{}), "available", "0")
        zec = get(get(data, "ZEC", %{}), "available", "0")
        green("Wallet for account #{ctx.label} holds #{mine} MINE and #{zec} ZEC")
        advisor(ctx)

      {:error, _reason} ->
        red("Wallet for account #{ctx.label} could not be loaded this time")
        advisor(ctx)
    end
  end

  defp advisor(ctx) do
    case api(ctx, :get, "si/advisor", nil) do
      {:ok, data, _ctx} ->
        actions = get(get(data, "advice", %{}), "recommendations", [])
        yellow("Advisor listed #{plural(length(actions), "action")} for account #{ctx.label} to review")
        yellow("Boost and stake ideas were left alone to keep the balance safe")

      {:error, _reason} ->
        red("Advisor report for account #{ctx.label} could not be loaded this time")
    end
  end

  defp login(key, device, proxy) do
    headers = device_headers(device)

    body = YuurisanJSON.encode(%{"loginKey" => key})

    case send_request(:post, "#{@base_url}/auth/login", headers, body, nil, proxy) do
      {:ok, _status, response_headers, response_body} ->
        case cookie_from(response_headers) do
          nil -> {:error, :no_session_cookie}
          cookie -> {:ok, cookie, get(decode_body(response_body), "user", %{})}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp api(ctx, method, path, payload) do
    headers = request_headers(ctx.device, ctx.cookie)
    body = if payload == nil, do: nil, else: YuurisanJSON.encode(payload)

    case send_request(method, "#{@base_url}/#{path}", headers, body, nil, ctx.proxy) do
      {:ok, status, _response_headers, response_body} when status >= 200 and status < 300 ->
        {:ok, decode_body(response_body), ctx}

      {:ok, status, _response_headers, response_body} when status in [401, 403] ->
        renew_session(ctx, method, path, payload, response_body)

      {:ok, _status, _response_headers, response_body} ->
        {:error, error_code(response_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp renew_session(ctx, method, path, payload, _response_body) do
    case login(ctx.key, ctx.device, ctx.proxy) do
      {:ok, cookie, _user} ->
        yellow("Session for account #{ctx.label} was renewed because the cookie expired")
        ctx = %{ctx | cookie: cookie}
        headers = request_headers(ctx.device, cookie)
        body = if payload == nil, do: nil, else: YuurisanJSON.encode(payload)

        case send_request(method, "#{@base_url}/#{path}", headers, body, nil, ctx.proxy) do
          {:ok, status, _response_headers, response_body} when status >= 200 and status < 300 ->
            {:ok, decode_body(response_body), ctx}

          _other ->
            {:error, :retry_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp device_headers(device) do
    [
      {~c"accept", ~c"*/*"},
      {~c"accept-language", device_ch(device, "lang", "en-US,en;q=0.9")},
      {~c"cache-control", ~c"no-cache"},
      {~c"content-type", ~c"application/json"},
      {~c"origin", ~c"https://zmine.si"},
      {~c"pragma", ~c"no-cache"},
      {~c"referer", ~c"https://zmine.si/login"},
      {~c"sec-ch-ua", device_ch(device, "ch_ua", ~c"")},
      {~c"sec-ch-ua-mobile", device_ch(device, "ch_mobile", ~c"?0")},
      {~c"sec-ch-ua-platform", device_ch(device, "ch_platform", ~c"\"Windows\"")},
      {~c"user-agent", device_ch(device, "ua", ~c"")}
    ]
  end

  defp request_headers(device, cookie) do
    [
      {~c"accept", ~c"*/*"},
      {~c"accept-language", device_ch(device, "lang", "en-US,en;q=0.9")},
      {~c"cookie", String.to_charlist(cookie)},
      {~c"origin", ~c"https://zmine.si"},
      {~c"referer", ~c"https://zmine.si/app"},
      {~c"sec-ch-ua", device_ch(device, "ch_ua", ~c"")},
      {~c"sec-ch-ua-mobile", device_ch(device, "ch_mobile", ~c"?0")},
      {~c"sec-ch-ua-platform", device_ch(device, "ch_platform", ~c"\"Windows\"")},
      {~c"sec-fetch-dest", ~c"empty"},
      {~c"sec-fetch-mode", ~c"cors"},
      {~c"sec-fetch-site", ~c"same-origin"},
      {~c"user-agent", device_ch(device, "ua", ~c"")}
    ]
  end

  defp device_ch(device, name, fallback) do
    case get(device, name, nil) do
      value when is_binary(value) and value != "" -> String.to_charlist(value)
      _other -> fallback
    end
  end

  defp device_session(key, proxies, index) do
    device = device_for(key)

    case get(device, "proxy", nil) do
      cached when is_binary(cached) and cached != "" ->
        {device, cached}

      _other ->
        case proxy_for(proxies, index) do
          nil ->
            {device, nil}

          line ->
            device = Map.put(device, "proxy", line)
            save_device(key, device)
            {device, line}
        end
    end
  end

  defp device_for(key) do
    store = load_device_cache()

    case Map.get(store, device_key(key)) do
      %{} = record ->
        if is_binary(get(record, "ua", nil)) and get(record, "ua", "") != "" do
          record
        else
          fresh_device(key, store)
        end

      _other ->
        fresh_device(key, store)
    end
  end

  defp fresh_device(key, store) do
    record = build_device()
    File.write(Path.join(__DIR__, "device.json"), YuurisanJSON.encode_pretty(Map.put(store, device_key(key), record)))
    record
  end

  defp save_device(key, record) do
    store = load_device_cache()
    File.write(Path.join(__DIR__, "device.json"), YuurisanJSON.encode_pretty(Map.put(store, device_key(key), record)))
  end

  defp load_device_cache do
    case File.read(Path.join(__DIR__, "device.json")) do
      {:ok, content} ->
        case YuurisanJSON.decode(content) do
          {:ok, %{} = store} -> store
          _other -> %{}
        end

      {:error, _reason} ->
        %{}
    end
  end

  defp device_key(key) do
    :crypto.hash(:sha256, key) |> Base.encode16(case: :lower) |> String.slice(0, 16)
  end

  defp build_device do
    {ua, ch_ua, ch_mobile, ch_platform, lang} = Enum.random(device_pool())

    %{
      "ua" => ua,
      "ch_ua" => ch_ua,
      "ch_mobile" => ch_mobile,
      "ch_platform" => ch_platform,
      "lang" => lang
    }
  end

  defp device_pool do
    [
      {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
        "\"Google Chrome\";v=\"141\", \"Chromium\";v=\"141\", \"Not?A_Brand\";v=\"24\"",
        "?0",
        "\"Windows\"",
        "en-US,en;q=0.9"
      },
      {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
        "\"Google Chrome\";v=\"140\", \"Chromium\";v=\"140\", \"Not?A_Brand\";v=\"24\"",
        "?0",
        "\"Windows\"",
        "en-US,en;q=0.9"
      },
      {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
        "\"Google Chrome\";v=\"141\", \"Chromium\";v=\"141\", \"Not?A_Brand\";v=\"24\"",
        "?0",
        "\"macOS\"",
        "en-US,en;q=0.9"
      },
      {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36",
        "\"Google Chrome\";v=\"139\", \"Chromium\";v=\"139\", \"Not?A_Brand\";v=\"24\"",
        "?0",
        "\"macOS\"",
        "en-GB,en;q=0.9"
      },
      {
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
        "\"Google Chrome\";v=\"140\", \"Chromium\";v=\"140\", \"Not?A_Brand\";v=\"24\"",
        "?0",
        "\"Linux\"",
        "en-US,en;q=0.9"
      },
      {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36",
        "\"Google Chrome\";v=\"138\", \"Chromium\";v=\"138\", \"Not?A_Brand\";v=\"24\"",
        "?0",
        "\"Windows\"",
        "id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7"
      },
      {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36",
        "\"Google Chrome\";v=\"142\", \"Chromium\";v=\"142\", \"Not?A_Brand\";v=\"24\"",
        "?0",
        "\"macOS\"",
        "en-US,en;q=0.9"
      },
      {
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36",
        "\"Google Chrome\";v=\"137\", \"Chromium\";v=\"137\", \"Not?A_Brand\";v=\"24\"",
        "?0",
        "\"Linux\"",
        "en-US,en;q=0.9"
      }
    ]
  end

  defp cookie_from(headers) do
    headers
    |> Enum.filter(fn {name, _value} -> String.downcase(to_string(name)) == "set-cookie" end)
    |> Enum.map(fn {_name, value} ->
      value |> to_string() |> String.split(";") |> List.first() |> String.trim()
    end)
    |> Enum.find(fn value -> String.starts_with?(value, "zmine_session=") end)
  end

  defp error_code(body) do
    case get(decode_body(body), "error", nil) do
      %{} = error -> get(error, "code", "rejected")
      _other -> "rejected"
    end
  end

  defp decode_body(body) do
    case YuurisanJSON.decode(body) do
      {:ok, value} -> value
      {:error, _reason} -> %{}
    end
  end

  defp send_request(method, url, headers, body, _token, proxy) do
    address = String.to_charlist(url)
    {profile, auth} = proxy_setup(proxy)
    options = [ssl: [verify: :verify_none], timeout: 30_000, connect_timeout: 15_000] ++ auth

    request =
      case method do
        :get -> {:get, {address, headers}}
        :post -> {:post, {address, headers, ~c"application/json", body || "{}"}}
      end

    case :httpc.request(elem(request, 0), elem(request, 1), options, [body_format: :binary], profile) do
      {:ok, {{_protocol, status, _reason}, response_headers, response_body}} ->
        {:ok, status, response_headers, response_body}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp proxy_setup(nil), do: {:default, []}

  defp proxy_setup(line) do
    case parse_proxy(line) do
      {host, port, user, pass} -> proxy_profile(host, port, user, pass)
      {host, port} -> proxy_profile(host, port, "", "")
      nil -> {:default, []}
    end
  end

  defp proxy_profile(host, port, user, pass) do
    name = String.to_atom("proxy_#{host}_#{port}")
    address = {String.to_charlist(host), port}

    case :inets.start(:httpc, profile: name) do
      {:ok, _pid} -> :httpc.set_options([proxy: {address, []}, https_proxy: {address, []}], name)
      {:error, {:already_started, _pid}} -> :ok
      _other -> :ok
    end

    case user do
      "" -> {name, []}
      _user -> {name, [proxy_auth: {String.to_charlist(user), String.to_charlist(pass)}]}
    end
  end

  defp parse_proxy(line) do
    value =
      line
      |> String.trim()
      |> String.replace_prefix("http://", "")
      |> String.replace_prefix("https://", "")
      |> String.replace_prefix("socks5://", "")

    case String.split(value, "@") do
      [credentials, host_part] ->
        case String.split(credentials, ":") do
          [user, pass] -> with_host_port(host_part, user, pass)
          _other -> with_host_port(host_part, "", "")
        end

      [host_part] ->
        case String.split(host_part, ":") do
          [host, port] -> with_port(host, port)
          [host, port, user, pass] -> with_port_creds(host, port, user, pass)
          _other -> nil
        end
    end
  end

  defp with_host_port(host_part, user, pass) do
    case String.split(host_part, ":") do
      [host, port] -> with_port_creds(host, port, user, pass)
      _other -> nil
    end
  end

  defp with_port(host, port) do
    case Integer.parse(port) do
      {number, ""} -> {host, number}
      _other -> nil
    end
  end

  defp with_port_creds(host, port, user, pass) do
    case Integer.parse(port) do
      {number, ""} -> {host, number, user, pass}
      _other -> nil
    end
  end

  defp mask_proxy(line) do
    case parse_proxy(line) do
      {host, port, _user, _pass} -> "http://user:pass@#{mask_host(host)}:#{port}"
      {host, port} -> "http://user:pass@#{mask_host(host)}:#{port}"
      nil -> "http://user:pass@***:***"
    end
  end

  defp mask_host(host) do
    parts = String.split(host, ".")

    case parts do
      [a, _b, _c, d] ->
        "#{a}*****#{d}"

      _other ->
        if String.length(host) > 4 do
          String.slice(host, 0, 2) <> "*****" <> String.slice(host, -2, 2)
        else
          "***"
        end
    end
  end

  defp proxy_for([], _index), do: nil
  defp proxy_for(proxies, index), do: Enum.at(proxies, rem(index, length(proxies)))

  defp load_lines(name) do
    case File.read(Path.join(__DIR__, name)) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:error, _reason} ->
        []
    end
  end

  defp load_settings do
    case File.read(Path.join(__DIR__, "config.json")) do
      {:ok, content} ->
        case YuurisanJSON.decode(content) do
          {:ok, value} -> value
          {:error, _reason} -> default_settings()
        end

      {:error, _reason} ->
        settings = default_settings()
        File.write(Path.join(__DIR__, "config.json"), YuurisanJSON.encode_pretty(settings))
        settings
    end
  end

  defp default_settings, do: %{"settings" => %{"sleep_seconds" => 3600}}

  defp sleep_seconds(settings) do
    case get(get(settings, "settings", %{}), "sleep_seconds", 3600) do
      value when is_integer(value) and value > 0 -> value
      value when is_float(value) and value > 0 -> trunc(value)
      _other -> 3600
    end
  end

  defp display_name(user) do
    case get(user, "displayName", nil) do
      nil -> get(user, "handle", "unknown miner")
      name -> name
    end
  end

  defp solve(prompt, options) do
    text = String.trim(prompt)

    facts = [
      {"February has 29 days in every year divisible by 4, including 1900", false},
      {"maximum supply of 21 million ZEC", true},
      {"shielded transactions use zero-knowledge proofs", true},
      {"transparent address starts with 'zs1'", false},
      {"launched in 2016 as a fork of the Bitcoin codebase", true},
      {"24-word BIP-39 phrase encodes 256 bits of entropy plus an 8-bit checksum", true},
      {"typeof null", false},
      {"'10' + 5", false},
      {"all squares are rectangles, so all rectangles are squares", false},
      {"if it rains the ground gets wet", false},
      {"no fish are mammals, whales are mammals", true},
      {"Stake is withdrawable after a 7-day cooldown", false},
      {"The epoch reward halves every 210,240 epochs", true},
      {"0.1 + 0.2 equals exactly 0.3", false},
      {"1 kilobyte in the SI sense is 1024 bytes", false},
      {"1 ZEC = 100,000,000 zatoshi", true}
    ]

    picks = [
      {"capital of Australia", "Canberra"},
      {"Which Zcash address type bundles", "Unified"},
      {"SHA-256 hash is how many bits long", "256"},
      {"Math.floor(-1.5)", "-2"},
      {"filters rows after an aggregate", "HAVING"},
      {"'idempotent'", "repeating it has the same effect as doing it once"},
      {"Orders rest on the book until filled or cancelled", "A resting order can be cancelled"},
      {"every miner who staked got a bonus", "did not stake"}
    ]

    fact = Enum.find(facts, fn {fragment, _value} -> String.contains?(text, fragment) end)
    pick_hint = Enum.find(picks, fn {fragment, _want} -> String.contains?(text, fragment) end)

    cond do
      fact != nil ->
        {_fragment, value} = fact
        verdict(options, value)

      pick_hint != nil ->
        {_fragment, want} = pick_hint
        Enum.find_index(options, fn option -> String.contains?(option, want) end)

      String.contains?(text, "is a prime number") ->
        Enum.find_index(options, fn option ->
          case num_of(option) do
            nil -> false
            value -> prime?(trunc(value))
          end
        end)

      String.contains?(text, "x * 2") and String.contains?(text, "map") ->
        verdict(options, true)

      String.contains?(text, "len('zcash')") ->
        verdict(options, true)

      true ->
        solve_pattern(text, options)
    end
  end

  defp solve_pattern(text, options) do
    cond do
      match = Regex.run(~r/claims: ([\d,]+) is a factor of ([\d,]+)\./, text) ->
        [_all, a, b] = match
        verdict(options, rem(to_int(b), to_int(a)) == 0)

      match = Regex.run(~r/claims: there are ([\d,]+) ten-minute epochs in a day/, text) ->
        [_all, a] = match
        verdict(options, to_int(a) == 144)

      match = Regex.run(~r/block time of (\d+) seconds gives roughly how many blocks per day/, text) ->
        [_all, a] = match
        pick(options, div(86_400, to_int(a)))

      match = Regex.run(~r/^What is (\d+)% of ([\d,]+)\?$/, text) ->
        [_all, a, b] = match
        pick(options, percent_of(to_int(a), to_int(b)))

      match = Regex.run(~r/one block every (\d+) seconds\. How many blocks is that per day/, text) ->
        [_all, a] = match
        pick(options, div(86_400, to_int(a)))

      match = Regex.run(~r/Epochs last (\d+) minutes\. How many epochs are there in ([\d,]+) hours/, text) ->
        [_all, a, b] = match
        pick(options, to_int(b) * div(60, to_int(a)))

      match = Regex.run(~r/claims: ([\d.]+) ZEC = ([\d,]+) zatoshi/, text) ->
        [_all, a, b] = match
        verdict(options, zatoshi(a) == to_int(b))

      match = Regex.run(~r/claims: ([\d,]+) x ([\d,]+) = ([\d,]+)\./, text) ->
        [_all, a, b, c] = match
        verdict(options, to_int(a) * to_int(b) == to_int(c))

      match = Regex.run(~r/claims: ([\d,]+) \/ ([\d,]+) = ([\d,]+)\./, text) ->
        [_all, a, b, c] = match
        left = to_int(a)
        right = to_int(b)
        verdict(options, right != 0 and rem(left, right) == 0 and div(left, right) == to_int(c))

      match = Regex.run(~r/claims: (\d+)% of ([\d,]+) is ([\d,]+)\./, text) ->
        [_all, a, b, c] = match
        verdict(options, percent_of(to_int(a), to_int(b)) == to_int(c))

      match = Regex.run(~r/claims: 2\^(\d+) = ([\d,]+)\./, text) ->
        [_all, a, b] = match
        verdict(options, trunc(:math.pow(2, to_int(a))) == to_int(b))

      match = Regex.run(~r/sum of the integers from 1 to ([\d,]+) is ([\d,]+)\./, text) ->
        [_all, a, b] = match
        n = to_int(a)
        verdict(options, div(n * (n + 1), 2) == to_int(b))

      match = Regex.run(~r/rises (\d+)% and then falls (\d+)%/, text) ->
        [_all, a, b] = match
        factor = (1 + to_int(a) / 100) * (1 - to_int(b) / 100)
        direction_pick(options, (factor - 1) * 100)

      match = Regex.run(~r/closest to the square root of ([\d,]+)/, text) ->
        [_all, a] = match
        closest_pick(options, :math.sqrt(to_int(a) * 1.0))

      match = Regex.run(~r/clock shows (\d+):(\d+)/, text) ->
        [_all, hour, minute] = match
        angle = abs(30 * rem(to_int(hour), 12) - 5.5 * to_int(minute))
        pick(options, min(angle, 360 - angle))

      match = Regex.run(~r/How many seconds are in ([\d.]+) hours\?/, text) ->
        [_all, a] = match
        pick(options, trunc(num_of(a) * 3600))

      match = Regex.run(~r/How many seconds are in ([\d.]+) minutes\?/, text) ->
        [_all, a] = match
        pick(options, trunc(num_of(a) * 60))

      match = Regex.run(~r/Sequence: ([\d,\s]+)\.\.\. Next term\?/, text) ->
        [_all, a] = match
        sequence_pick(options, a)

      true ->
        nil
    end
  end

  defp verdict(options, truth) do
    Enum.find_index(options, fn option ->
      low = option |> String.trim() |> String.downcase()

      if truth do
        low in ["correct", "true", "yes"]
      else
        low in ["incorrect", "false", "no"]
      end
    end)
  end

  defp pick(options, value) do
    target = value |> to_string() |> norm()

    case Enum.find_index(options, fn option -> norm(option) == target end) do
      nil ->
        case parse_number(target) do
          nil -> nil
          want -> nearest_pick(options, want)
        end

      index ->
        index
    end
  end

  defp nearest_pick(options, want) do
    options
    |> Enum.with_index()
    |> Enum.map(fn {option, index} -> {num_of(option), index} end)
    |> Enum.reject(fn {value, _index} -> is_nil(value) end)
    |> Enum.map(fn {value, index} -> {abs(value - want), index} end)
    |> Enum.sort()
    |> Enum.find(fn {distance, _index} -> distance < 0.000001 end)
    |> case do
      nil -> nil
      {_distance, index} -> index
    end
  end

  defp closest_pick(options, target) do
    options
    |> Enum.with_index()
    |> Enum.map(fn {option, index} -> {num_of(option), index} end)
    |> Enum.reject(fn {value, _index} -> is_nil(value) end)
    |> Enum.map(fn {value, index} -> {abs(value - target), index} end)
    |> Enum.sort()
    |> case do
      [{_distance, index} | _rest] -> index
      [] -> nil
    end
  end

  defp direction_pick(options, percent) do
    {fragment, magnitude} =
      cond do
        abs(percent) < 0.000000001 -> {"the same", nil}
        percent > 0 -> {"higher", percent}
        true -> {"lower", abs(percent)}
      end

    candidates =
      options
      |> Enum.with_index()
      |> Enum.filter(fn {option, _index} ->
        String.contains?(String.downcase(option), fragment)
      end)

    case {magnitude, candidates} do
      {nil, [{_option, index} | _rest]} -> index
      {nil, []} -> nil
      {_value, []} -> nil

      {value, list} ->
        list
        |> Enum.map(fn {option, index} -> {num_of(option), index} end)
        |> Enum.filter(fn {number, _index} ->
          is_number(number) and abs(number - value) < 0.000001
        end)
        |> case do
          [{_number, index} | _rest] -> index
          [] -> elem(Enum.at(list, 0), 1)
        end
    end
  end

  defp sequence_pick(options, text) do
    numbers =
      ~r/\d+/
      |> Regex.scan(text)
      |> Enum.map(fn [value] -> String.to_integer(value) end)

    if length(numbers) >= 3 do
      first = diffs(numbers)
      second = diffs(first)

      cond do
        length(Enum.uniq(second)) == 1 ->
          pick(options, List.last(numbers) + List.last(first) + List.last(second))

        length(Enum.uniq(first)) == 1 ->
          pick(options, List.last(numbers) + List.last(first))

        true ->
          nil
      end
    else
      nil
    end
  end

  defp diffs(list) do
    list
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> b - a end)
  end

  defp percent_of(percent, total) do
    product = percent * total

    if rem(product, 100) == 0 do
      div(product, 100)
    else
      product / 100
    end
  end

  defp zatoshi(text), do: round(num_of(text) * 100_000_000)

  defp prime?(value) when value < 2, do: false

  defp prime?(value) do
    limit = trunc(:math.sqrt(value))
    not Enum.any?(2..max(limit, 2), fn divisor -> rem(value, divisor) == 0 end)
  end

  defp num_of(text) do
    case Regex.run(~r/-?\d+(?:\.\d+)?/, norm(text)) do
      [value] -> parse_number(value)
      _other -> nil
    end
  end

  defp parse_number(text) do
    case Integer.parse(text) do
      {value, ""} ->
        value * 1.0

      _other ->
        case Float.parse(text) do
          {value, ""} -> value
          _other -> nil
        end
    end
  end

  defp norm(text), do: text |> String.replace(",", "") |> String.trim()

  defp to_int(text) do
    case Integer.parse(norm(text)) do
      {value, _rest} -> value
      :error -> trunc(num_of(text) || 0)
    end
  end

  defp number(value) when is_integer(value), do: value
  defp number(value) when is_float(value), do: trunc(value)

  defp number(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _rest} ->
        parsed

      :error ->
        case Float.parse(value) do
          {parsed, _rest} -> trunc(parsed)
          _other -> 0
        end
    end
  end

  defp number(_value), do: 0

  defp install_signal_handler do
    handler = fn ->
      IO.write("\n" <> @red <> @bold <> "Script stopped by user" <> @reset <> "\n")
      System.halt(0)
    end

    try do
      System.trap_signal(:sigint, handler)
    rescue
      _error -> :ok
    end

    try do
      System.trap_signal(:sigterm, handler)
    rescue
      _error -> :ok
    end
  end

  defp plural(count, word) do
    if count == 1, do: "#{count} #{word}", else: "#{count} #{pluralize(word)}"
  end

  defp pluralize(word) do
    size = String.length(word)
    last = if size > 0, do: String.at(word, size - 1), else: ""
    before = if size > 1, do: String.at(word, size - 2), else: ""

    if last == "y" and before not in ["a", "e", "i", "o", "u"] do
      String.slice(word, 0, size - 1) <> "ies"
    else
      word <> "s"
    end
  end

  defp countdown(seconds, label) do
    left = max(trunc(seconds), 0)

    if left >= 1 do
      width = frame(label, left, 0)
      tick(left, label, width)
    end
  end

  defp tick(0, _label, width) do
    IO.write("\r" <> String.duplicate(" ", width) <> "\r")
  end

  defp tick(left, label, width) do
    width = frame(label, left, width)
    :timer.sleep(1000)
    tick(left - 1, label, width)
  end

  defp frame(label, left, width) do
    text = label <> " " <> format_duration(left)
    IO.write("\r" <> @yellow <> @bold <> text <> @reset)
    max(width, String.length(text))
  end

  defp format_duration(total) do
    days = div(total, 86_400)
    hours = div(rem(total, 86_400), 3600)
    minutes = div(rem(total, 3600), 60)
    seconds = rem(total, 60)

    if days > 0 do
      pad(days) <> ":" <> pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    else
      pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    end
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 2, "0")

  defp get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp get(_other, _key, default), do: default

  defp green(message), do: IO.puts(@green <> @bold <> message <> @reset)
  defp yellow(message), do: IO.puts(@yellow <> @bold <> message <> @reset)
  defp red(message), do: IO.puts(@red <> @bold <> message <> @reset)
end

ZMine.run()
