#!/usr/bin/env bash
# Bug Bounty Recon & Enumeration tools installer
# Target: Kali Linux / Debian-based systems (amd64 or arm64)
# Default: CLI tools. Optional: --gui (Burp Suite + Postman when snap exists)
#          --wordlists (SecLists)

set -Eeuo pipefail

SCRIPT_NAME="${0##*/}"
GO_MIN_VERSION="1.26.10"
LOCAL_BIN="${HOME}/.local/bin"
TOOLS_DIR="${HOME}/tools/recon"
VENV_DIR="${HOME}/.venvs/recon-tools"
GOPATH_DIR="${HOME}/go"
GOBIN_DIR="${LOCAL_BIN}"
INSTALL_GUI=0
INSTALL_WORDLISTS=0

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { printf "${BLUE}[*]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*" >&2; }
err()  { printf "${RED}[-]${NC} %s\n" "$*" >&2; }

usage() {
  cat <<USAGE
Usage: bash ${SCRIPT_NAME} [options]

Options:
  --gui         Also install Burp Suite. Postman is installed only if snap is available.
  --wordlists   Install SecLists (large download).
  -h, --help    Show this help.

Default installation covers CLI recon/enumeration tools only.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --gui) INSTALL_GUI=1 ;;
    --wordlists) INSTALL_WORDLISTS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $arg"; usage; exit 2 ;;
  esac
done

if [[ "${EUID}" -eq 0 ]]; then
  SUDO=""
else
  command -v sudo >/dev/null 2>&1 || { err "sudo is required. Install sudo or run as root."; exit 1; }
  SUDO="sudo"
fi

run_root() {
  if [[ -n "$SUDO" ]]; then "$SUDO" "$@"; else "$@"; fi
}

if [[ ! -r /etc/os-release ]]; then
  err "Cannot identify Linux distribution. This installer supports Kali/Debian-based Linux."
  exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  kali|debian|ubuntu|parrot) ;;
  *) warn "Detected ${PRETTY_NAME:-unknown}. Proceeding, but this script is designed for Kali/Debian-based systems." ;;
esac

ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
case "$ARCH" in
  amd64) GOARCH="amd64" ;;
  arm64) GOARCH="arm64" ;;
  *) err "Unsupported architecture: ${ARCH:-unknown}. Supported: amd64, arm64."; exit 1 ;;
esac

mkdir -p "$LOCAL_BIN" "$TOOLS_DIR" "$VENV_DIR" "$GOBIN_DIR" "$GOPATH_DIR"
export GOPATH="$GOPATH_DIR"
export GOBIN="$GOBIN_DIR"
export PATH="${LOCAL_BIN}:${GOBIN_DIR}:${PATH}"

log "Updating package indexes and installing prerequisites..."
run_root apt-get update
run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl wget git jq make build-essential pkg-config \
  python3 python3-venv python3-pip pipx \
  dnsutils libpcap-dev libssl-dev libffi-dev unzip tar xz-utils

# Compare dotted numeric versions without relying on non-POSIX version sort.
version_ge() {
  local have="$1" need="$2" first
  first="$(printf '%s\n%s\n' "$need" "$have" | sort -V | head -n1)"
  [[ "$first" == "$need" ]]
}

install_or_update_go() {
  local current="" go_json go_file go_sha tmpdir archive
  if command -v go >/dev/null 2>&1; then
    current="$(go version | awk '{print $3}' | sed 's/^go//')"
  fi

  if [[ -n "$current" ]] && version_ge "$current" "$GO_MIN_VERSION"; then
    ok "Go ${current} is available (minimum for current ProjectDiscovery builds: ${GO_MIN_VERSION})."
    return
  fi

  if [[ -n "$current" ]]; then
    warn "Go ${current} is older than ${GO_MIN_VERSION}; installing the latest stable Go from go.dev."
  else
    log "Installing the latest stable Go from go.dev..."
  fi

  go_json="$(mktemp)"
  curl -fsSL 'https://go.dev/dl/?mode=json' -o "$go_json"
  read -r _ go_file go_sha < <(
    jq -r --arg arch "$GOARCH" \
      '.[0] as $v | $v.files[] | select(.os == "linux" and .arch == $arch and .kind == "archive") | [$v.version, .filename, .sha256] | @tsv' \
      "$go_json"
  )
  rm -f "$go_json"
  [[ -n "${go_file:-}" && -n "${go_sha:-}" ]] || { err "Could not determine the latest Go archive for linux/${GOARCH}."; return 1; }

  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/${go_file}"
  curl -fL "https://go.dev/dl/${go_file}" -o "$archive"
  printf '%s  %s\n' "$go_sha" "$archive" | sha256sum -c -
  run_root rm -rf /usr/local/go
  run_root tar -C /usr/local -xzf "$archive"
  rm -rf "$tmpdir"
  export PATH="/usr/local/go/bin:${PATH}"
  command -v go >/dev/null 2>&1 || { err "Go installation failed."; return 1; }
  ok "Installed $(/usr/local/go/bin/go version)."
}

