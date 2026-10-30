<!-- ===================== HEADER ===================== -->
<div align="center">
  <img
    src="https://capsule-render.vercel.app/api?type=waving&color=gradient&text=ReconForge&height=140&section=header"
    alt="ReconForge Header"
    width="100%"
  />
</div>

# ReconForge v2

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Kali%20%2F%20Debian-blueviolet)
![Shell](https://img.shields.io/badge/shell-bash%20%2F%20zsh-green)

**Advanced Reconnaissance Toolkit Manager** — a modular installer and manager for Bug Bounty recon tools on Kali / Debian-based Linux (amd64 & arm64), with unified CLI commands, an interactive installer, smart language & dependency checks, and full lifecycle management (install → verify → update → remove).

> ⚠️ Run these tools only against assets you are explicitly authorized to test (e.g., in-scope Bug Bounty programs).

---

## What's new in v2

| Feature | Description |
|---|---|
| **Interactive menu** | Pick categories with numbers, `[x]` checkboxes, plus Select All / Clear |
| **Smart installation** | Checks every tool before installing — already-present tools are skipped automatically |
| **Language & dependency pre-check** | Verifies Go / Python 3 (+venv) / pipx / build tools **before** any download — present ones are skipped, missing or outdated ones are installed automatically |
| **Unified `reconforge` CLI** | One command for everything: install / update / check / list / remove / doctor |
| **Parallel installation** | Go tools install concurrently — tune it with `--jobs N` |
| **Error recovery** | A failed tool never stops the rest; you get a ready-made retry command at the end |
| **Installation logs** | Every run is logged to `~/.local/state/reconforge/logs/` |
| **Post-install verification** | Every tool is executed (version/help) after install and recorded with its version |
| **SHA256** | Go downloads are verified against the official go.dev checksums |
| **Go protection** | A Go installation outside reconforge management is **never** touched without a typed `yes` confirmation |
| **Uninstaller** | `reconforge remove` deletes only what reconforge installed, with confirmation |
| **Update manager** | `reconforge update` upgrades every tool in one command |
| **Dry run** | `--dry-run` previews the full plan — dependencies, runtimes and tools — without executing anything |
| **Architecture detection** | Automatic AMD64 & ARM64 support |
| **Shell compatibility** | PATH automatically configured for `.bashrc` and `.zshrc` |
| **Modular architecture** | One module file per tool category under `lib/modules/` |

---

## Quick start

```bash
# Run the interactive installer (it asks what you want to install)
bash install_recon_tools.sh

# or directly from the CLI
./reconforge install

# register the global 'reconforge' command (after the first run):
./reconforge setup
reconforge --help
```

## Commands

```
reconforge install    Install tools (interactive menu by default)
reconforge update     Update all tools
reconforge check      Per-tool status report (Installed / Missing + version)
reconforge list       List every tool by category
reconforge remove     Remove tools
reconforge doctor     Diagnose prerequisites, environment, state and logs
reconforge setup      Install the 'reconforge' command into ~/.local/bin
reconforge version    Print version
```

### Example: `reconforge check`

```
  TOOL                 CATEGORY      STATUS
  ----------------------------------------------------------
  subfinder            subdomain     Installed 2.6.9 *
  amass                subdomain     Installed 4.2.0 *
  ffuf                 web           Missing
  katana               web           Installed 1.1.0 *
  ----------------------------------------------------------
  Installed: 3   Missing: 1   (* = managed by reconforge)
```

## install / update options

```bash
reconforge install                     # interactive menu
reconforge install --all --dry-run     # preview the full plan without executing
reconforge install --tools subfinder,httpx,ffuf
reconforge install --only subdomain,web
reconforge install --all --gui         # all CLI categories + Burp/Postman
reconforge install --jobs 8            # install with 8 parallel workers
reconforge update                      # update everything
reconforge update --only subdomain,web
reconforge update --tools ffuf
```

**Category ids:** `subdomain` · `web` · `archive` · `js` · `params` · `content` · `cloud` · `osint` · `wordlists` · `gui`

> `--all` covers categories 1–9 (wordlists included) and excludes the GUI category. Add `--gui` or toggle it in the menu.

## Interactive menu

It looks like this — type category numbers to toggle them (e.g. `1 4 7`), or use the letter commands:

```
  RECONFORGE — Installation Categories
  Categories selected: 9/10

   1) [x] Subdomain Enumeration
         Subfinder, Amass, MassDNS, Shuffledns, DNSX, SubBrute
   2) [x] Web Discovery
         HTTPX, FFUF, Katana, Hakrawler, Gospider, Httprobe, Anew
   ...
  10) [ ] GUI Applications
         Burpsuite, Postman

  <number(s)> toggle · a all · c clear · i install · q quit
```

## Language & dependency pre-check

Before anything is downloaded, reconforge verifies every runtime and dependency the toolkit needs:

| Requirement | Check | If missing / too old |
|---|---|---|
| **Go** | present + version ≥ 1.26.10 | Downloads the latest stable from go.dev, **SHA256-verified** |
| **Python 3 + venv** | present + version ≥ 3.9 + working `ensurepip` | `apt install python3 python3-venv python3-pip` |
| **pipx** | present | `apt install pipx` |
| **Build tools** | `make` + `gcc` | `apt install make build-essential pkg-config` |
| **System tools** | curl / wget / git / jq / tar / xz / unzip / dig + libpcap/libssl/libffi (dpkg check) | Collected into a single `apt install` |

- Already-sufficient components are skipped with an `ok` line; only the gaps get installed.
- Runtimes are re-verified after installation — a broken Python/pipx aborts the run with a clear error instead of failing silently later.
- `--dry-run` reports the runtime plan too, e.g. `[dry-run] Go is missing — would download the latest stable Go for linux/amd64 (SHA256 verified).`
- `reconforge doctor` shows the same checks in its `Language runtimes` section.

## Tools (34, in 10 categories)

| # | Category | Tools |
|---|---|---|
| 1 | Subdomain Enumeration | Subfinder, Amass, MassDNS, Shuffledns, DNSX, SubBrute |
| 2 | Web Discovery | HTTPX, FFUF, Katana, Hakrawler, Gospider, Httprobe, Anew |
| 3 | URL & Archive Discovery | GAU, Waybackurls |
| 4 | JavaScript Analysis | LinkFinder, SubJS, JSFinder, GF |
| 5 | Parameter Discovery | Arjun, ParamSpider |
| 6 | Content Discovery | Feroxbuster, Dirsearch |
| 7 | Cloud & API | CloudEnum, S3Scanner, Kiterunner, AWS CLI |
| 8 | OSINT & Intelligence | GitDorker, GitHub-Subdomains, Shodan, Censys |
| 9 | Wordlists | SecLists, GF Patterns |
| 10 | GUI Applications | Burp Suite, Postman |

## Files & directories

| Path | Content |
|---|---|
| `~/.local/bin/` | Tool binaries and launchers |
| `~/tools/recon/` | Tool source checkouts (git clones) |
| `~/.venvs/recon-tools/` | Isolated Python venv per tool |
| `~/go/` | GOPATH |
| `~/.gf/` | GF patterns |
| `~/.local/state/reconforge/installed.tsv` | Managed-tool registry (name/category/type/version/date) |
| `~/.local/state/reconforge/logs/` | Full log of every install / update / remove run |

Temporary files during installation (Go archive, AWS installer script) are created under the system temp directory and are always cleaned up — including on failure paths.

## Removing tools

```bash
reconforge remove subfinder amass
reconforge remove --category cloud
reconforge remove all -y          # every tool (skips per-tool confirmation)
reconforge remove go              # Go removal — requires typing 'yes'
```

- Removal covers the binary, the venv, the source checkout and the state entry.
- **Go protection:** a Go installation outside reconforge management is never removed or replaced without a typed `yes` confirmation — `--yes` does not bypass it. Instead of replacing a system Go, you can choose to install a private copy in `~/.local/go-reconforge` and leave the system Go untouched.

## Troubleshooting

```bash
reconforge doctor        # full diagnosis: prerequisites, PATH, state, logs
reconforge check         # what is missing?
cat "$(ls -t ~/.local/state/reconforge/logs/* | head -1)"   # latest log
```

- A tool failed? Retry only that tool: `reconforge install --tools <name>`
- OSINT tools need your own tokens: `shodan init <API_KEY>` · `censys config auth add` · GitDorker and github-subdomains need a GitHub PAT.

## Project structure

```
ReconForge/
├── reconforge              # main CLI
├── install_recon_tools.sh  # bootstrap (backwards-compatible entry point)
├── lib/
│   ├── common.sh           # logging, platform, fetch+SHA256, parallel runner
│   ├── registry.sh         # tool registry + install/remove handlers + Go management
│   ├── menu.sh             # interactive menu
│   ├── commands.sh         # command implementations
│   └── modules/            # one file per tool category
│       ├── 10_subdomain.sh ... 99_gui.sh
└── legacy/                 # original single-file installer (v1)
```

## Security notes

- Go downloads are verified with **SHA256** from `go.dev/dl/?mode=json`, and `go install` relies on the Go module checksum database (`sum.golang.org`) automatically.
- Nothing is downloaded or deleted before the plan is shown — and `--dry-run` is always available.
- Review each tool's help output yourself, and run active discovery only against assets you are officially authorized to test.

## License

Released under the [MIT License](LICENSE) — free to use, modify and distribute with attribution.

```
Copyright (c) 2026 xIsmail
```

<p align="center">
🔒 <em>Stay safe, stay curious — Built with ❤️ for the security community.</em>
</p>

<!-- ===================== FOOTER ===================== -->
<div align="center">
  <img 
    src="https://capsule-render.vercel.app/api?type=waving&color=gradient&height=110&section=footer"
    alt="GitHub Footer"
    width="100%"
  />
</div>
