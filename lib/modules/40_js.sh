#!/usr/bin/env bash
# ReconForge module — Category 4: JavaScript Analysis
[[ -n "${RF_MOD_JS_SH:-}" ]] && return 0
RF_MOD_JS_SH=1

rf_module js "JavaScript Analysis"

rf_tool linkfinder js pysrc \
  "Extract endpoints and parameters from JavaScript files" \
  'https://github.com/GerbenJavado/LinkFinder.git|LinkFinder|linkfinder.py' 'linkfinder -h'

rf_tool subjs       js go \
  "Find JavaScript files in a list of URLs" \
  'github.com/lc/subjs@latest' 'echo | subjs'

rf_tool jsfinder    js pysrc \
  "Extract JS and HTML endpoints from a domain" \
  'https://github.com/Threezh1/JSFinder.git|JSFinder|JSFinder.py' ''

rf_tool gf          js go \
  "Wrapper around grep with bug-bounty pattern sets" \
  'github.com/tomnomnom/gf@latest' 'gf -list'
