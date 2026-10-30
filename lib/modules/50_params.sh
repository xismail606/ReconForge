#!/usr/bin/env bash
# ReconForge module — Category 5: Parameter Discovery
[[ -n "${RF_MOD_PARAMS_SH:-}" ]] && return 0
RF_MOD_PARAMS_SH=1

rf_module params "Parameter Discovery"

rf_tool arjun       params pipx \
  "HTTP parameter discovery suite" \
  'arjun' 'arjun -h'

rf_tool paramspider params pysrc \
  "Extract known parameters from Wayback archives" \
  'https://github.com/devanshbatham/ParamSpider.git|ParamSpider|paramspider.py' ''
