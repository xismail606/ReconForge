#!/usr/bin/env bash
# ============================================================
# ReconForge — lib/common.sh
# Shared utilities: paths, platform detection, logging,
# downloads (with SHA256 verification), parallel runner.
# This file is sourced by the reconforge CLI — do not execute.
# ============================================================

[[ -n "${RF_COMMON_SH:-}" ]] && return 0
RF_COMMON_SH=1

RF_VERSION="2.0.0"

# reconforge home = parent directory of lib/
RF_HOME="${RF_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"

# ---------- paths ----------
RF_STATE_ROOT="${RF_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/reconforge}"
RF_LOG_DIR="$RF_STATE_ROOT/logs"
RF_STATE_FILE="$RF_STATE_ROOT/installed.tsv"
RF_GO_STATE="$RF_STATE_ROOT/goruntime.conf"

RF_LOCAL_BIN="${HOME}/.local/bin"
RF_TOOLS_DIR="${HOME}/tools/recon"
RF_VENV_DIR="${HOME}/.venvs/recon-tools"
RF_GOPATH_DIR="${HOME}/go"
RF_GOBIN_DIR="$RF_LOCAL_BIN"
RF_GF_DIR="${HOME}/.gf"

# ---------- tunables ----------
RF_GO_MIN_VERSION="1.26.10"
RF_PY_MIN_VERSION="3.9"
RF_JOBS=4
RF_ASSUME_YES=0
RF_DRY_RUN=0
RF_FORCE=0
RF_NO_DEPS=0
RF_LOG_FILE=""
RF_TMP_DIR=""

# ---------- colors (real escape chars, safe with printf %s) ----------
if [[ -t 1 ]]; then
  GREEN=$'\e[0;32m'; YELLOW=$'\e[1;33m'; RED=$'\e[0;31m'
  BLUE=$'\e[0;34m';  CYAN=$'\e[0;36m';   BOLD=$'\e[1m'; NC=$'\e[0m'
else
  GREEN=''; YELLOW=''; RED=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

# ---------- logging ----------
rf_log_init() { # rf_log_init <command-name>
  mkdir -p "$RF_LOG_DIR"
  RF_LOG_FILE="$RF_LOG_DIR/$1-$(date +%Y%m%d-%H%M%S).log"
  { echo "# reconforge $1 | $(date '+%F %T %z') | host: $(uname -sm)"; } > "$RF_LOG_FILE"
}

rf_logline() {
  [[ -n "${RF_LOG_FILE:-}" ]] && printf '[%s] %s\n' "$1" "$2" >> "$RF_LOG_FILE" 2>/dev/null
  return 0
}
log()  { printf '%s[*]%s %s\n' "$BLUE"   "$NC" "$*"; rf_logline '*' "$*"; }
ok()   { printf '%s[+]%s %s\n' "$GREEN"  "$NC" "$*"; rf_logline '+' "$*"; }
warn() { printf '%s[!]%s %s\n' "$YELLOW" "$NC" "$*" >&2; rf_logline '!' "$*"; }
err()  { printf '%s[-]%s %s\n' "$RED"    "$NC" "$*" >&2; rf_logline '-' "$*"; }
die()  { err "$*"; exit 1; }
dry()  { printf '%s[dry-run]%s %s\n' "$YELLOW" "$NC" "$*"; rf_logline 'dry' "$*"; }

rf_hr() { printf '  %s\n' "----------------------------------------------------------"; }

# ---------- sudo ----------
SUDO=""
rf_setup_sudo() {
  if (( EUID == 0 )); then
    SUDO=""
  else
    have sudo || { err "sudo is required (or run as root)."; return 1; }
    SUDO="sudo"
  fi
  return 0
}
run_root() {
  if [[ -n "$SUDO" ]]; then "$SUDO" "$@"; else "$@"; fi
}

# ---------- platform ----------
rf_detect_platform() {
  RF_OS_ID="unknown"; RF_OS_PRETTY="unknown"; RF_ARCH="unknown"; RF_GOARCH="unknown"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    RF_OS_ID="$(. /etc/os-release; printf '%s' "${ID:-unknown}")"
    # shellcheck disable=SC1091
    RF_OS_PRETTY="$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-$RF_OS_ID}")"
  fi
  local m
  m="$(uname -m 2>/dev/null || true)"
  RF_ARCH="$m"
  case "$m" in
    x86_64|amd64)  RF_GOARCH="amd64" ;;
    aarch64|arm64) RF_GOARCH="arm64" ;;
    *)             RF_GOARCH="" ;;
  esac
  return 0
}

