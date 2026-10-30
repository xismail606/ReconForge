#!/usr/bin/env bash
# ReconForge module — Category 10: GUI Applications
# Not included by 'install --all'; toggle it in the menu or pass --gui.
[[ -n "${RF_MOD_GUI_SH:-}" ]] && return 0
RF_MOD_GUI_SH=1

rf_module gui "GUI Applications"

rf_tool burpsuite gui apt \
  "Burp Suite Community (Kali/Debian package)" \
  'burpsuite' '' burpsuite

rf_tool postman    gui snap \
  "Postman API platform (snap package)" \
  'postman' '' postman
