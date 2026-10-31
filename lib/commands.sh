#!/usr/bin/env bash
# ============================================================
# ReconForge — lib/commands.sh
# Command implementations: install, update, check, list,
# remove, doctor, setup — plus the shared plan/report logic.
# ============================================================

[[ -n "${RF_COMMANDS_SH:-}" ]] && return 0
RF_COMMANDS_SH=1

RF_SEL_CATS=()
RF_SEL_TOOLS=""
RF_MENU_SEL=()
RF_PLAN=()
RF_ACT=()

# ---------------- usage ----------------
rf_usage_install() {
  cat <<'USAGE'
Usage: reconforge install [options]     (update accepts the same options)

Selection:
  --all              All tool categories except wordlists & GUI (opt in separately)
  --only LIST        Comma-separated categories:
                     subdomain,web,archive,js,params,content,exploit,cloud,osint,wordlists,gui
  --tools LIST       Comma-separated tool names (e.g. subfinder,ffuf)
  --gui              Add the GUI category (Burp Suite, Postman)
  --wordlists        Add the wordlists category
  (no options)       Interactive category menu (run in a terminal)

Behaviour:
  --dry-run          Show the plan without changing anything
  --jobs N           Parallel installation workers (default: 4)
  --force            Reinstall even if tools are already present
  --no-deps         Skip the language/dependency check
  -y, --yes          Assume yes for confirmations
  -h, --help         This help
USAGE
}

rf_usage() {
  cat <<'USAGE'
RECONFORGE — Advanced Reconnaissance Toolkit Manager

Usage: reconforge <command> [options]

Commands:
  install      Install tools — interactive menu by default (same flags as update)
  update       Update tools to their latest versions
  check        Show per-tool status (installed / missing + versions)
  list         List every tool by category
  remove       Remove tools:  remove <tool...> | --category <id> | all
  doctor       Diagnose prerequisites, PATH, state and logs
  setup        Install the 'reconforge' command into ~/.local/bin
  version      Print version

install / update options:
  --all            All tool categories except wordlists & GUI (opt in separately)
  --only LIST      Categories: subdomain,web,archive,js,params,content,exploit,cloud,osint,wordlists,gui
  --tools LIST     Specific tools, e.g. --tools subfinder,httpx
  --gui            Include GUI tools (Burp Suite, Postman)
  --wordlists      Include wordlists (SecLists, GF patterns)
  --dry-run        Preview the plan without changing anything
  --jobs N         Parallel installation workers (default 4)
  --force          Reinstall even when the tool already exists
  --no-deps        Skip the language/dependency check
  -y, --yes        Assume yes for confirmations
  -h, --help       Help

Examples:
  reconforge install                  # interactive menu
  reconforge install --all --dry-run  # preview everything first
  reconforge install --tools subfinder,httpx
  reconforge update --only subdomain,web
  reconforge check
  reconforge remove --category cloud
  reconforge doctor

Security notes:
  - Go archives are verified against go.dev SHA256 checksums.
  - Go managed by the system (not reconforge) is never replaced or
    removed without an explicit typed confirmation.
  - Every run writes a full log under ~/.local/state/reconforge/logs/.
USAGE
}

# ---------------- command wrappers ----------------
rf_cmd_install() { rf_install_cmd_common install "$@"; }
rf_cmd_update()  { rf_install_cmd_common update "$@"; }

