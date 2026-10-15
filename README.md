<div align="center">

<img width="100%" alt="header" src="https://capsule-render.vercel.app/api?type=waving&height=210&text=ZMine%20Bot&fontAlign=50&fontAlignY=36&fontSize=56&desc=Auto%20Mining%20%7C%20SI%20Question%20Solver%20%7C%20Referral%20Creator%20%7C%20Multi-Account&descAlign=50&descAlignY=58"/>

<img alt="typing" src="https://readme-typing-svg.demolab.com?font=Inter&size=18&duration=3000&pause=650&center=true&vCenter=true&width=900&lines=Auto+Mining+Session+%7C+Start+%26+Activate+Daily;Auto+SI+Question+Solver+%7C+Math+%2F+Logic+%2F+ZEC+Facts;Auto+Referral+Account+Creator+%7C+Bulk+Registration;Per-Account+Device+Fingerprint+Cached;Multi-Account+%7C+All+Keys+Per+Cycle"/>

<p>
  <img alt="elixir" src="https://img.shields.io/badge/Elixir-1.14%2B-4B275F?logo=elixir&logoColor=white"/>
  <img alt="ruby" src="https://img.shields.io/badge/Ruby-3.2+-CC342D?logo=ruby&logoColor=white"/>
  <img alt="platform" src="https://img.shields.io/badge/Platform-ZMine-111111"/>
  <img alt="multi-account" src="https://img.shields.io/badge/Multi--Account-Supported-111111"/>
  <img alt="proxy" src="https://img.shields.io/badge/Proxy-Supported-111111"/>
  <img alt="author" src="https://img.shields.io/badge/by-Yuurisandesu-111111"/>
</p>

<p>
  <b>ZMine Bot</b> has two components: a main automation bot written in Elixir and a referral account creator written in Ruby.<br/>
  The main bot handles the complete cycle: activating the daily mining session, answering the SI question rail automatically using a built-in solver for math, logic, ZEC, and Zcash knowledge questions, reporting the wallet balance, and reviewing advisor actions, all across multiple accounts with per-account device caching, proxy support, and a live countdown. The referral creator generates and registers new accounts in bulk.<br/>
  Built and distributed by <b>Yuurisandesu</b>.
</p>

</div>

---

## Table of Contents

