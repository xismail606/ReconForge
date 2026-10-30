#!/usr/bin/env bash
# ReconForge module — Category 1: Subdomain Enumeration
[[ -n "${RF_MOD_SUBDOMAIN_SH:-}" ]] && return 0
RF_MOD_SUBDOMAIN_SH=1

rf_module subdomain "Subdomain Enumeration"

rf_tool subfinder  subdomain go \
  "Fast passive subdomain enumerator (ProjectDiscovery)" \
  'github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest' 'subfinder -version'

rf_tool amass      subdomain apt \
  "In-depth subdomain enumeration and mapping (OWASP)" \
  'amass' 'amass -version'

rf_tool massdns    subdomain aptorbuild \
  "High-performance DNS brute-forcer" \
  'massdns|https://github.com/blechschmidt/massdns.git|massdns|bin/massdns|massdns' 'massdns --help'

rf_tool shuffledns subdomain go \
  "MassDNS wrapper for active subdomain bruteforcing" \
  'github.com/projectdiscovery/shuffledns/cmd/shuffledns@latest' 'shuffledns -version'

rf_tool dnsx       subdomain go \
  "Fast DNS resolver and toolkit (ProjectDiscovery)" \
  'github.com/projectdiscovery/dnsx/cmd/dnsx@latest' 'dnsx -version'

rf_tool subbrute   subdomain gitraw \
  "DNS brute-forcer (source checkout)" \
  'https://github.com/TheRook/subbrute.git|SubBrute|subbrute.py' ''