install_go_tool() {
  local package="$1" binary="${2:-}"
  log "Installing Go tool: ${package}"
  if go install "$package"; then
    if [[ -n "$binary" && -x "${GOBIN}/${binary}" ]]; then
      ok "Installed ${binary}."
    else
      ok "Installed $(basename "${package%@*}")."
    fi
  else
    warn "Could not install ${package}; continuing with the remaining tools."
  fi
}

clone_or_update() {
  local repo="$1" dest="$2"
  if [[ -d "${dest}/.git" ]]; then
    git -C "$dest" pull --ff-only || warn "Could not update ${dest}; keeping the existing checkout."
  else
    git clone --depth 1 "$repo" "$dest" || { warn "Clone failed: ${repo}"; return 1; }
  fi
}

make_venv() {
  local name="$1" venv="${VENV_DIR}/${name}"
  if [[ ! -x "${venv}/bin/python" ]]; then
    python3 -m venv "$venv" || { warn "Could not create Python venv: ${name}"; return 1; }
  fi
  "${venv}/bin/python" -m pip install --upgrade pip wheel setuptools >/dev/null || warn "Could not upgrade pip in ${name}."
  printf '%s' "$venv"
}

install_python_repo() {
  local name="$1" repo="$2" folder="$3" dest="${TOOLS_DIR}/${folder}" venv
  clone_or_update "$repo" "$dest" || return 1
  venv="$(make_venv "$name")" || return 1

  if [[ -f "${dest}/requirements.txt" ]]; then
    "${venv}/bin/python" -m pip install -r "${dest}/requirements.txt" || warn "Some requirements failed for ${name}."
  fi
  if [[ -f "${dest}/pyproject.toml" || -f "${dest}/setup.py" ]]; then
    "${venv}/bin/python" -m pip install "$dest" || warn "Package install failed for ${name}; source remains in ${dest}."
  fi
  ok "Prepared ${name} in ${dest}"
}

write_python_launcher() {
  local name="$1" venv_name="$2" script_path="$3"
  cat > "${LOCAL_BIN}/${name}" <<LAUNCHER
#!/usr/bin/env bash
exec "${VENV_DIR}/${venv_name}/bin/python" "${script_path}" "\$@"
LAUNCHER
  chmod +x "${LOCAL_BIN}/${name}"
}

log "Ensuring a recent Go toolchain..."
install_or_update_go
export PATH="/usr/local/go/bin:${LOCAL_BIN}:${GOBIN_DIR}:${PATH}"

log "Installing Go-based reconnaissance tools..."
install_go_tool 'github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest' subfinder
install_go_tool 'github.com/projectdiscovery/dnsx/cmd/dnsx@latest' dnsx
install_go_tool 'github.com/projectdiscovery/httpx/cmd/httpx@latest' httpx
install_go_tool 'github.com/projectdiscovery/katana/cmd/katana@latest' katana
install_go_tool 'github.com/projectdiscovery/shuffledns/cmd/shuffledns@latest' shuffledns
install_go_tool 'github.com/ffuf/ffuf/v2@latest' ffuf
install_go_tool 'github.com/lc/gau/v2/cmd/gau@latest' gau
install_go_tool 'github.com/tomnomnom/waybackurls@latest' waybackurls
install_go_tool 'github.com/hakluke/hakrawler@latest' hakrawler
install_go_tool 'github.com/lc/subjs@latest' subjs
install_go_tool 'github.com/jaeles-project/gospider@latest' gospider
install_go_tool 'github.com/tomnomnom/httprobe@latest' httprobe
install_go_tool 'github.com/tomnomnom/gf@latest' gf
install_go_tool 'github.com/gwen001/github-subdomains@latest' github-subdomains
install_go_tool 'github.com/sa7mon/s3scanner@latest' s3scanner
install_go_tool 'github.com/tomnomnom/anew@latest' anew