- [Requirements](#requirements)
- [Install Elixir](#install-elixir)
- [Install Ruby](#install-ruby)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Main Bot](#running-the-main-bot)
- [Running the Referral Creator](#running-the-referral-creator)
- [Features](#features)
- [File Structure](#file-structure)
- [Disclaimer](#disclaimer)

---

## Requirements

- Elixir `1.14+` with Erlang/OTP (for the main bot)
- Ruby `3.2+` with Bundler (for the referral creator)
- Git

---

## Install Elixir

Elixir runs on the Erlang virtual machine, so Erlang/OTP is required. Elixir cannot run without it. Every package manager below installs Erlang/OTP automatically as a dependency. The only path that needs a separate Erlang step is the Windows manual installer.

### Windows

**Option A - package manager (recommended, installs Erlang automatically):**

```cmd
winget install Elixir.Elixir
```

**Option B - manual installer (two installers, in this order):**

1. Download and run the **Erlang/OTP installer** from https://www.erlang.org/downloads
2. Run `erl -s halt` to check which OTP version you got
3. Download the **Elixir installer built for that exact OTP** from https://elixir-lang.org/install.html (`elixir-otp-<N>.exe`) and run it

Then open Command Prompt and verify:

```cmd
elixir --version
```

The output prints both versions, for example `Elixir 1.14.0 (compiled with Erlang/OTP 25)`.

### Linux (Ubuntu / Debian)

```bash
sudo apt-get update
sudo apt-get install -y elixir
elixir --version
```

### macOS

```bash
brew install elixir
elixir --version
```

> If you do not have Homebrew, install it first from https://brew.sh

### Termux (Android)

```bash
pkg update && pkg upgrade -y
pkg install elixir -y
elixir --version
```

> If the `elixir` package is not available in your Termux repository, install an Ubuntu environment first with `pkg install proot-distro`, then `proot-distro install ubuntu`, then `proot-distro login ubuntu` and run the Linux command above inside it.

---

## Install Ruby

Ruby is only needed to run the referral account creator (`bot.rb`). Skip this section if you only need the main bot.

### Linux

```bash
sudo apt update && sudo apt install -y ruby ruby-bundler git
```

### macOS

```bash
brew install ruby
```

### Windows

Download and run the installer from https://rubyinstaller.org. Check **Add Ruby executables to your PATH** during installation. Verify with:

```bash
ruby --version
```

### Termux (Android)

```bash
pkg update && pkg install ruby git
```

---

## Installation

**Clone the repository:**

```bash
git clone https://github.com/Yuurisan-N1/Zmine-Bot.git
cd Zmine-Bot
```

**Install Ruby dependencies (only needed for `bot.rb`):**

```bash
bundle install
```

---

## Configuration

### 1. Login Keys (data.txt)

Fill `data.txt` with your ZMine login keys, one per line:

```
yourloginkey1here
yourloginkey2here
```

> Login keys can be found in your ZMine account settings or the `account/loginKey.txt` file if you registered via the referral creator.

### 2. Proxy (proxy.txt)

Fill `proxy.txt` with proxies, one per line (optional, leave empty to run without proxy):

```
host:port
host:port:user:pass
http://user:pass@host:port
```

Proxies are assigned to accounts by index in round-robin order. The proxy assigned to each account is cached in `device.json` and reused on all subsequent cycles.

### 3. Bot Settings (config.json)

`sleep_seconds` controls how many seconds the bot waits between cycles. If `config.json` is missing, it is created automatically with a default of `3600` seconds.

---

## Running the Main Bot

**Linux / macOS:**

```bash
elixir --erl "+Bd" bot.exs
```

**Windows:**

```cmd
elixir --erl "+Bc" bot.exs
```

Or just double click `run_pc.bat`, which runs the Windows command above.

---

## Running the Referral Creator

The referral creator (`bot.rb`) registers new ZMine accounts in bulk using randomly generated identities and saves the credentials to the `account/` folder.

```bash
ruby bot.rb
```

Each registered account is saved with its login key, recovery phrase, and account data inside `account/`. These keys can then be copied into `data.txt` to be used by the main bot.

---

## Features

### Auto Mining Session
The bot fetches the mining overview for each account and logs the total MINE mined, current hashpower in MH, streak in days, and total sessions. If no mining session is active, it starts one immediately. If a session is already running, that is logged and the session is left to continue.

### SI Question Solver
After mining, the bot works through the SI question rail automatically until the daily cap is reached or the cooldown becomes too long to wait. The built-in solver handles multiple question categories:

- **Math questions** multiplication, division, percentage, power of 2, sum of integers, clock angle, sequence next term, block-per-day calculations, ZEC/zatoshi conversions, percent rise and fall
- **True/False questions** ZEC supply, shielded transactions, Zcash history, BIP-39 entropy, JavaScript behavior, logic statements, staking rules, epoch rewards, floating point precision
- **Multiple choice questions** capital cities, Zcash address types, SHA-256 hash length, SQL clauses, prime number detection, and more

Each answer waits 5 seconds before submitting to avoid rejection for answering too fast. If the server says the answer was too fast, it waits and retries. If a question has no match in the solver, it is skipped and the next one is fetched.

### Wallet Report
After the question rail, the bot fetches the wallet balance and logs the available MINE and ZEC for each account.

### Advisor Report
The bot fetches the advisor recommendation list and logs how many actions are available for review. Boost and stake actions are left untouched to keep the balance safe.

### Per-Account Device Fingerprint
Each account gets a unique device profile on first run, selected from a pool of 8 Chrome User-Agents across Windows, macOS, and Linux. The profile is saved to `device.json` keyed by a hash of the login key and reused on all subsequent cycles. The assigned proxy is also cached in the same device record.

### Session Renewal
If the server returns a 401 or 403 response during any request, the bot automatically logs in again to renew the session cookie and retries the original request without interrupting the cycle.

### Multi Account
All login keys in `data.txt` are processed sequentially within every cycle. Each account runs its full cycle before moving to the next.

### Proxy Support
Proxies are loaded from `proxy.txt` and assigned to accounts by index in round-robin order. HTTP and SOCKS5 proxies with or without credentials are supported. The assigned proxy is locked to each account and cached in `device.json`. Running without proxies is fully supported.

### Auto Countdown
After all accounts complete a cycle, the bot displays a live `HH:MM:SS` countdown until the next cycle starts.

### Referral Account Creator
`bot.rb` registers new ZMine accounts in bulk using randomly generated names, emails, and identities. Each account is registered with the configured referral code. Login keys, recovery phrases, and account data are saved to `account/` after each successful registration.

---

## File Structure

```text
Zmine-Bot/
├── bot.exs             # Main bot, full cycle automation (Elixir script)
├── bot.rb              # Referral account creator (Ruby)
├── run_pc.bat          # Windows launcher for bot.exs
├── config.json         # Sleep duration between cycles
├── data.txt            # Login keys, one per line
├── proxy.txt           # Proxy list, one per line (optional)
├── device.json         # Per-account device fingerprint and proxy cache (auto-generated)
├── Gemfile             # Ruby gem dependencies for bot.rb
├── LICENSE             # License file
├── account/
│   ├── loginKey.txt    # Login keys saved by the referral creator
│   ├── recoveryPhrase.txt  # Recovery phrases saved by the referral creator
│   └── account.json    # Full account data saved by the referral creator
└── utils/
    ├── banner.ex       # Elixir banner module
    ├── banner.rb       # Ruby banner module
    └── json.ex         # Elixir JSON parser module
```

---

## Disclaimer

This tool is built for educational and technical exploration purposes. Use it wisely and at your own responsibility.

---

<div align="center">
<img width="100%" alt="footer" src="https://capsule-render.vercel.app/api?type=waving&height=120&section=footer"/>
</div>