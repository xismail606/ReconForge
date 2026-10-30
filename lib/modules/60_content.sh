#!/usr/bin/env bash
# ReconForge module — Category 6: Content Discovery
[[ -n "${RF_MOD_CONTENT_SH:-}" ]] && return 0
RF_MOD_CONTENT_SH=1

rf_module content "Content Discovery"

rf_tool feroxbuster content apt \
  "Recursive content discovery tool written in Rust" \
  'feroxbuster' 'feroxbuster --version'

rf_tool dirsearch   content pipx \
  "Web path scanner / directory brute-forcer" \
  'git+https://github.com/maurosoria/dirsearch.git' ''
