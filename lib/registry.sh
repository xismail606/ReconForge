#!/usr/bin/env bash
# ============================================================
# ReconForge — lib/registry.sh
# Tool registry, per-type install/status/remove handlers,
# and Go toolchain management (with unmanaged-Go protection).
# ============================================================

[[ -n "${RF_REGISTRY_SH:-}" ]] && return 0
RF_REGISTRY_SH=1

# ---------------- registry ----------------
RF_MOD_ID=();   RF_MOD_TITLE=()
RF_T_NAME=();   RF_T_CAT=(); RF_T_TYPE=(); RF_T_DESC=()
RF_T_SPEC=();   RF_T_VERIFY=(); RF_T_BIN=(); RF_T_EXTRA=()

rf_module() { # <id> <title>
  RF_MOD_ID+=("$1"); RF_MOD_TITLE+=("$2")
}

rf_tool() { # <name> <category> <type> <description> <spec> <verify-cmd> [bin] [extra]
  local name="$1" cat="$2" type="$3" desc="$4" spec="$5" verify="$6"
  local bin="${7:-$name}" extra="${8:-}"
  RF_T_NAME+=("$name"); RF_T_CAT+=("$cat"); RF_T_TYPE+=("$type"); RF_T_DESC+=("$desc")
  RF_T_SPEC+=("$spec"); RF_T_VERIFY+=("$verify"); RF_T_BIN+=("$bin"); RF_T_EXTRA+=("$extra")
}

rf_tool_index() {
  local i
  for i in ${RF_T_NAME[@]+"${!RF_T_NAME[@]}"}; do
    [[ "${RF_T_NAME[i]}" == "$1" ]] && { printf '%s' "$i"; return 0; }
  done
  return 1
}

rf_tool_field() { # <name> <cat|type|spec|bin|extra>
  local i
  i="$(rf_tool_index "$1")" || return 1
  case "$2" in
    cat)   printf '%s' "${RF_T_CAT[i]}" ;;
    type)  printf '%s' "${RF_T_TYPE[i]}" ;;
    spec)  printf '%s' "${RF_T_SPEC[i]}" ;;
    bin)   printf '%s' "${RF_T_BIN[i]}" ;;
    extra) printf '%s' "${RF_T_EXTRA[i]}" ;;
  esac
}

rf_valid_cat() {
  local id
  for id in ${RF_MOD_ID[@]+"${RF_MOD_ID[@]}"}; do
    [[ "$id" == "$1" ]] && return 0
  done
  return 1
}

rf_cat_tools() { # <category-id> → tool names, one per line
  local i
  for i in ${RF_T_NAME[@]+"${!RF_T_NAME[@]}"}; do
    [[ "${RF_T_CAT[i]}" == "$1" ]] && printf '%s\n' "${RF_T_NAME[i]}"
  done
  return 0
}

rf_spec_part() { # <spec> <1-based-index> — specs use '|' as separator
  printf '%s' "$1" | awk -v i="$2" -F'|' '{print $i}'
}

# ---------------- state file (TSV) ----------------
rf_state_row() { # <name> → row or empty
  [[ -r "$RF_STATE_FILE" ]] || return 0
  awk -F'\t' -v n="$1" '$1 == n { print; exit }' "$RF_STATE_FILE" 2>/dev/null
}

rf_state_add() { # <name> <category> <type> <version>
  mkdir -p "$RF_STATE_ROOT"
  rf_state_del "$1" 2>/dev/null
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:--}" "$(date '+%F %T')" >> "$RF_STATE_FILE"
}

rf_state_del() { # <name>
  [[ -f "$RF_STATE_FILE" ]] || return 0
  local tmp="$RF_STATE_FILE.tmp"
  awk -F'\t' -v n="$1" '$1 != n' "$RF_STATE_FILE" > "$tmp" && mv -f "$tmp" "$RF_STATE_FILE"
  return 0
}

