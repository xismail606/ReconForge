#!/usr/bin/env bash
# ReconForge module — Category 3: URL & Archive Discovery
[[ -n "${RF_MOD_ARCHIVE_SH:-}" ]] && return 0
RF_MOD_ARCHIVE_SH=1

rf_module archive "URL & Archive Discovery"

rf_tool gau         archive go \
  "Fetch known URLs from AlienVault OTX, Common Crawl and Wayback" \
  'github.com/lc/gau/v2/cmd/gau@latest' 'gau -version'

rf_tool waybackurls archive go \
  "Fetch known URLs from the Wayback Machine" \
  'github.com/tomnomnom/waybackurls@latest' 'echo | waybackurls'
