#!/usr/bin/env bash
# ReconForge module — Category 2: Web Discovery
[[ -n "${RF_MOD_WEB_SH:-}" ]] && return 0
RF_MOD_WEB_SH=1

rf_module web "Web Discovery"

rf_tool httpx    web go \
  "Fast and multi-purpose HTTP toolkit (ProjectDiscovery)" \
  'github.com/projectdiscovery/httpx/cmd/httpx@latest' 'httpx -version'

rf_tool ffuf     web go \
  "Fast web fuzzer written in Go" \
  'github.com/ffuf/ffuf/v2@latest' 'ffuf -V'

rf_tool katana   web go \
  "Next-gen crawling and spidering framework" \
  'github.com/projectdiscovery/katana/cmd/katana@latest' 'katana -version'

rf_tool hakrawler web go \
  "Web crawler for endpoint discovery" \
  'github.com/hakluke/hakrawler@latest' 'echo | hakrawler'

rf_tool gospider web go \
  "Fast multi-threaded web spider" \
  'github.com/jaeles-project/gospider@latest' ''

rf_tool httprobe web go \
  "Probe working HTTP/HTTPS servers from a list" \
  'github.com/tomnomnom/httprobe@latest' 'echo | httprobe'

rf_tool anew     web go \
  "Append only new lines to a file (pipeline helper)" \
  'github.com/tomnomnom/anew@latest' 'echo | anew'