# Current Censys Platform CLI is named "censys" after installation.
log "Installing Censys Platform CLI..."
if go install github.com/censys/cencli/cmd/cencli@latest; then
  if [[ -x "${GOBIN}/cencli" ]]; then mv -f "${GOBIN}/cencli" "${GOBIN}/censys"; fi
  ok "Censys CLI installed as 'censys'. Configure it later with: censys config auth add"
else
  warn "Censys CLI installation failed; install it later from https://github.com/censys/cencli"
fi

log "Installing Kali/Debian packaged tools..."
for pkg in amass massdns feroxbuster; do
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" || warn "APT install failed for ${pkg}."
  else
    warn "Package '${pkg}' is not available in the configured APT repositories."
  fi
done

# MassDNS: build from its upstream source if APT did not provide the binary.
if ! command -v massdns >/dev/null 2>&1; then
  log "Building MassDNS from upstream source..."
  MASSDNS_DIR="${TOOLS_DIR}/massdns"
  if clone_or_update 'https://github.com/blechschmidt/massdns.git' "$MASSDNS_DIR"; then
    if make -C "$MASSDNS_DIR"; then
      if [[ -x "${MASSDNS_DIR}/bin/massdns" ]]; then
        install -m 0755 "${MASSDNS_DIR}/bin/massdns" "${LOCAL_BIN}/massdns"
        ok "MassDNS installed to ${LOCAL_BIN}/massdns"
      else
        warn "MassDNS build completed but expected binary was not found."
      fi
    else
      warn "MassDNS build failed."
    fi
  fi
fi

log "Installing Python tools in isolated virtual environments..."
# Pipx applications
pipx ensurepath >/dev/null 2>&1 || true
if ! pipx list 2>/dev/null | grep -q 'package arjun'; then pipx install arjun || warn "Arjun install failed."; else ok "Arjun already installed via pipx."; fi
if ! pipx list 2>/dev/null | grep -q 'package shodan'; then pipx install shodan || warn "Shodan CLI install failed."; else ok "Shodan CLI already installed via pipx."; fi

# Dirsearch via an isolated pipx environment from the maintained upstream source.
if ! command -v dirsearch >/dev/null 2>&1; then
  pipx install 'git+https://github.com/maurosoria/dirsearch.git' || warn "Dirsearch install failed."
else
  ok "dirsearch command already exists; leaving it unchanged."
fi

# Python repositories. Each has its own venv to avoid dependency collisions.
if install_python_repo linkfinder 'https://github.com/GerbenJavado/LinkFinder.git' 'LinkFinder'; then
  write_python_launcher linkfinder linkfinder "${TOOLS_DIR}/LinkFinder/linkfinder.py"
fi

if install_python_repo jsfinder 'https://github.com/Threezh1/JSFinder.git' 'JSFinder'; then
  if [[ -f "${TOOLS_DIR}/JSFinder/JSFinder.py" ]]; then
    write_python_launcher jsfinder jsfinder "${TOOLS_DIR}/JSFinder/JSFinder.py"
  else
    warn "JSFinder checkout found, but JSFinder.py was not found; inspect ${TOOLS_DIR}/JSFinder."
  fi
fi

if install_python_repo gitdorker 'https://github.com/obheda12/GitDorker.git' 'GitDorker'; then
  write_python_launcher gitdorker gitdorker "${TOOLS_DIR}/GitDorker/GitDorker.py"
fi

if install_python_repo paramspider 'https://github.com/devanshbatham/ParamSpider.git' 'ParamSpider'; then
  if [[ -f "${TOOLS_DIR}/ParamSpider/paramspider.py" ]]; then
    write_python_launcher paramspider paramspider "${TOOLS_DIR}/ParamSpider/paramspider.py"
  else
    warn "ParamSpider source cloned; inspect ${TOOLS_DIR}/ParamSpider for its current entry point."
  fi
fi

if install_python_repo cloud_enum 'https://github.com/initstring/cloud_enum.git' 'cloud_enum'; then
  if [[ -x "${VENV_DIR}/cloud_enum/bin/cloud_enum" ]]; then
    ln -sf "${VENV_DIR}/cloud_enum/bin/cloud_enum" "${LOCAL_BIN}/cloud_enum"
  fi
fi

# SubBrute is kept as a source checkout because forks expose different CLIs.
if clone_or_update 'https://github.com/TheRook/subbrute.git' "${TOOLS_DIR}/SubBrute"; then
  if [[ -f "${TOOLS_DIR}/SubBrute/subbrute.py" ]]; then
    cat > "${LOCAL_BIN}/subbrute.py" <<LAUNCHER
