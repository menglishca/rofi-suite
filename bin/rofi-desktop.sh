#!/usr/bin/env bash
#
# rofi-desktop.sh - Theme-aware desktop launcher (drun, run, filebrowser, window)
#
# Usage: rofi-desktop.sh [options] [mode]
#   e.g.: rofi-desktop.sh              → drun, default theme
#         rofi-desktop.sh run          → run, default theme
#         rofi-desktop.sh --theme foo.rasi filebrowser
#
# Options:
#   --config FILE    Path to user config JSON (overrides default lookup)
#   --defaults FILE  Path to defaults JSON (overrides default lookup)
#   --theme FILE     Path to .rasi theme file (overrides default lookup)
#   -h, --help       Show this help message
#
# Config resolution (for each file, first found wins):
#   1. Explicit CLI argument (--config, --defaults, --theme)
#   2. $HOME/.config/rofi/suite/<filename>
#   3. Error

set -euo pipefail

# ── Resolve script directory ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROFI_DIR="$(dirname "$SCRIPT_DIR")"

# ── Fallback config directory ───────────────────────────────────
ROFI_CONFIG_DIR="$HOME/.config/rofi/suite"

# ── Parse arguments ─────────────────────────────────────────────
CONFIG_FILE=""
DEFAULTS_FILE=""
THEME_FILE=""
MODE=""

show_help() {
    cat <<EOF
Usage: $(basename "$0") [options] [mode]

Theme-aware desktop launcher (drun, run, filebrowser, window).

Positional arguments:
  mode    Rofi mode: drun, run, filebrowser, window (default: drun)

Options:
  --config FILE    Path to user config JSON (overrides default lookup)
  --defaults FILE  Path to defaults JSON (overrides default lookup)
  --theme FILE     Path to .rasi theme file (overrides default lookup)
  -h, --help       Show this help message

Config resolution (for each file, first found wins):
  1. Explicit CLI argument (--config, --defaults, --theme)
  2. \$HOME/.config/rofi/suite/<filename>
  3. Error

Examples:
  $(basename "$0")
  $(basename "$0") run
  $(basename "$0") --theme /path/to/theme.rasi filebrowser
  $(basename "$0") --config /path/to/user_config.json
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)   CONFIG_FILE="$2"; shift 2 ;;
        --defaults) DEFAULTS_FILE="$2"; shift 2 ;;
        --theme)    THEME_FILE="$2"; shift 2 ;;
        --help|-h)  show_help; exit 0 ;;
        -*)         echo "Unknown option: $1"; echo "Try '$(basename "$0") --help'"; exit 1 ;;
        *)          MODE="$1"; shift ;;
    esac
done

# ── Default mode ───────────────────────────────────────────────
MODE="${MODE:-drun}"

# ── Resolve defaults.json ───────────────────────────────────────
if [ -n "$DEFAULTS_FILE" ]; then
    if [ ! -f "$DEFAULTS_FILE" ]; then
        echo "Error: Defaults file not found: $DEFAULTS_FILE"
        exit 1
    fi
else
    FALLBACK_DEFAULTS="$ROFI_CONFIG_DIR/defaults.json"
    if [ -f "$FALLBACK_DEFAULTS" ]; then
        DEFAULTS_FILE="$FALLBACK_DEFAULTS"
    else
        echo "Error: No defaults.json found"
        echo "  Tried: $FALLBACK_DEFAULTS"
        echo "  Provide one with --defaults or place it in $ROFI_CONFIG_DIR/"
        exit 1
    fi
fi

# ── Resolve user_config.json ────────────────────────────────────
if [ -n "$CONFIG_FILE" ]; then
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: User config file not found: $CONFIG_FILE"
        exit 1
    fi
else
    FALLBACK_CONFIG="$ROFI_CONFIG_DIR/user_config.json"
    if [ -f "$FALLBACK_CONFIG" ]; then
        CONFIG_FILE="$FALLBACK_CONFIG"
    fi
    # Config is optional — we proceed without it if not found
fi

# ── Merge defaults + user config ───────────────────────────────
if [ -n "$CONFIG_FILE" ]; then
    merged=$(jq -s '.[0] * .[1]' "$DEFAULTS_FILE" "$CONFIG_FILE")
else
    merged=$(cat "$DEFAULTS_FILE")
fi

# ── Resolve theme .rasi file ───────────────────────────────────
if [ -n "$THEME_FILE" ]; then
    if [ ! -f "$THEME_FILE" ]; then
        echo "Error: Theme file not found: $THEME_FILE"
        exit 1
    fi
else
    FALLBACK_THEME="$ROFI_CONFIG_DIR/theme.rasi"
    if [ -f "$FALLBACK_THEME" ]; then
        THEME_FILE="$FALLBACK_THEME"
    else
        echo "Error: No theme file found"
        echo "  Tried: $FALLBACK_THEME"
        echo "  Provide one with --theme or place it in $ROFI_CONFIG_DIR/"
        exit 1
    fi
fi

# ── Launch rofi ─────────────────────────────────────────────────
rofi \
    -show "$MODE" \
    -theme "$THEME_FILE"
