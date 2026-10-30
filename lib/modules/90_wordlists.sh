#!/usr/bin/env bash
# ReconForge module — Category 9: Wordlists
[[ -n "${RF_MOD_WORDLISTS_SH:-}" ]] && return 0
RF_MOD_WORDLISTS_SH=1

rf_module wordlists "Wordlists"

rf_tool seclists   wordlists apt \
  "SecLists wordlist collection (/usr/share/seclists, large download)" \
  'seclists' '' seclists 'dir:/usr/share/seclists'

rf_tool gfpatterns wordlists patterns \
  "GF pattern JSON collection (copied to ~/.gf)" \
  'https://github.com/1ndianl33t/Gf-Patterns.git|Gf-Patterns' ''