# ---------------- verification ----------------
# Runs the tool's verify command; prints the first output line (version).
# rc 0 = verified, 1 = verify failed, 2 = unknown tool.
rf_run_verify() {
  local i cmd out
  i="$(rf_tool_index "$1")" || return 2
  cmd="${RF_T_VERIFY[i]}"
  [[ -z "$cmd" ]] && return 0
  if have timeout; then
    out="$(timeout 25 bash -c "$cmd" 2>&1)" || return 1
  else
    out="$(bash -c "$cmd" 2>&1)" || return 1
  fi
  printf '%s' "$(printf '%s\n' "$out" | head -n1 | cut -c1-60)"
  return 0
}

# Prints "<status>\t<version>"; rc 0 = installed, 1 = missing, 2 = unknown.
rf_tool_status() {
  local name="$1" noverify="${2:-}" i bin st="missing" ver="" out
  i="$(rf_tool_index "$name")" || { printf 'unknown\t'; return 2; }
  bin="${RF_T_BIN[i]}"
  case "${RF_T_TYPE[i]}" in
    # Go binaries: only trust the reconforge GOBIN — a same-named tool elsewhere
    # in PATH (e.g. the Python 'httpx' package) must not be reported as ours.
    go)         if [[ -x "$RF_GOBIN_DIR/$bin" ]]; then st="installed"; fi ;;
    apt)        if dpkg-query -W -f='${db:Status-Abbrev}' "$bin" 2>/dev/null | grep -q '^ii'; then st="installed"; fi ;;
    aptorbuild) if have "$bin"; then st="installed"; fi ;;
    pipx)       if [[ -d "$HOME/.local/pipx/venvs/$name" ]] || have "$bin"; then st="installed"; fi ;;
    pysrc|gitraw) if [[ -x "$RF_LOCAL_BIN/$name" ]]; then st="installed"; fi ;;
    gitmake)    if have "$bin" || [[ -x "$RF_LOCAL_BIN/$bin" ]]; then st="installed"; fi ;;
    patterns)   if ls "$RF_GF_DIR"/*.json >/dev/null 2>&1; then st="installed"; fi ;;
    curlscript) if have aws; then st="installed"; fi ;;
    snap)       if have snap && snap list "$bin" >/dev/null 2>&1; then st="installed"; fi ;;
  esac
  if [[ "$st" == "installed" && -z "$noverify" ]]; then
    out="$(rf_run_verify "$name")" || out=""
    ver="$out"
  fi
  printf '%s\t%s\n' "$st" "$ver"
  [[ "$st" == "installed" ]]
}

# ---------------- shared source helpers ----------------
rf_clone_or_update() { # <repo-url> <dest>
  if [[ -d "${2}/.git" ]]; then
    git -C "$2" pull --ff-only || warn "Could not update $2; keeping the existing checkout."
  else
    git clone --depth 1 "$1" "$2" || { err "Clone failed: $1"; return 1; }
  fi
}

rf_make_venv() { # <name> → echoes venv path
  local venv="$RF_VENV_DIR/$1"
  if [[ ! -x "$venv/bin/python" ]]; then
    python3 -m venv "$venv" || { err "Could not create Python venv: $1"; return 1; }
  fi
  "$venv/bin/python" -m pip install --upgrade pip wheel setuptools >/dev/null 2>&1 \
    || warn "Could not upgrade pip inside venv $1."
  printf '%s' "$venv"
}

rf_write_launcher() { # <launcher-name> <python-binary> <script-path>
  local name="$1" py="$2" target="$3"
  mkdir -p "$RF_LOCAL_BIN"
  cat > "$RF_LOCAL_BIN/$name" <<LAUNCHER
#!/usr/bin/env bash
exec "$py" "$target" "\$@"
LAUNCHER
  chmod +x "$RF_LOCAL_BIN/$name"
}

# ---------------- install handlers (one per type) ----------------
rf_inst_go() {
  local i="$1"
  local name="${RF_T_NAME[i]}" bin="${RF_T_BIN[i]}" spec="${RF_T_SPEC[i]}" extra="${RF_T_EXTRA[i]}"
  local rename="" hook=""
  if [[ "$extra" == post:* ]]; then hook="${extra#post:}"; else rename="$extra"; fi
  have go || { err "Go toolchain not found."; return 1; }
  log "go install $spec"
  go install "$spec" || { err "go install failed: $spec"; return 1; }
  if [[ -x "$RF_GOBIN_DIR/$bin" ]]; then
    ok "Installed $bin."
  elif [[ -n "$rename" && -x "$RF_GOBIN_DIR/$rename" ]]; then
    mv -f "$RF_GOBIN_DIR/$rename" "$RF_GOBIN_DIR/$bin" && ok "Installed $bin (from $rename)."
  else
    err "Expected binary '$bin' was not produced by: $spec"
    return 1
  fi
  if [[ -n "$hook" ]]; then
    if declare -F "$hook" >/dev/null 2>&1; then
      "$hook" || true
    else
      warn "Post-install hook '$hook' is not defined (bug — please report)."
    fi
  fi
}

rf_inst_apt() {
  local i="$1"
  local pkg="${RF_T_BIN[i]}" extra="${RF_T_EXTRA[i]}"
  apt-cache show "$pkg" >/dev/null 2>&1 \
    || { err "Package '$pkg' is not available in the configured APT repositories."; return 1; }
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >>"$RF_LOG_FILE" 2>&1 \
    || { err "apt install failed: $pkg"; return 1; }
  if [[ "$extra" == dir:* ]]; then
    local d="${extra#dir:}"
    if [[ -d "$d" ]]; then ok "Installed $pkg ($d present)."
    else warn "$pkg installed but $d is missing."; fi
  else
    ok "Installed $pkg (apt)."
  fi
}

# spec: apt-pkg|repo-url|folder|binary-relpath|install-name
rf_inst_aptorbuild() {
  local i="$1" spec="${RF_T_SPEC[i]}"
  local pkg repo folder binrel instname dest
  IFS='|' read -r pkg repo folder binrel instname <<< "$spec"
  if apt-cache show "$pkg" >/dev/null 2>&1 \
     && run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >>"$RF_LOG_FILE" 2>&1; then
    ok "Installed $instname (apt package: $pkg)."
    return 0
  fi
  warn "APT route failed for '$pkg'; building from upstream source..."
  dest="$RF_TOOLS_DIR/$folder"
  rf_clone_or_update "$repo" "$dest" || return 1
  make -C "$dest" >>"$RF_LOG_FILE" 2>&1 || { err "Build failed: $folder (see log)."; return 1; }
  [[ -x "$dest/$binrel" ]] || { err "Built binary not found: $dest/$binrel"; return 1; }
  install -m 0755 "$dest/$binrel" "$RF_LOCAL_BIN/$instname"
  ok "Installed $instname (built from source)."
}

rf_inst_pipx() {
  local i="$1"
  local name="${RF_T_NAME[i]}" spec="${RF_T_SPEC[i]}"
  have pipx || { err "pipx is not available (installed by the prerequisites step)."; return 1; }
  pipx ensurepath >/dev/null 2>&1 || true
  if [[ -d "$HOME/.local/pipx/venvs/$name" ]] || have "$name"; then
    if (( RF_FORCE )); then
      pipx upgrade "$name" >>"$RF_LOG_FILE" 2>&1 \
        || { warn "pipx upgrade failed for $name; reinstalling..."; pipx install "$spec" --force >>"$RF_LOG_FILE" 2>&1 || return 1; }
      ok "$name updated (pipx)."
    else
      ok "$name already installed via pipx."
    fi
    return 0
  fi
  pipx install "$spec" >>"$RF_LOG_FILE" 2>&1 || { err "pipx install failed: $spec"; return 1; }
  ok "Installed $name (pipx)."
}

# spec: repo-url|folder|entrypoint-relpath  (own venv + launcher)
rf_inst_pysrc() {
  local i="$1" spec="${RF_T_SPEC[i]}"
  local name="${RF_T_NAME[i]}" repo folder entry dest venv
  IFS='|' read -r repo folder entry <<< "$spec"
  dest="$RF_TOOLS_DIR/$folder"
  rf_clone_or_update "$repo" "$dest" || return 1
  venv="$(rf_make_venv "$folder")" || { err "venv creation failed: $folder"; return 1; }
  if [[ -f "$dest/requirements.txt" ]]; then
    "$venv/bin/python" -m pip install -r "$dest/requirements.txt" >>"$RF_LOG_FILE" 2>&1 \
      || warn "Some requirements failed for $name."
  fi
  if [[ -f "$dest/pyproject.toml" || -f "$dest/setup.py" ]]; then
    "$venv/bin/python" -m pip install "$dest" >>"$RF_LOG_FILE" 2>&1 \
      || warn "Package install failed for $name; source remains in $dest."
  fi
  local entry_path="$dest/$entry"
  if [[ ! -f "$entry_path" ]]; then
    # tolerate case/name drift after clone (e.g. JSFinder.py vs jsfinder.py)
    entry_path="$(find "$dest" -maxdepth 1 -iname "$(basename "$entry")" -print -quit 2>/dev/null)"
  fi
  if [[ -n "$entry_path" && -f "$entry_path" ]]; then
    rf_write_launcher "$name" "$venv/bin/python" "$entry_path"
  elif [[ -x "$venv/bin/$name" ]]; then
    ln -sf "$venv/bin/$name" "$RF_LOCAL_BIN/$name"
  else
    err "Entrypoint '$entry' not found in $dest — inspect manually."
    return 1
  fi
  ok "Prepared $name (venv: $venv)."
}

# spec: repo-url|folder|entrypoint-relpath  (system python3 + launcher)
rf_inst_gitraw() {
  local i="$1" spec="${RF_T_SPEC[i]}"
  local name="${RF_T_NAME[i]}" repo folder entry dest
  IFS='|' read -r repo folder entry <<< "$spec"
  dest="$RF_TOOLS_DIR/$folder"
  rf_clone_or_update "$repo" "$dest" || return 1
  local entry_path="$dest/$entry"
  if [[ ! -f "$entry_path" ]]; then
    entry_path="$(find "$dest" -maxdepth 1 -iname "$(basename "$entry")" -print -quit 2>/dev/null)"
  fi
  [[ -n "$entry_path" && -f "$entry_path" ]] \
    || { err "Entrypoint '$entry' not found in $dest."; return 1; }
  rf_write_launcher "$name" "python3" "$entry_path"
  ok "Prepared $name (source: $dest)."
}

# ---------------- post-install hooks ----------------
rf_post_shuffledns() {
  have massdns \
    || warn "shuffledns needs MassDNS to run — it is in the same category, or: reconforge install --tools massdns"
  local resolvers="${HOME}/tools/recon/resolvers.txt"
  if [[ ! -s "$resolvers" ]]; then
    log "Downloading a public DNS resolvers list for shuffledns..."
    if curl -fsSL --retry 2 -o "$resolvers" \
         'https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt' \
         && [[ -s "$resolvers" ]]; then
      ok "Resolvers list saved to $resolvers (use with: shuffledns -r $resolvers)"
    else
      rm -f "$resolvers"
      warn "Could not fetch a resolvers list — shuffledns requires one (-r <file>)."
    fi
  fi
  return 0
}

rf_post_nuclei() {
  log "nuclei needs its template library before first use: run 'nuclei -update-templates'."
  return 0
}

# spec: repo-url|folder|make-target|binary-relpath|install-name
rf_inst_gitmake() {
  local i="$1" spec="${RF_T_SPEC[i]}"
  local name="${RF_T_NAME[i]}" repo folder target binrel instname dest
  IFS='|' read -r repo folder target binrel instname <<< "$spec"
  dest="$RF_TOOLS_DIR/$folder"
  rf_clone_or_update "$repo" "$dest" || return 1
  make -C "$dest" "$target" >>"$RF_LOG_FILE" 2>&1 \
    || { err "Build failed: $folder (target: $target)."; return 1; }
  [[ -x "$dest/$binrel" ]] || { err "Built binary not found: $dest/$binrel"; return 1; }
  install -m 0755 "$dest/$binrel" "$RF_LOCAL_BIN/$instname"
  ok "Installed $instname (built from source)."
}

# spec: repo-url|folder
rf_inst_patterns() {
  local i="$1" spec="${RF_T_SPEC[i]}"
  local repo folder dest
  IFS='|' read -r repo folder <<< "$spec"
  dest="$RF_TOOLS_DIR/$folder"
  rf_clone_or_update "$repo" "$dest" || return 1
  mkdir -p "$RF_GF_DIR"
  find "$dest" -type f -name '*.json' -exec cp -f {} "$RF_GF_DIR/" \;
  ok "GF patterns copied to $RF_GF_DIR"
}

rf_inst_curlscript() {
  local i="$1" url="${RF_T_SPEC[i]}" tmp
  if have aws && (( RF_FORCE == 0 )); then
    ok "AWS CLI already available: $(aws --version 2>&1 | head -n1)"
    return 0
  fi
  tmp="$(mktemp /tmp/rf-awscli-XXXXXX)"
  if ! rf_fetch "$url" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  run_root bash "$tmp" >>"$RF_LOG_FILE" 2>&1 || { err "AWS CLI installer failed (see log)."; rm -f "$tmp"; return 1; }
  rm -f "$tmp"
  ok "AWS CLI installed/updated."
}

rf_inst_snap() {
  local i="$1" snapname="${RF_T_BIN[i]}"
  have snap || { err "snap is unavailable — install ${snapname} manually: https://www.postman.com/downloads/ (Postman) or enable snapd first."; return 1; }
  run_root snap install "$snapname" >>"$RF_LOG_FILE" 2>&1 \
    || { err "snap install failed: $snapname"; return 1; }
  ok "Installed $snapname (snap)."
}

rf_do_install() { # <tool-name> → dispatch by type
  local name="$1" i
  i="$(rf_tool_index "$name")" || { err "Unknown tool: $name"; return 1; }
  case "${RF_T_TYPE[i]}" in
    go)         rf_inst_go "$i" ;;
    apt)        rf_inst_apt "$i" ;;
    aptorbuild) rf_inst_aptorbuild "$i" ;;
    pipx)       rf_inst_pipx "$i" ;;
    pysrc)      rf_inst_pysrc "$i" ;;
    gitraw)     rf_inst_gitraw "$i" ;;
    gitmake)    rf_inst_gitmake "$i" ;;
    patterns)   rf_inst_patterns "$i" ;;
    curlscript) rf_inst_curlscript "$i" ;;
    snap)       rf_inst_snap "$i" ;;
    *)          err "Unknown tool type: ${RF_T_TYPE[i]}"; return 1 ;;
  esac
}

# ---------------- Go toolchain management ----------------
rf_go_state_field() { # <prefix|version|managed>
  [[ -r "$RF_GO_STATE" ]] || return 1
  grep "^${1}=" "$RF_GO_STATE" 2>/dev/null | head -n1 | cut -d= -f2-
}

# Ensures Go >= RF_GO_MIN_VERSION. Never destroys a Go installation that
# reconforge does not manage without an explicit typed confirmation.
rf_ensure_go() {
  local cur="" target_prefix="" managed
  if have go; then
    cur="$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//' || true)"
  fi
  if [[ -n "$cur" ]] && version_ge "$cur" "$RF_GO_MIN_VERSION"; then
    ok "Go ${cur} is available (minimum: ${RF_GO_MIN_VERSION})."
    return 0
  fi
  if (( RF_DRY_RUN )); then
    if [[ -n "$cur" ]]; then
      dry "Go ${cur} is below the minimum ${RF_GO_MIN_VERSION} — would download the latest stable Go for linux/${RF_GOARCH:-?} (SHA256 verified)."
    else
      dry "Go is missing — would download the latest stable Go for linux/${RF_GOARCH:-?} (SHA256 verified)."
    fi
    return 0
  fi
  managed="$(rf_go_state_field prefix || true)"

  if [[ -n "$cur" ]]; then
    if [[ -n "$managed" && -d "$managed" ]]; then
      warn "Go ${cur} is older than ${RF_GO_MIN_VERSION} and was installed by reconforge — replacing it."
      target_prefix="$managed"
    else
      warn "Existing Go ${cur} (outside reconforge management) is older than ${RF_GO_MIN_VERSION}."
      if rf_confirm "Replace the existing Go installation? (No = install a private copy in ~/.local instead)"; then
        target_prefix="/usr/local/go"
      else
        target_prefix="$HOME/.local/go-reconforge"
        warn "A private Go will be installed at ${target_prefix} — your system Go stays untouched."
      fi
    fi
  else
    log "Installing the latest stable Go from go.dev..."
    target_prefix="/usr/local/go"
  fi

  local json file sha tmpd archive
  json="$(mktemp)"
  curl -fsSL 'https://go.dev/dl/?mode=json' -o "$json" \
    || { err "Could not reach go.dev to resolve the Go release."; rm -f "$json"; return 1; }
  read -r _ file sha < <(
    jq -r --arg arch "$RF_GOARCH" \
      '.[0] as $v | $v.files[] | select(.os == "linux" and .arch == $arch and .kind == "archive") | [$v.version, .filename, .sha256] | @tsv' \
      "$json" 2>/dev/null
  ) || { err "Could not parse the go.dev release manifest."; rm -f "$json"; return 1; }
  rm -f "$json"
  [[ -n "${file:-}" && -n "${sha:-}" ]] \
    || { err "Could not determine the latest Go archive for linux/${RF_GOARCH}."; return 1; }

  tmpd="$(mktemp -d)"
  archive="${tmpd}/${file}"
  rf_fetch "https://go.dev/dl/${file}" "$archive" "$sha" || { rm -rf "$tmpd"; return 1; }

  if [[ "$target_prefix" == "/usr/local/go" ]]; then
    run_root rm -rf "$target_prefix"
    run_root tar -C /usr/local -xzf "$archive" || { rm -rf "$tmpd"; err "Extraction to /usr/local/go failed."; return 1; }
  else
    # Private location: only overwrite a directory reconforge itself created.
    if [[ -d "$target_prefix" && ! -f "$target_prefix/.reconforge-managed" ]]; then
      err "Refusing to overwrite non-reconforge directory: $target_prefix"
      rm -rf "$tmpd"
      return 1
    fi
    rm -rf "$target_prefix"
    mkdir -p "$target_prefix"
    tar -C "$target_prefix" -xzf "$archive" || { rm -rf "$tmpd"; err "Extraction failed."; return 1; }
    touch "$target_prefix/.reconforge-managed"
  fi
  rm -rf "$tmpd"

  export PATH="$target_prefix/bin:$PATH"
  hash -r
  have go || { err "Go installation failed."; return 1; }
  mkdir -p "$RF_STATE_ROOT"
  printf 'managed=1\nprefix=%s\nversion=%s\ndate=%s\n' \
    "$target_prefix" "$(go version | awk '{print $3}')" "$(date +%F)" > "$RF_GO_STATE"
  ok "Installed $(go version)."
}

# Removes the Go toolchain — protected by typed confirmation, especially
# when the Go installation is not reconforge-managed.
rf_remove_go() {
  local prefix ver gopath
  prefix="$(rf_go_state_field prefix || true)"
  if [[ -n "$prefix" && -d "$prefix" ]]; then
    ver="$(rf_go_state_field version || true)"
    warn "reconforge-managed Go: ${ver:-unknown} at $prefix"
    rf_confirm_strict "This permanently deletes $prefix." \
      || { err "Aborted — typed confirmation is required to remove Go."; return 1; }
    if [[ "$prefix" == "/usr/local/go" ]]; then
      run_root rm -rf "$prefix"
    else
      rm -rf "$prefix"
    fi
    rm -f "$RF_GO_STATE"
    ok "Managed Go removed."
    return 0
  fi
  gopath="$(command -v go 2>/dev/null || true)"
  if [[ -z "$gopath" ]]; then
    ok "No Go toolchain found."
    return 0
  fi
  err "Go at $gopath is NOT managed by reconforge — removal refused by default."
  if rf_confirm_strict "Force-remove the unmanaged Go at $(dirname "$(dirname "$gopath")")?"; then
    run_root rm -rf "$(dirname "$(dirname "$gopath")")"
    ok "Unmanaged Go removed."
  else
    warn "Nothing was removed. Remove Go manually if you are certain."
    return 1
  fi
}

# ---------------- removal handlers ----------------
rf_remove_tool() { # <tool-name>
  local name="$1" i type bin row spec
  if [[ "$name" == "go" || "$name" == "go-toolchain" ]]; then
    rf_remove_go
    return $?
  fi
  i="$(rf_tool_index "$name")" || { err "Unknown tool: $name"; return 1; }
  type="${RF_T_TYPE[i]}"; bin="${RF_T_BIN[i]}"; spec="${RF_T_SPEC[i]}"
  row="$(rf_state_row "$name")"
  if [[ -z "$row" ]]; then
    rf_confirm "'$name' is not recorded as reconforge-managed. Remove it anyway?" || return 1
  fi
  case "$type" in
    go)
      rm -f "$RF_GOBIN_DIR/$bin"
      ok "Removed $bin" ;;
    apt)
      run_root env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$bin" >>"$RF_LOG_FILE" 2>&1 \
        || warn "apt remove failed: $bin"
      ok "Removed $bin (apt)" ;;
    aptorbuild)
      rm -f "$RF_LOCAL_BIN/$bin"
      run_root env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$(rf_spec_part "$spec" 1)" >>"$RF_LOG_FILE" 2>&1 || true
      rm -rf "$RF_TOOLS_DIR/$(rf_spec_part "$spec" 3)"
      ok "Removed $name" ;;
    pipx)
      if have pipx; then pipx uninstall "$name" >>"$RF_LOG_FILE" 2>&1 || warn "pipx uninstall failed: $name"; fi
      ok "Removed $name (pipx)" ;;
    pysrc)
      rm -f "$RF_LOCAL_BIN/$name"
      rm -rf "$RF_VENV_DIR/$(rf_spec_part "$spec" 2)" "$RF_TOOLS_DIR/$(rf_spec_part "$spec" 2)"
      ok "Removed $name (launcher, venv and source)" ;;
    gitraw)
      rm -f "$RF_LOCAL_BIN/$name"
      rm -rf "$RF_TOOLS_DIR/$(rf_spec_part "$spec" 2)"
      ok "Removed $name (launcher and source)" ;;
    gitmake)
      rm -f "$RF_LOCAL_BIN/$bin"
      rm -rf "$RF_TOOLS_DIR/$(rf_spec_part "$spec" 2)"
      ok "Removed $name (binary and source)" ;;
    patterns)
      if rf_confirm "Also remove GF pattern JSONs in $RF_GF_DIR?" y; then
        rm -f "$RF_GF_DIR"/*.json
      fi
      rm -rf "$RF_TOOLS_DIR/$(rf_spec_part "$spec" 2)"
      ok "Removed $name" ;;
    curlscript)
      if have aws; then
        local awspath; awspath="$(dirname "$(command -v aws)")"
        run_root rm -f "$awspath/aws" "$awspath/aws_completer" "$awspath/aws.cmd"
      fi
      ok "Removed AWS CLI binaries" ;;
    snap)
      if have snap; then run_root snap remove "$bin" >>"$RF_LOG_FILE" 2>&1 || warn "snap remove failed: $bin"; fi
      ok "Removed $name (snap)" ;;
    *)
      err "Unknown tool type: $type"; return 1 ;;
  esac
  rf_state_del "$name"
  return 0
}