rf_require_debian() {
  [[ -r /etc/os-release ]] || { err "Cannot identify the Linux distribution (missing /etc/os-release). Supported: Kali/Debian-based."; return 1; }
  case "$RF_OS_ID" in
    kali|debian|ubuntu|parrot) ;;
    *) warn "Detected ${RF_OS_PRETTY}. Designed for Kali/Debian-based systems — continuing anyway." ;;
  esac
  have apt-get || { err "apt-get not found. This installer supports Kali/Debian-based systems only."; return 1; }
  case "$RF_GOARCH" in
    amd64|arm64) ;;
    *) err "Unsupported architecture: ${RF_ARCH:-unknown}. Supported: amd64 (x86_64), arm64 (aarch64)."; return 1 ;;
  esac
  rf_setup_sudo || return 1
  return 0
}

# ---------- generic helpers ----------
have() { command -v "$1" >/dev/null 2>&1; }

# version_ge <have> <need>  → true when have >= need
version_ge() {
  # min(have, need) == need  ⟺  have >= need
  [[ "$2" == "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" ]]
}

# ---------- language runtime probes ----------
rf_py_version() {
  python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || true
}

# venv needs a working ensurepip (Debian ships it in python3-venv).
rf_python_venv_ok() {
  python3 -m ensurepip --version >/dev/null 2>&1
}

# rf_confirm <message> [y|n] — -y/--yes and non-interactive default to "no"
rf_confirm() {
  local msg="$1" def="${2:-n}" ans
  (( RF_ASSUME_YES )) && return 0
  [[ -t 0 ]] || return 1
  local hint="[y/N]"
  [[ "$def" == "y" ]] && hint="[Y/n]"
  read -r -p "$msg $hint " ans || return 1
  [[ -z "$ans" ]] && ans="$def"
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# rf_confirm_strict — requires typing the word "yes"; --yes never bypasses it
rf_confirm_strict() {
  local msg="$1" ans
  (( RF_ASSUME_YES )) && return 1
  [[ -t 0 ]] || return 1
  read -r -p "$msg Type 'yes' to continue: " ans || return 1
  [[ "$ans" == "yes" ]]
}

# rf_fetch <url> <dest> [expected_sha256] — download with retries + checksum
rf_fetch() {
  local url="$1" dest="$2" sha="${3:-}"
  log "Downloading $(basename "$dest") ..."
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$dest" "$url" \
    || { err "Download failed: $url"; return 1; }
  if [[ -n "$sha" ]]; then
    if printf '%s  %s\n' "$sha" "$dest" | sha256sum -c - >/dev/null 2>&1; then
      ok "SHA256 verified: $(basename "$dest")"
    else
      err "SHA256 mismatch for $dest (expected: $sha) — file removed."
      rm -f "$dest"
      return 1
    fi
  fi
}

# ---------- parallel runner ----------
# rf_run_parallel <function> <jobs> <item...>
# Each item runs as "$function <item>" in the background; results are
# communicated by the function itself (result files), not exit codes.
rf_run_parallel() {
  local fn="$1" jobs="$2"; shift 2
  local item running=0
  if (( jobs <= 1 )) || (( $# <= 1 )); then
    for item in "$@"; do "$fn" "$item"; done
    return 0
  fi
  for item in "$@"; do
    "$fn" "$item" &
    running=$((running + 1))
    if (( running >= jobs )); then
      wait -n 2>/dev/null || true
      running=$((running - 1))
    fi
  done
  wait 2>/dev/null || true
  return 0
}

# ---------- persistent PATH block for bash/zsh ----------
rf_write_path_rc() {
  local rc marker="# >>> reconforge toolkit >>>"
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -e "$rc" ]] || touch "$rc"
    grep -Fq "$marker" "$rc" && continue
    {
      printf '\n%s\n' "$marker"
      printf 'export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$HOME/.local/go-reconforge/bin:$PATH"\n'
      printf '# <<< reconforge toolkit <<<\n'
    } >> "$rc"
    ok "PATH block added to $(basename "$rc")"
  done
  return 0
}
