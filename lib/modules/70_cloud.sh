#!/usr/bin/env bash
# ReconForge module — Category 7: Cloud & API
[[ -n "${RF_MOD_CLOUD_SH:-}" ]] && return 0
RF_MOD_CLOUD_SH=1

rf_module cloud "Cloud & API"

rf_tool cloudenum  cloud pysrc \
  "Multi-cloud OSINT enumerator (S3, Azure, GCS)" \
  'https://github.com/initstring/cloud_enum.git|cloud_enum|cloud_enum.py' ''

rf_tool s3scanner  cloud go \
  "Scan for open S3 buckets and enumerate their objects" \
  'github.com/sa7mon/s3scanner@latest' 's3scanner --version'

rf_tool kiterunner cloud gitmake \
  "API endpoint discovery and kite runners (assetnote)" \
  'https://github.com/assetnote/kiterunner.git|kiterunner|build|dist/kr|kr' 'kr -h'

rf_tool awscli     cloud curlscript \
  "AWS CLI v2 (official AWS installer)" \
  'https://awscli.amazonaws.com/v2/install.sh' 'aws --version' aws
