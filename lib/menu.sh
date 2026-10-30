#!/usr/bin/env bash
# ============================================================
# ReconForge — lib/menu.sh
# Interactive category selection menu (works in bash and zsh
# terminals; uses numbered toggles, no special escape codes).
# ============================================================

[[ -n "${RF_MENU_SH:-}" ]] && return 0
RF_MENU_SH=1

rf_banner() {
  printf '%s\n' "$CYAN$BOLD"
  printf '  ==============================================================\n'
  printf '    R E C O N F O R G E  ·  Advanced Reconnaissance Toolkit\n'
  printf '  ==============================================================\n'
  printf '%s\n' "$NC"
}

# rf_menu_select → 0 on success, 1 on quit.
# Sets RF_MENU_SEL=(category-ids...). Defaults: all CLI categories on, GUI off.
rf_menu_select() {
  local -a ids=() titles=() lists=() on=()
  local n=0 i j count ans tok
  for i in ${RF_MOD_ID[@]+"${!RF_MOD_ID[@]}"}; do
    ids+=("${RF_MOD_ID[i]}")
    titles+=("${RF_MOD_TITLE[i]}")
    local tl
    tl="$(rf_cat_tools "${RF_MOD_ID[i]}" | paste -sd ',' -)"
    tl="${tl//,/, }"
    lists+=("$tl")
    if [[ "${RF_MOD_ID[i]}" == "gui" ]]; then on+=(0); else on+=(1); fi
    n=$((n + 1))
  done
  (( n > 0 )) || { err "Tool registry is empty."; return 1; }

  while true; do
    count=0
    for (( j = 0; j < n; j++ )); do (( count += on[j] )); done
    printf '\n%s  RECONFORGE — Installation Categories%s\n' "$BOLD" "$NC"
    printf '  Categories selected: %s%d/%d%s\n\n' "$BOLD" "$count" "$n" "$NC"
    for (( i = 0; i < n; i++ )); do
      local mark="[ ]"
      (( on[i] )) && mark="${GREEN}[x]${NC}"
      printf '  %2d) %s %s\n' "$((i + 1))" "$mark" "${titles[i]}"
      printf '      %s\n' "${lists[i]}"
    done
    printf '\n  %s<number(s)>%s toggle · %sa%s all · %sc%s clear · %si%s install · %sq%s quit\n' \
      "$BOLD" "$NC" "$BOLD" "$NC" "$BOLD" "$NC" "$BOLD" "$NC" "$BOLD" "$NC"
    IFS= read -r -p "  Selection: " ans || return 1
    ans="${ans%$'\r'}"
    # trim leading/trailing whitespace only (internal spaces separate numbers)
    ans="${ans#"${ans%%[![:space:]]*}"}"
    ans="${ans%"${ans##*[![:space:]]}"}"
    case "$ans" in
      '' ) : ;;
      a|A) for (( j = 0; j < n; j++ )); do on[j]=1; done ;;
      c|C) for (( j = 0; j < n; j++ )); do on[j]=0; done ;;
      i|I)
        count=0
        for (( j = 0; j < n; j++ )); do (( count += on[j] )); done
        if (( count == 0 )); then
          warn "Nothing selected — toggle at least one category."
          continue
        fi
        RF_MENU_SEL=()
        for (( j = 0; j < n; j++ )); do
          (( on[j] )) && RF_MENU_SEL+=("${ids[j]}")
        done
        return 0 ;;
      q|Q) return 1 ;;
      *)
        for tok in ${ans//,/ }; do
          if ! [[ "$tok" =~ ^[0-9]+$ ]]; then warn "Invalid entry: $tok"; continue; fi
          if (( tok < 1 || tok > n )); then warn "Out of range: $tok"; continue; fi
          j=$((tok - 1))
          if (( on[j] )); then on[j]=0; else on[j]=1; fi
        done ;;
    esac
  done
}
