#!/usr/bin/env bash
#
# build-theme.sh - Pre-bake static .rasi files from templates and config
#
# Usage: ./build-theme.sh                           # Uses defaults.json + user_config.json
#        ./build-theme.sh --type bordered --color nord --style overrides
#        ./build-theme.sh --output ./my-theme
#        ./build-theme.sh --templates-dir /path/to/themes --defaults /path/to/defaults.json --config /path/to/user_config.json
#
# This generates ready-to-use .rasi files in the output/ directory.
# Symlink output/ to ~/.config/rofi/ to use.
#
# Options:
#   --templates-dir DIR   Path to templates directory (default: ./templates)
#   --defaults FILE       Path to defaults.json (default: ./defaults.json)
#   --config FILE         Path to user_config.json (default: ./user_config.json)
#   --output DIR          Output directory (default: ./output)
#   --type TYPE           Theme type (e.g. bordered, rounded, compact, horizontal, iconic)
#   --color NAME          Color scheme name (e.g. nord, dracula, catppuccin)
#   --style JSON          Style overrides as JSON string
#   -h, --help            Show this help message

set -euo pipefail

# ── Paths (defaults, overridable via CLI) ──────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
OUTPUT_DIR="$SCRIPT_DIR/output"
DEFAULTS_FILE="$SCRIPT_DIR/defaults.json"
USER_CONFIG_FILE="$SCRIPT_DIR/user_config.json"

# ── Defaults (overridden by config below) ──────────────────────
THEME_TYPE="bordered"
COLOR_SCHEME="nord"
STYLE_OVERRIDES=""

# ── Parse command-line arguments ────────────────────────────────
show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Pre-bake static .rasi files from templates and config.

Options:
  --templates-dir DIR   Path to templates directory (default: ./templates)
  --defaults FILE       Path to defaults.json (default: ./defaults.json)
  --config FILE         Path to user_config.json (default: ./user_config.json)
  --output DIR          Output directory (default: ./output)
  --type TYPE           Theme type (e.g. bordered, rounded, compact, horizontal, iconic)
  --color NAME          Color scheme name (e.g. nord, dracula, catppuccin)
  --style JSON          Style overrides as JSON string
  -h, --help            Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") --type rounded --color catppuccin
  $(basename "$0") --templates-dir ~/my-templates --defaults ~/my-defaults.json
  $(basename "$0") --output ~/.config/rofi
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)           THEME_TYPE="$2"; _CLI_TYPE_SET=1; shift 2 ;;
        --color)          COLOR_SCHEME="$2"; _CLI_COLOR_SET=1; shift 2 ;;
        --output)         OUTPUT_DIR="$2"; shift 2 ;;
        --style)          STYLE_OVERRIDES="$2"; shift 2 ;;
        --templates-dir)  TEMPLATES_DIR="$2"; shift 2 ;;
        --defaults)       DEFAULTS_FILE="$2"; shift 2 ;;
        --config)         USER_CONFIG_FILE="$2"; shift 2 ;;
        --help|-h)        show_help; exit 0 ;;
        *)                echo "Unknown option: $1"; echo "Try '$(basename "$0") --help'"; exit 1 ;;
    esac
done

# ── Validate paths ─────────────────────────────────────────────
if [ ! -d "$TEMPLATES_DIR" ]; then
    echo "Error: Templates directory not found: $TEMPLATES_DIR"
    exit 1
fi

if [ ! -f "$DEFAULTS_FILE" ]; then
    echo "Error: Defaults file not found: $DEFAULTS_FILE"
    exit 1
fi

# ── Merge defaults + user config ───────────────────────────────
if [ -f "$USER_CONFIG_FILE" ]; then
    merged=$(jq -s '.[0] * .[1]' "$DEFAULTS_FILE" "$USER_CONFIG_FILE")
else
    merged=$(cat "$DEFAULTS_FILE")
fi

# ── CLI args take precedence over config ───────────────────────
# Save the CLI-parsed values (set during arg parsing above).
# Only use config values when no CLI arg was provided.
if [ -z "${_CLI_TYPE_SET:-}" ]; then
    THEME_TYPE=$(echo "$merged" | jq -re '.theme.type // empty' || echo "$THEME_TYPE")
