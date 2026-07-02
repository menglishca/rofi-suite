#!/usr/bin/env bash
#
# rofi-desktop.sh - Theme-aware desktop launcher (drun, run, filebrowser, window)
#
# Each desktop mode can have its own theme (type + color scheme).
#
# Usage: rofi-desktop.sh [options] [mode]
#   e.g.: rofi-desktop.sh              → drun, resolved theme
#         rofi-desktop.sh run          → run, resolved theme
#         rofi-desktop.sh --theme foo.rasi filebrowser
#
# Options:
#   --config FILE    Path to user config JSON (overrides default lookup)
#   --defaults FILE  Path to defaults JSON (overrides default lookup)
#   --theme FILE     Path to .rasi theme file (overrides per-mode theme)
#   -h, --help       Show this help message
#
# Theme resolution (first match wins):
#   1. --theme CLI argument (highest priority)
#   2. desktop.<mode>.theme.type + desktop.<mode>.theme.color_scheme
#   3. Global theme.type + theme.color_scheme (fallback)
#
# Resolved theme file: $ROFI_CONFIG_DIR/styles/<type>-<color>.rasi

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
  --theme FILE     Path to .rasi theme file (overrides per-mode theme)
  -h, --help       Show this help message

Theme resolution (first match wins):
  1. --theme CLI argument
  2. desktop.<mode>.theme (type + color_scheme)
  3. Global theme (type + color_scheme)

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

# ── Resolve theme for this desktop mode ─────────────────────────
resolve_theme() {
    # Priority: CLI --theme > mode-specific > global default
    if [ -n "$THEME_FILE" ]; then
        echo "$THEME_FILE"
        return
    fi

    local mode_type mode_color global_type global_color

    # Check per-mode theme override
    mode_type=$(echo "$merged" | jq -re ".desktop.${MODE}.theme.type // empty" 2>/dev/null || true)
    mode_color=$(echo "$merged" | jq -re ".desktop.${MODE}.theme.color_scheme // empty" 2>/dev/null || true)

    # Fall back to global theme
    global_type=$(echo "$merged" | jq -re '.theme.type // "bordered"')
    global_color=$(echo "$merged" | jq -re '.theme.color_scheme // "nord"')

    local resolved_type="${mode_type:-$global_type}"
    local resolved_color="${mode_color:-$global_color}"

    local theme_path="$ROFI_CONFIG_DIR/styles/${resolved_type}-${resolved_color}.rasi"

    if [ -f "$theme_path" ]; then
        echo "$theme_path"
    else
        echo "Error: Resolved theme file not found: $theme_path"
        echo "  Mode: $MODE"
        echo "  Resolved: type=$resolved_type, color=$resolved_color"
        echo "  Run build-theme.sh to generate theme files."
        exit 1
    fi
}

THEME_FILE=$(resolve_theme)

# ── Launch rofi ─────────────────────────────────────────────────
rofi \
    -show "$MODE" \
    -theme "$THEME_FILE"
