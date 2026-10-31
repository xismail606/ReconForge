#!/usr/bin/env bash
# ReconForge module — Category 2: Web Discovery
[[ -n "${RF_MOD_WEB_SH:-}" ]] && return 0
RF_MOD_WEB_SH=1

rf_module web "Web Discovery"

rf_tool httpx    web go \
  "Fast and multi-purpose HTTP toolkit (ProjectDiscovery; the Python 'httpx' package is a different tool — this installs the Go binary into ~/.local/bin)" \
  'github.com/projectdiscovery/httpx/cmd/httpx@latest' 'httpx -version'

rf_tool ffuf     web go \
  "Fast web fuzzer written in Go" \
  'github.com/ffuf/ffuf/v2@latest' 'ffuf -V'

rf_tool katana   web go \
  "Next-gen crawling and spidering framework" \
  'github.com/projectdiscovery/katana/cmd/katana@latest' 'katana -version'

rf_tool hakrawler web go \
  "Web crawler for endpoint discovery" \
  'github.com/hakluke/hakrawler@latest' 'hakrawler -h 2>&1 | head -n1'

rf_tool gospider web go \
  "Fast multi-threaded web spider" \
  'github.com/jaeles-project/gospider@latest' ''

rf_tool anew     web go \
  "Append only new lines to a file (pipeline helper)" \
  'github.com/tomnomnom/anew@latest' 'echo | anew'