#!/usr/bin/env bash
exec python3 "${TOOLS_DIR}/SubBrute/subbrute.py" "\$@"
LAUNCHER
    chmod +x "${LOCAL_BIN}/subbrute.py"
  fi
fi

# Install GF community patterns.
log "Installing GF pattern collection..."
GF_PATTERNS_DIR="${TOOLS_DIR}/Gf-Patterns"
if clone_or_update 'https://github.com/1ndianl33t/Gf-Patterns.git' "$GF_PATTERNS_DIR"; then
  mkdir -p "${HOME}/.gf"
  find "$GF_PATTERNS_DIR" -type f -name '*.json' -exec cp -f {} "${HOME}/.gf/" \;
  ok "GF patterns copied to ${HOME}/.gf"
fi

# Kiterunner is built using its upstream Makefile.
log "Building Kiterunner..."
KITERUNNER_DIR="${TOOLS_DIR}/kiterunner"
if clone_or_update 'https://github.com/assetnote/kiterunner.git' "$KITERUNNER_DIR"; then
  if make -C "$KITERUNNER_DIR" build; then
    if [[ -x "${KITERUNNER_DIR}/dist/kr" ]]; then
      install -m 0755 "${KITERUNNER_DIR}/dist/kr" "${LOCAL_BIN}/kr"
      ok "Kiterunner installed to ${LOCAL_BIN}/kr"
    else
      warn "Kiterunner build completed but dist/kr was not found."
    fi
  else
    warn "Kiterunner build failed; source remains in ${KITERUNNER_DIR}."
  fi
fi

# AWS CLI v2 official installer.
if ! command -v aws >/dev/null 2>&1; then
  log "Installing AWS CLI v2 using AWS's official Linux installer..."
  curl -fsSL https://awscli.amazonaws.com/v2/install.sh -o /tmp/awscli-install.sh
  run_root bash /tmp/awscli-install.sh --system || warn "AWS CLI install failed."
  rm -f /tmp/awscli-install.sh
else
  ok "AWS CLI already available: $(aws --version 2>&1 | head -n1)"
fi

# Optional GUI applications.
if [[ "$INSTALL_GUI" -eq 1 ]]; then
  log "Installing Burp Suite Community from Kali/Debian repositories..."
  if apt-cache show burpsuite >/dev/null 2>&1; then
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y burpsuite || warn "Burp Suite install failed."
  else
    warn "Burp Suite package is unavailable in the configured repositories."
  fi
  if command -v snap >/dev/null 2>&1; then
    run_root snap install postman || warn "Postman snap installation failed."
  else
    warn "Postman was not installed: snap is not available. Install Postman from https://www.postman.com/downloads/ or enable snapd first."
  fi
fi

# Optional SecLists download from Kali repositories.
if [[ "$INSTALL_WORDLISTS" -eq 1 ]]; then
  log "Installing SecLists wordlists (large package)..."
  if apt-cache show seclists >/dev/null 2>&1; then
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y seclists || warn "SecLists installation failed."
  else
    warn "SecLists package is unavailable in configured APT repositories."
  fi
fi

# Persist user-local binary paths in common shells.
for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
  [[ -e "$rc" ]] || touch "$rc"
  if ! grep -Fq 'export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"' "$rc"; then
    printf '\n# Bug Bounty recon tools\nexport PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"\n' >> "$rc"
  fi
done

printf '\n'
ok "Installation routine finished."
echo "Tools directory : ${TOOLS_DIR}"
echo "Local binaries  : ${LOCAL_BIN}"
echo "Go binaries     : ${GOBIN_DIR}"
echo "Python venvs    : ${VENV_DIR}"
echo
log "Refresh your shell, then verify commands:"
echo "  source ~/.zshrc   # or: source ~/.bashrc"
echo "  subfinder -version"
echo "  dnsx -h"
echo "  httpx -version"
echo "  katana -h"
echo "  ffuf -V"
echo "  massdns -h"
echo "  kr -h"
echo "  cloud_enum -h"
echo
warn "Not installed automatically: crt.sh and Google dorking are web services/search techniques, not local tools. API-backed tools need your own tokens."
warn "AWSBucketDump is intentionally excluded: it is a legacy bulk object downloader; use approved, minimal, non-destructive cloud permission checks instead."
warn "Review each tool's current help output. Only run active discovery against assets explicitly authorized by the relevant Bug Bounty program."
