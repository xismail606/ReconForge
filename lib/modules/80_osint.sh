#!/usr/bin/env bash
# ReconForge module — Category 8: OSINT & Intelligence
[[ -n "${RF_MOD_OSINT_SH:-}" ]] && return 0
RF_MOD_OSINT_SH=1

rf_module osint "OSINT & Intelligence"

rf_tool gitdorker        osint pysrc \
  "GitHub dorking for secrets and subdomains (needs token)" \
  'https://github.com/obheda12/GitDorker.git|GitDorker|GitDorker.py' ''

rf_tool github-subdomains osint go \
  "Fetch subdomains from public GitHub data (needs PAT)" \
  'github.com/gwen001/github-subdomains@latest' ''

rf_tool shodan           osint pipx \
  "Shodan CLI (needs API key: shodan init <key>)" \
  'shodan' 'shodan version'

rf_tool censys           osint go \
  "Censys Platform CLI (needs API key: censys config auth add)" \
  'github.com/censys/cencli/cmd/cencli@latest' 'censys -h' censys cencli