# ---------------- shared option parsing (install/update) ----------------
rf_install_cmd_common() {
  local verb="$1"; shift
  local all=0 gui=0 wl=0 only="" toolsel="" c
  local -a cats=()

  while (( $# )); do
    case "$1" in
      --all) all=1 ;;
      --gui) gui=1 ;;
      --wordlists) wl=1 ;;
      --only) only="${2:-}"; shift ;;
      --tools) toolsel="${2:-}"; shift ;;
      --dry-run) RF_DRY_RUN=1 ;;
      --jobs) RF_JOBS="${2:-}"; shift ;;
      --force|-f) RF_FORCE=1 ;;
      --no-deps) RF_NO_DEPS=1 ;;
      -y|--yes) RF_ASSUME_YES=1 ;;
      -h|--help) rf_usage_install; return 0 ;;
      *) err "Unknown option: $1"; rf_usage_install; return 2 ;;
    esac
    shift
  done
  [[ "$RF_JOBS" =~ ^[1-9][0-9]*$ ]] || { err "--jobs expects a positive number (got: '$RF_JOBS')"; return 2; }
  [[ "$verb" == "update" ]] && RF_FORCE=1

  RF_SEL_TOOLS=""
  RF_SEL_CATS=()
  if [[ -n "$toolsel" ]]; then
    RF_SEL_TOOLS="$toolsel"
  else
    if (( all )); then
      cats+=(subdomain web archive js params content exploit cloud osint)
    fi
    (( wl )) && cats+=(wordlists)
    (( gui )) && cats+=(gui)
    if [[ -n "$only" ]]; then
      cats=()
      IFS=',' read -r -a cats <<< "$only"
    fi
    if (( ${#cats[@]} == 0 )) && { [[ -t 0 ]] || [[ -n "${RF_FORCE_MENU:-}" ]]; }; then
      rf_banner
      rf_menu_select || { warn "Cancelled — nothing selected."; return 1; }
      cats=("${RF_MENU_SEL[@]}")
    fi
    if (( ${#cats[@]} == 0 )); then
      err "No categories selected."
      err "Use --all / --only / --tools, or run inside a terminal to get the interactive menu."
      return 2
    fi
    local -a uniq=()
    for c in "${cats[@]}"; do
      c="${c//[[:space:]]/}"
      rf_valid_cat "$c" \
        || { err "Unknown category: '$c' (valid: ${RF_MOD_ID[*]})"; return 2; }
      [[ " ${uniq[*]-} " == *" $c "* ]] || uniq+=("$c")
    done
    RF_SEL_CATS=("${uniq[@]}")
  fi

  rf_install_core "$verb"
}

# ---------------- install/update core ----------------
rf_install_core() {
  local verb="$1"
  # Populate RF_OS_* / RF_ARCH / RF_GOARCH — rf_require_debian and the
  # header line below depend on these being set.
  rf_detect_platform
  local -a plan=()
  local t i

  if [[ -n "$RF_SEL_TOOLS" ]]; then
    local -a tarr=()
    IFS=',' read -r -a tarr <<< "$RF_SEL_TOOLS"
    for t in "${tarr[@]}"; do
      t="${t//[[:space:]]/}"
      [[ -z "$t" ]] && continue
      rf_tool_index "$t" >/dev/null 2>&1 || { err "Unknown tool: $t"; return 2; }
      plan+=("$t")
    done
  else
    local c
    for c in "${RF_SEL_CATS[@]}"; do
      while IFS= read -r t; do
        [[ -n "$t" ]] && plan+=("$t")
      done < <(rf_cat_tools "$c")
    done
  fi
  if (( ${#plan[@]} == 0 )); then
    err "Nothing to $verb."
    return 2
  fi
  RF_PLAN=("${plan[@]}")

  rf_log_init "$verb"
  printf '\n'
  log "reconforge $verb — ${RF_OS_PRETTY:-unknown} (${RF_ARCH:-?}, go:${RF_GOARCH:-?}) | jobs=$RF_JOBS | force=$RF_FORCE"

  # ---- statuses → actions (smart installation) ----
  RF_ACT=()
  local st
  for t in "${RF_PLAN[@]}"; do
    st="$(rf_tool_status "$t" noverify)" || true
    st="${st%%$'\t'*}"
    if [[ "$st" == "installed" ]] && (( RF_FORCE == 0 )); then
      RF_ACT+=("skip")
    else
      RF_ACT+=("do")
    fi
  done

  # ---- dry run ----
  if (( RF_DRY_RUN )); then
    local n_do=0 n_skip=0 idx
    for i in "${!RF_PLAN[@]}"; do
      if [[ "${RF_ACT[i]}" == "skip" ]]; then n_skip=$((n_skip + 1)); else n_do=$((n_do + 1)); fi
    done
    printf '\n  %sDry-run plan%s — nothing will be touched.\n\n' "$BOLD" "$NC"
    printf '  %-22s %-13s %s\n' "TOOL" "CATEGORY" "ACTION"
    rf_hr
    for i in "${!RF_PLAN[@]}"; do
      t="${RF_PLAN[i]}"
      idx="$(rf_tool_index "$t")"
      if [[ "${RF_ACT[i]}" == "skip" ]]; then
        printf '  %-22s %-13s %s\n' "$t" "${RF_T_CAT[idx]}" "skip (already installed)"
      else
        local act="install"
        [[ "$verb" == "update" ]] && act="update"
        printf '  %-22s %-13s %s\n' "$t" "${RF_T_CAT[idx]}" "$act"
      fi
    done
    rf_hr
    printf '  To %s: %d   Already installed (skipped): %d\n\n' "$verb" "$n_do" "$n_skip"
    # Runtime & dependency plan — read-only reporting (Debian-based systems only).
    if [[ -r /etc/os-release ]] && have apt-get; then
      (( RF_NO_DEPS == 0 )) && rf_preflight_deps
      rf_ensure_go
    else
      log "Dependency/runtime check skipped — not a Debian-based system."
    fi
    log "Dry-run complete. Re-run without --dry-run to apply."
    return 0
  fi

  # ---- real run: platform + dependencies/runtimes ----
  rf_require_debian || return 1
  if (( RF_NO_DEPS == 0 )); then
    rf_preflight_deps \
      || { err "Dependency check failed — aborting. (Re-run with --no-deps to skip this step.)"; return 1; }
  else
    warn "Skipping the dependency/runtime check (--no-deps)."
  fi

  rf_ensure_go \
    || warn "Go setup failed — Go-based tools will fail individually; everything else continues."

  export GOPATH="$RF_GOPATH_DIR" GOBIN="$RF_GOBIN_DIR"
  export PATH="$RF_LOCAL_BIN:$RF_GOBIN_DIR:/usr/local/go/bin:${HOME}/.local/go-reconforge/bin:$PATH"
  mkdir -p "$RF_LOCAL_BIN" "$RF_TOOLS_DIR" "$RF_VENV_DIR" "$RF_GOBIN_DIR" "$RF_GOPATH_DIR"
  hash -r

  RF_TMP_DIR="$(mktemp -d "$RF_STATE_ROOT/tmp.XXXXXX")"
  : > "$RF_TMP_DIR/done.list"
  : > "$RF_TMP_DIR/fail.list"

  # ---- split: apt/snap sequential (package locks), the rest parallel ----
  local -a seq=() par=()
  for i in "${!RF_PLAN[@]}"; do
    [[ "${RF_ACT[i]}" == "skip" ]] && continue
    t="${RF_PLAN[i]}"
    case "$(rf_tool_field "$t" type)" in
      apt|snap) seq+=("$t") ;;
      *)        par+=("$t") ;;
    esac
  done

  printf '\n'
  log "Installing $(( ${#seq[@]} + ${#par[@]} )) tool(s): ${#par[@]} parallel (jobs=$RF_JOBS) + ${#seq[@]} apt/snap sequential."
  printf '\n'

  for t in "${seq[@]}"; do rf_install_one "$t"; done
  if (( ${#par[@]} > 0 )); then
    rf_run_parallel rf_install_one "$RF_JOBS" "${par[@]}"
  fi

  local rc=0
  rf_install_report "$verb" || rc=1

  rm -rf "$RF_TMP_DIR"
  RF_TMP_DIR=""
  rf_write_path_rc

  printf '\n'
  ok "reconforge $verb finished."
  printf '  Log   : %s\n' "$RF_LOG_FILE"
  printf '  State : %s\n' "$RF_STATE_FILE"
  printf '  Next  : open a new shell (or: source ~/.bashrc), then run: reconforge check\n'
  return $rc
}

rf_install_one() { # worker — used for both sequential and parallel runs
  local name="$1"
  log "Installing $name ..."
  if rf_do_install "$name" >>"$RF_LOG_FILE" 2>&1; then
    printf '%s\n' "$name" >> "$RF_TMP_DIR/done.list"
    ok "$name — done"
  else
    printf '%s\n' "$name" >> "$RF_TMP_DIR/fail.list"
    err "$name — FAILED (details in the run log)"
  fi
  return 0
}

# ---------------- smart dependency / language-runtime check ----------------
RF_APT_NEED=()

rf_need_cmd() { # <probe-cmd> <apt-pkg...> — probe missing → queue packages
  have "$1" && return 0
  RF_APT_NEED+=("${@:2}")
}

rf_need_pkg() { # <apt-pkg...> — no command probe; check the dpkg database
  local p
  for p in "$@"; do
    dpkg-query -W -f='${db:Status-Abbrev}' "$p" 2>/dev/null | grep -q '^ii' && continue
    RF_APT_NEED+=("$p")
  done
  return 0
}

# Checks every language/runtime/tool the toolkit needs. Anything already
# present (with a sufficient version) is skipped; only what is missing or
# too old gets installed. Read-only reporting when RF_DRY_RUN=1.
rf_preflight_deps() {
  RF_APT_NEED=()
  log "Checking required languages and dependencies before installing anything..."

  # --- language runtimes ---
  local pyv
  pyv="$(rf_py_version)"
  if [[ -n "$pyv" ]] && version_ge "$pyv" "$RF_PY_MIN_VERSION" && rf_python_venv_ok; then
    ok "Python ${pyv} (+venv) already available (minimum: ${RF_PY_MIN_VERSION})."
  else
    if [[ -n "$pyv" ]]; then
      warn "Python ${pyv} is present but too old or missing venv support (need >= ${RF_PY_MIN_VERSION} + venv)."
    else
      log "Python 3 not found."
    fi
    RF_APT_NEED+=(python3 python3-venv python3-pip)
  fi

  if have pipx; then
    ok "pipx already available."
  else
    log "pipx not found."
    RF_APT_NEED+=(pipx)
  fi

  # Go is verified separately by rf_ensure_go (downloads from go.dev + SHA256).

  # --- build & system tools ---
  if have make && have gcc; then
    ok "Build tools (make/gcc) already available."
  else
    log "Build tools (make/gcc) missing."
    RF_APT_NEED+=(make build-essential pkg-config)
  fi

  rf_need_cmd curl  ca-certificates curl wget
  rf_need_cmd wget  wget
  rf_need_cmd git   git
  rf_need_cmd jq    jq
  rf_need_cmd tar   tar
  rf_need_cmd xz    xz-utils
  rf_need_cmd unzip unzip
  rf_need_cmd dig   dnsutils
  rf_need_pkg libpcap-dev libssl-dev libffi-dev

  # dedup the queue
  local -a uniq=()
  local p
  for p in ${RF_APT_NEED[@]+"${RF_APT_NEED[@]}"}; do
    [[ " ${uniq[*]-} " == *" $p "* ]] || uniq+=("$p")
  done
  RF_APT_NEED=("${uniq[@]}")

  if (( ${#RF_APT_NEED[@]} == 0 )); then
    ok "All languages and dependencies are already present — nothing to install."
    return 0
  fi

  if (( RF_DRY_RUN )); then
    dry "Would install the missing dependencies via apt: ${RF_APT_NEED[*]}"
    return 0
  fi

  log "Installing missing dependencies: ${RF_APT_NEED[*]}"
  run_root apt-get update >>"$RF_LOG_FILE" 2>&1 \
    || { err "apt-get update failed (see log)."; return 1; }
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${RF_APT_NEED[@]}" \
    >>"$RF_LOG_FILE" 2>&1 \
    || { err "Dependency installation failed (see log)."; return 1; }

  # Re-verify the language runtimes after installation.
  pyv="$(rf_py_version)"
  if [[ -n "$pyv" ]] && rf_python_venv_ok; then
    ok "Python ${pyv} (+venv) ready."
  else
    err "Python 3 is still not usable after installation (see log)."
    return 1
  fi
  if have pipx; then
    ok "pipx ready."
  else
    err "pipx is still missing after installation (see log)."
    return 1
  fi
  ok "All languages and dependencies ready."
  return 0
}

rf_install_report() {
  local verb="$1" t idx cat type ver res
  local rc=0 n_done=0 n_skip=0 n_fail=0 n_unver=0 i
  printf '\n  %sResults%s\n' "$BOLD" "$NC"
  printf '  %-22s %s\n' "TOOL" "RESULT"
  rf_hr
  for i in "${!RF_PLAN[@]}"; do
    t="${RF_PLAN[i]}"
    idx="$(rf_tool_index "$t")"
    cat="${RF_T_CAT[idx]}"; type="${RF_T_TYPE[idx]}"
    if grep -Fxq "$t" "$RF_TMP_DIR/fail.list" 2>/dev/null; then
      printf '  %-22s %s\n' "$t" "${RED}FAILED — see log${NC}"
      n_fail=$((n_fail + 1))
    elif [[ "${RF_ACT[i]}" == "skip" ]]; then
      printf '  %-22s %s\n' "$t" "${YELLOW}skipped (already installed)${NC}"
      n_skip=$((n_skip + 1))
    else
      rc=0
      ver="$(rf_run_verify "$t")" || rc=$?
      if (( rc == 1 )); then
        rf_state_add "$t" "$cat" "$type" "unverified"
        printf '  %-22s %s\n' "$t" "${YELLOW}installed, but verify failed${NC}"
        n_unver=$((n_unver + 1))
      else
        rf_state_add "$t" "$cat" "$type" "${ver:--}"
        printf '  %-22s %s\n' "$t" "${GREEN}installed${ver:+ — $ver}${NC}"
        n_done=$((n_done + 1))
      fi
    fi
  done
  rf_hr
  printf '  Installed: %d   Skipped: %d   Unverified: %d   Failed: %d\n' \
    "$n_done" "$n_skip" "$n_unver" "$n_fail"
  if (( n_fail > 0 )); then
    local retry
    retry="$(tr '\n' ',' < "$RF_TMP_DIR/fail.list" | sed 's/,$//')"
    warn "Failed tools: $retry"
    warn "Retry with: reconforge install --tools \"$retry\""
    return 1
  fi
  return 0
}

# ---------------- check ----------------
rf_cmd_check() {
  rf_detect_platform
  printf '\n  %sReconForge tool status%s — %s (%s)\n\n' "$BOLD" "$NC" "$RF_OS_PRETTY" "$RF_ARCH"
  printf '  %-20s %-13s %s\n' "TOOL" "CATEGORY" "STATUS"
  rf_hr
  local i t out st ver man n_ok=0 n_miss=0
  for i in ${RF_T_NAME[@]+"${!RF_T_NAME[@]}"}; do
    t="${RF_T_NAME[i]}"
    out="$(rf_tool_status "$t")" || true
    st="${out%%$'\t'*}"; ver="${out#*$'\t'}"
    man=""
    [[ -n "$(rf_state_row "$t")" ]] && man=" ${BLUE}*${NC}"
    if [[ "$st" == "installed" ]]; then
      printf '  %-20s %-13s %s%s\n' "$t" "${RF_T_CAT[i]}" "${GREEN}Installed ${ver:-(ok)}${NC}" "$man"
      n_ok=$((n_ok + 1))
    else
      printf '  %-20s %-13s %s%s\n' "$t" "${RF_T_CAT[i]}" "${RED}Missing${NC}" "$man"
      n_miss=$((n_miss + 1))
    fi
  done
  rf_hr
  printf '  Installed: %d   Missing: %d   (* = managed by reconforge)\n\n' "$n_ok" "$n_miss"
  (( n_miss > 0 )) && log "Install missing tools: reconforge install  (or --tools <names>)"
  return 0
}

# ---------------- list ----------------
rf_cmd_list() {
  rf_detect_platform
  printf '\n  %sReconForge tools%s (v%s)\n' "$BOLD" "$NC" "$RF_VERSION"
  local m i
  for m in ${RF_MOD_ID[@]+"${!RF_MOD_ID[@]}"}; do
    printf '\n  %s[%d] %s%s\n' "$CYAN" "$((m + 1))" "${RF_MOD_TITLE[m]}" "$NC"
    printf '  %-22s %-11s %s\n' "TOOL" "TYPE" "DESCRIPTION"
    for i in ${RF_T_NAME[@]+"${!RF_T_NAME[@]}"}; do
      [[ "${RF_T_CAT[i]}" == "${RF_MOD_ID[m]}" ]] || continue
      printf '  %-22s %-11s %s\n' "${RF_T_NAME[i]}" "${RF_T_TYPE[i]}" "${RF_T_DESC[i]}"
    done
  done
  printf '\n'
  return 0
}

# ---------------- remove ----------------
rf_cmd_remove() {
  local all=0 cat="" t
  local -a names=() targets=()

  while (( $# )); do
    case "$1" in
      all) all=1 ;;
      --category) cat="${2:-}"; shift ;;
      -y|--yes) RF_ASSUME_YES=1 ;;
      -h|--help)
        printf 'Usage: reconforge remove <tool...> | --category <id> | all [-y]\n'
        printf 'Special: reconforge remove go  (typed confirmation required)\n'
        return 0 ;;
      *) names+=("$1") ;;
    esac
    shift
  done

  rf_detect_platform
  rf_setup_sudo || return 1

  local i
  if (( all )); then
    for i in ${RF_T_NAME[@]+"${!RF_T_NAME[@]}"}; do targets+=("${RF_T_NAME[i]}"); done
  elif [[ -n "$cat" ]]; then
    rf_valid_cat "$cat" || { err "Unknown category: $cat"; return 2; }
    while IFS= read -r t; do [[ -n "$t" ]] && targets+=("$t"); done < <(rf_cat_tools "$cat")
  else
    targets=("${names[@]}")
  fi

  if (( ${#targets[@]} == 0 )); then
    err "Nothing to remove. Usage: reconforge remove <tool...> | --category <id> | all"
    return 2
  fi
  for t in "${targets[@]}"; do
    [[ "$t" == "go" || "$t" == "go-toolchain" ]] && continue
    rf_tool_index "$t" >/dev/null 2>&1 || { err "Unknown tool: $t"; return 2; }
  done

  printf '\n  %sRemoval plan%s:\n' "$BOLD" "$NC"
  printf '    %s\n' "${targets[*]}"
  rf_log_init remove
  if (( RF_ASSUME_YES == 0 )); then
    rf_confirm "Remove the tool(s) listed above?" || { warn "Cancelled."; return 1; }
  fi
  printf '\n'

  local nfail=0
  for t in "${targets[@]}"; do
    log "Removing $t ..."
    rf_remove_tool "$t" || { err "Failed to remove $t."; nfail=$((nfail + 1)); }
  done
  printf '\n'
  if (( nfail == 0 )); then
    ok "Removal finished."
    return 0
  fi
  err "$nfail removal(s) failed — see $RF_LOG_FILE"
  return 1
}

# ---------------- doctor ----------------
rf_cmd_doctor() {
  rf_detect_platform
  local problems=0
  printf '\n  %sReconForge doctor%s (v%s)\n' "$BOLD" "$NC" "$RF_VERSION"
  printf '  OS      : %s\n' "$RF_OS_PRETTY"
  printf '  Arch    : %s (go arch: %s)\n' "$RF_ARCH" "${RF_GOARCH:-n/a}"
  printf '  Kernel  : %s\n' "$(uname -sr 2>/dev/null || echo '?')"

  printf '\n  %sPrerequisites%s\n' "$BOLD" "$NC"
  local p v crit="curl git python3 make gcc" missing_crit=0
  for p in curl git jq python3 pipx make gcc unzip sha256sum timeout apt-get go snap; do
    if have "$p"; then
      v=""
      case "$p" in
        go)      v="$(go version 2>/dev/null | head -n1 | cut -c1-45 || true)" ;;
        snap)    v="$(snap version 2>/dev/null | head -n1 | cut -c1-45 || true)" ;;
        apt-get) v="$(apt-get --version 2>/dev/null | head -n1 | cut -c1-45 || true)" ;;
        *)       v="$("$p" --version 2>/dev/null | head -n1 | cut -c1-45 || true)" ;;
      esac
      printf '  %-12s %sok%s %s\n' "$p" "$GREEN" "$NC" "${v:+— $v}"
    else
      printf '  %-12s %smissing%s\n' "$p" "$RED" "$NC"
      [[ " $crit " == *" $p "* ]] && missing_crit=1
    fi
  done

  printf '\n  %sLanguage runtimes%s\n' "$BOLD" "$NC"
  # Go
  if have go; then
    local gv mgp
    gv="$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//' || true)"
    if [[ -n "$gv" ]] && version_ge "$gv" "$RF_GO_MIN_VERSION"; then
      printf '  %sGo %s >= minimum %s — OK%s\n' "$GREEN" "$gv" "$RF_GO_MIN_VERSION" "$NC"
    else
      printf '  %sGo %s is older than the minimum %s — "reconforge install" handles it.%s\n' \
        "$YELLOW" "${gv:-?}" "$RF_GO_MIN_VERSION" "$NC"
    fi
    mgp="$(rf_go_state_field prefix || true)"
    if [[ -n "$mgp" ]]; then
      printf '  Managed by reconforge at: %s\n' "$mgp"
    else
      printf '  Go is outside reconforge management — it will never be touched without typed confirmation.\n'
    fi
  else
    printf '  %sGo not found — "reconforge install" downloads the latest stable release (SHA256 verified).%s\n' "$YELLOW" "$NC"
  fi
  # Python 3 + venv
  local pv
  if have python3; then
    pv="$(rf_py_version)"
    if [[ -n "$pv" ]] && version_ge "$pv" "$RF_PY_MIN_VERSION" && rf_python_venv_ok; then
      printf '  %sPython %s (+venv) >= minimum %s — OK%s\n' "$GREEN" "$pv" "$RF_PY_MIN_VERSION" "$NC"
    else
      printf '  %sPython is present but old or missing venv support (found: %s) — "reconforge install" repairs it.%s\n' \
        "$YELLOW" "${pv:-not usable}" "$NC"
    fi
  else
    printf '  %sPython 3 not found — "reconforge install" installs it with venv support.%s\n' "$YELLOW" "$NC"
  fi
  # pipx
  if have pipx; then
    printf '  %spipx — OK%s\n' "$GREEN" "$NC"
  else
    printf '  %spipx not found — "reconforge install" installs it.%s\n' "$YELLOW" "$NC"
  fi

  printf '\n  %sShell PATH configuration%s\n' "$BOLD" "$NC"
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]] && grep -Fq '# >>> reconforge toolkit >>>' "$rc"; then
      printf '  %s — %sconfigured%s\n' "$rc" "$GREEN" "$NC"
    else
      printf '  %s — %snot configured%s (fixed automatically by: reconforge install)\n' "$rc" "$YELLOW" "$NC"
    fi
  done

  printf '\n  %sDirectories%s\n' "$BOLD" "$NC"
  local d
  for d in "$RF_LOCAL_BIN" "$RF_TOOLS_DIR" "$RF_VENV_DIR" "$RF_STATE_ROOT" "$RF_GF_DIR"; do
    if [[ -d "$d" ]]; then
      printf '  %s%s  present%s\n' "$GREEN" "$d" "$NC"
    else
      printf '  %s%s  absent%s\n' "$YELLOW" "$d" "$NC"
    fi
  done

  printf '\n  %sReconForge state%s\n' "$BOLD" "$NC"
  if [[ -r "$RF_STATE_FILE" ]]; then
    local total broken=() out name
    total="$(grep -c . "$RF_STATE_FILE" 2>/dev/null || true)"
    while IFS=$'\t' read -r name _rest; do
      [[ -z "$name" ]] && continue
      out="$(rf_tool_status "$name" noverify)" || true
      [[ "${out%%$'\t'*}" == "missing" ]] && broken+=("$name")
    done < "$RF_STATE_FILE"
    printf '  Managed tools recorded: %s\n' "${total:-0}"
    if (( ${#broken[@]} > 0 )); then
      printf '  %sRecorded as installed but now missing:%s %s\n' "$YELLOW" "$NC" "${broken[*]}"
      printf '  Clean them up with: reconforge remove <tool> ...\n'
    fi
  else
    printf '  No state yet — nothing has been installed through reconforge.\n'
  fi

  printf '\n  %sLogs%s\n' "$BOLD" "$NC"
  local latest
  latest="$(ls -1t "$RF_LOG_DIR" 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest" ]]; then
    printf '  Latest: %s/%s\n' "$RF_LOG_DIR" "$latest"
  else
    printf '  No logs yet.\n'
  fi

  printf '\n'
  if (( missing_crit )); then
    err "Doctor: critical prerequisites are missing — run 'reconforge install' first."
    return 1
  fi
  ok "Doctor: no blocking issues found."
  return 0
}

# ---------------- setup (global CLI install) ----------------
rf_cmd_setup() {
  local dest="${HOME}/.local/share/reconforge"
  log "Installing the reconforge CLI to $dest ..."
  mkdir -p "$dest"
  cp -f "$RF_HOME/reconforge" "$dest/reconforge" || { err "Copy failed: reconforge"; return 1; }
  rm -rf "$dest/lib"
  cp -rf "$RF_HOME/lib" "$dest/lib" || { err "Copy failed: lib/"; return 1; }
  chmod +x "$dest/reconforge"
  mkdir -p "$RF_LOCAL_BIN"
  cat > "$RF_LOCAL_BIN/reconforge" <<LAUNCHER
#!/usr/bin/env bash
exec bash "$dest/reconforge" "\$@"
LAUNCHER
  chmod +x "$RF_LOCAL_BIN/reconforge"
  rf_write_path_rc
  ok "reconforge CLI installed globally."
  printf '  Open a new shell (or: source ~/.bashrc) and run: reconforge --help\n'
  return 0
}