fi
if [ -z "${_CLI_COLOR_SET:-}" ]; then
    COLOR_SCHEME=$(echo "$merged" | jq -re '.theme.color_scheme // empty' || echo "$COLOR_SCHEME")
fi

# ── Validate type ──────────────────────────────────────────────
TYPE_FILE="$TEMPLATES_DIR/types/${THEME_TYPE}.rasi"
if [ ! -f "$TYPE_FILE" ]; then
    echo "Error: Type '$THEME_TYPE' not found at $TYPE_FILE"
    echo "Available: $(ls "$TEMPLATES_DIR/types/"*.rasi 2>/dev/null | xargs -n1 basename | sed 's/\.rasi//')"
    exit 1
fi

# ── Validate color scheme ──────────────────────────────────────
COLOR_FILE="$TEMPLATES_DIR/colors/${COLOR_SCHEME}.rasi"
if [ ! -f "$COLOR_FILE" ]; then
    echo "Error: Color scheme '$COLOR_SCHEME' not found at $COLOR_FILE"
    echo "Available: $(ls "$TEMPLATES_DIR/colors/"*.rasi 2>/dev/null | xargs -n1 basename | sed 's/\.rasi//')"
    exit 1
fi

# ── Generate the assembled .rasi ──────────────────────────────
echo "→ Building theme: type=${THEME_TYPE}, color=${COLOR_SCHEME}"
echo "  Templates:  $TEMPLATES_DIR"
echo "  Defaults:   $DEFAULTS_FILE"
echo "  Config:     $USER_CONFIG_FILE"
echo "  Output:     $OUTPUT_DIR"

# Create output directories
mkdir -p "$OUTPUT_DIR/styles"

# ── 1. Read and assemble the type file ────────────────────────
# Read the type file, substitute the @import for colors
# The type file imports "_base.rasi", "_elements.rasi", "_widgets.rasi", "colors/nord.rasi"
# We'll inline all of those into a single output file.

assemble_rasi() {
    local input_file="$1"
    local output_file="$2"
    local color_file="$3"

    # Start with the core shared fragments
    {
        echo "/**"
        echo " * Auto-generated by build-theme.sh"
        echo " * Source: type=${THEME_TYPE}, color=${COLOR_SCHEME}"
        echo " */"
        echo ""

        # Inline _base.rasi (skip the *{} block marker and add the global block)
        if [ -f "$TEMPLATES_DIR/_base.rasi" ]; then
            # Check if _base.rasi starts with a comment; pass through fully
            cat "$TEMPLATES_DIR/_base.rasi"
            echo ""
        fi

        # Inline _elements.rasi
        if [ -f "$TEMPLATES_DIR/_elements.rasi" ]; then
            # Strip the heading comment from elements since we have our own
            grep -v "^/\*\*\*\*\*" "$TEMPLATES_DIR/_elements.rasi" 2>/dev/null || true
            echo ""
        fi

        # Inline _widgets.rasi
        if [ -f "$TEMPLATES_DIR/_widgets.rasi" ]; then
            grep -v "^/\*\*\*\*\*" "$TEMPLATES_DIR/_widgets.rasi" 2>/dev/null || true
            echo ""
        fi

        # Inline the color scheme
        if [ -f "$color_file" ]; then
            cat "$color_file"
            echo ""
        fi

        # Now read the type file, replacing @import lines with nothing
        # (since we've already inlined everything)
        sed -e 's/@import.*//' "$input_file"
    } > "$output_file"

    echo "   ✓ $output_file"
}

# ── 2. Build launcher theme ───────────────────────────────────
THEME_FILE="$OUTPUT_DIR/styles/${THEME_TYPE}.rasi"
assemble_rasi "$TYPE_FILE" "$THEME_FILE" "$COLOR_FILE"

# ── 3. Generate copy-to-config convenience ─────────────────────
echo ""
echo "→ Build complete. Output in: $OUTPUT_DIR"
echo ""
echo "To use:"
echo "  ln -sf \"$OUTPUT_DIR\" ~/.config/rofi"
echo ""
echo "Or copy:"
echo "  cp -r \"$OUTPUT_DIR/\"* ~/.config/rofi/"
