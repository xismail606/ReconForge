#!/usr/bin/env bash
# ============================================================
# ReconForge bootstrap — delegates to the modular CLI.
# Legacy entry point kept for compatibility:
#   bash install_recon_tools.sh [--gui] [--wordlists] ...
# now opens the same interactive installer as: reconforge install
# ============================================================
set -Eeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

printf '%s\n' "Bootstrapping ReconForge..."
# Register the global 'reconforge' command (idempotent, cheap).
bash "$DIR/reconforge" setup >/dev/null 2>&1 || true

exec bash "$DIR/reconforge" install "$@"
