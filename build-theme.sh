#!/usr/bin/env bash
#
# build-theme.sh - Pre-bake static .rasi files from templates and config
#
# Usage: ./build-theme.sh                           # Auto-discover all type+color combos from config
#        ./build-theme.sh --type bordered --color nord  # Build a single specific combo
#        ./build-theme.sh --track launcher            # Build all launcher types
#        ./build-theme.sh --output ./my-theme
#
# When no --type/--color is given, the script reads the merged config
# (defaults.json + user_config.json) to discover all unique type+color
# combinations needed by desktop modes and applets, then builds each
# one as styles/<track>/<type>-<color>.rasi.
#
# Options:
#   --templates-dir DIR   Path to templates directory (default: ./templates)
#   --defaults FILE       Path to defaults.json (default: ./defaults.json)
#   --config FILE         Path to user_config.json (default: ./user_config.json)
#   --output DIR          Output directory (default: ./output)
#   --track TRACK         Theme track (launcher, applet, powermenu)
#   --type TYPE           Theme type — build only this type (e.g. bordered, rounded)
#   --color NAME          Color scheme — build only this color (e.g. nord, dracula)
#   --style JSON          Style overrides as JSON string
#   -h, --help            Show this help message

set -euo pipefail

# ── Paths (defaults, overridable via CLI) ──────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
OUTPUT_DIR="$SCRIPT_DIR/output"
DEFAULTS_FILE="$SCRIPT_DIR/defaults.json"
USER_CONFIG_FILE="$SCRIPT_DIR/user_config.json"

# ── Defaults ───────────────────────────────────────────────────
STYLE_OVERRIDES=""

# ── Parse command-line arguments ────────────────────────────────
show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Pre-bake static .rasi files from templates and config.

When called without --type/--color, discovers all unique type+color
combinations from the merged config and builds each one.

Options:
  --templates-dir DIR   Path to templates directory (default: ./templates)
  --defaults FILE       Path to defaults.json (default: ./defaults.json)
  --config FILE         Path to user_config.json (default: ./user_config.json)
  --output DIR          Output directory (default: ./output)
  --track TRACK         Theme track (launcher, applet, powermenu)
  --type TYPE           Build only this theme type (e.g. bordered, rounded)
  --color NAME          Build only this color scheme (e.g. nord, dracula)
  --style JSON          Style overrides as JSON string
  -h, --help            Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") --track launcher --type rounded --color catppuccin
  $(basename "$0") --track powermenu
  $(basename "$0") --templates-dir ~/my-templates --defaults ~/my-defaults.json
  $(basename "$0") --output ~/.config/rofi
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --track)          THEME_TRACK="$2"; _CLI_TRACK_SET=1; shift 2 ;;
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

# ── Assemble a single .rasi file ──────────────────────────────
#   $1 = track name (launcher, applet, powermenu)
#   $2 = type name
#   $3 = color scheme name
assemble_rasi() {
    local track_name="$1"
    local type_name="$2"
    local color_name="$3"

    local type_file="$TEMPLATES_DIR/${track_name}-types/${type_name}.rasi"
    local color_file="$TEMPLATES_DIR/colors/${color_name}.rasi"
    local output_file="$OUTPUT_DIR/styles/${track_name}/${type_name}-${color_name}.rasi"

    # Validate track directory
    if [ ! -d "$TEMPLATES_DIR/${track_name}-types" ]; then
        echo "Error: Track directory '$TEMPLATES_DIR/${track_name}-types' not found"
        echo "Available: $(ls -d "$TEMPLATES_DIR"/*-types 2>/dev/null | xargs -n1 basename | sed 's/-types//')"
        return 1
    fi

    # Validate type
    if [ ! -f "$type_file" ]; then
        echo "Error: Type '$type_name' not found at $type_file"
        echo "Available: $(ls "$TEMPLATES_DIR/${track_name}-types/"*.rasi 2>/dev/null | xargs -n1 basename | sed 's/\.rasi//')"
        return 1
    fi

    # Validate color scheme
    if [ ! -f "$color_file" ]; then
        echo "Error: Color scheme '$color_name' not found at $color_file"
        echo "Available: $(ls "$TEMPLATES_DIR/colors/"*.rasi 2>/dev/null | xargs -n1 basename | sed 's/\.rasi//')"
        return 1
    fi

    # Create output directory for track
    mkdir -p "$OUTPUT_DIR/styles/${track_name}"

    # Assemble the .rasi file by inlining all fragments
    {
        echo "/**"
        echo " * Auto-generated by build-theme.sh"
        echo " * Source: track=${track_name}, type=${type_name}, color=${color_name}"
        echo " */"
        echo ""

        # Inline _base.rasi
        if [ -f "$TEMPLATES_DIR/_base.rasi" ]; then
            cat "$TEMPLATES_DIR/_base.rasi"
            echo ""
        fi

        # Inline _elements.rasi
        if [ -f "$TEMPLATES_DIR/_elements.rasi" ]; then
            grep -v "^/\*\*\*\*\*" "$TEMPLATES_DIR/_elements.rasi" 2>/dev/null || true
            echo ""
        fi

        # Inline _widgets.rasi
        if [ -f "$TEMPLATES_DIR/_widgets.rasi" ]; then
            grep -v "^/\*\*\*\*\*" "$TEMPLATES_DIR/_widgets.rasi" 2>/dev/null || true
            echo ""
        fi

        # Inline the color scheme
        cat "$color_file"
        echo ""

        # Inline the type file, stripping @import lines (already inlined)
        sed -e 's/@import.*//' "$type_file"
    } > "$output_file"

    echo "   ✓ ${track_name}/${type_name}-${color_name}.rasi"
}

# ── Create output directory ────────────────────────────────────
mkdir -p "$OUTPUT_DIR/styles"

echo "→ Building theme(s)"
echo "  Templates:  $TEMPLATES_DIR"
echo "  Defaults:   $DEFAULTS_FILE"
echo "  Config:     $USER_CONFIG_FILE"
echo "  Output:     $OUTPUT_DIR"

if [ "${_CLI_TRACK_SET:-}" ] && [ "${_CLI_TYPE_SET:-}" ] && [ "${_CLI_COLOR_SET:-}" ]; then
    # ── Single-combination build with explicit track (all CLI args) ───────────
    echo ""
    assemble_rasi "$THEME_TRACK" "$THEME_TYPE" "$COLOR_SCHEME"

elif [ "${_CLI_TRACK_SET:-}" ] && [ "${_CLI_TYPE_SET:-}" ]; then
    # ── Track + type: pair with config defaults for color ──────────────────────
    RESOLVED_COLOR="${COLOR_SCHEME:-$(echo "$merged" | jq -re ".${THEME_TRACK}_theme.color_scheme // \"nord\"")}"
    echo ""
    assemble_rasi "$THEME_TRACK" "$THEME_TYPE" "$RESOLVED_COLOR"

elif [ "${_CLI_TRACK_SET:-}" ] && [ "${_CLI_COLOR_SET:-}" ]; then
    # ── Track + color: pair with config defaults for type ──────────────────────
    RESOLVED_TYPE="${THEME_TYPE:-$(echo "$merged" | jq -re ".${THEME_TRACK}_theme.type // \"bordered\"")}"
    echo ""
    assemble_rasi "$THEME_TRACK" "$RESOLVED_TYPE" "$COLOR_SCHEME"

elif [ "${_CLI_TRACK_SET:-}" ]; then
    # ── Track only: use config defaults for type and color ─────────────────────
    RESOLVED_TYPE="${THEME_TYPE:-$(echo "$merged" | jq -re ".${THEME_TRACK}_theme.type // \"bordered\"")}"
    RESOLVED_COLOR="${COLOR_SCHEME:-$(echo "$merged" | jq -re ".${THEME_TRACK}_theme.color_scheme // \"nord\"")}"
    echo ""
    assemble_rasi "$THEME_TRACK" "$RESOLVED_TYPE" "$RESOLVED_COLOR"

elif [ "${_CLI_TYPE_SET:-}" ] && [ "${_CLI_COLOR_SET:-}" ]; then
    # ── Type + color only (no track): assume launcher track ───────────────────
    echo ""
    assemble_rasi "launcher" "$THEME_TYPE" "$COLOR_SCHEME"

elif [ "${_CLI_TYPE_SET:-}" ] || [ "${_CLI_COLOR_SET:-}" ]; then
    # ── Partial CLI: assume launcher track ────────────────────────────────────
    RESOLVED_TYPE="${THEME_TYPE:-$(echo "$merged" | jq -re '.launcher_theme.type // "bordered"')}"
    RESOLVED_COLOR="${COLOR_SCHEME:-$(echo "$merged" | jq -re '.launcher_theme.color_scheme // "nord"')}"
    echo ""
    assemble_rasi "launcher" "$RESOLVED_TYPE" "$RESOLVED_COLOR"

else
    # ── Auto-discover all unique track+type+color combinations ────────────────
    # Collect combos from: launcher_theme, applet_theme, power_menu_theme,
    # desktop modes, and applets
    declare -A COMBOS  # keys are "track|type|color"

    # 1. Launcher theme default
    launcher_type=$(echo "$merged" | jq -re '.launcher_theme.type // "bordered"')
    launcher_color=$(echo "$merged" | jq -re '.launcher_theme.color_scheme // "nord"')
    COMBOS["launcher|${launcher_type}|${launcher_color}"]=1

    # 2. Applet theme default
    applet_type=$(echo "$merged" | jq -re '.applet_theme.type // "rounded"')
    applet_color=$(echo "$merged" | jq -re '.applet_theme.color_scheme // "nord"')
    COMBOS["applet|${applet_type}|${applet_color}"]=1

    # 3. Power menu theme default
    powermenu_type=$(echo "$merged" | jq -re '.power_menu_theme.type // "centered"')
    powermenu_color=$(echo "$merged" | jq -re '.power_menu_theme.color_scheme // "dracula"')
    COMBOS["powermenu|${powermenu_type}|${powermenu_color}"]=1

    # 4. Desktop modes (use launcher track)
    for mode in $(echo "$merged" | jq -r '.desktop // {} | keys[]' 2>/dev/null); do
        mode_type=$(echo "$merged" | jq -re ".desktop.${mode}.theme.type // empty" 2>/dev/null || true)
        mode_color=$(echo "$merged" | jq -re ".desktop.${mode}.theme.color_scheme // empty" 2>/dev/null || true)
        t="${mode_type:-$launcher_type}"
        c="${mode_color:-$launcher_color}"
        COMBOS["launcher|${t}|${c}"]=1
    done

    # 5. Applets (determine track from name or use applet_theme defaults)
    for applet in $(echo "$merged" | jq -r '.applets // {} | keys[]' 2>/dev/null); do
        override_type=$(echo "$merged" | jq -re ".applets.${applet}.theme.type // empty" 2>/dev/null || true)
        override_color=$(echo "$merged" | jq -re ".applets.${applet}.theme.color_scheme // empty" 2>/dev/null || true)
        
        # Determine track from applet name
        track="applet"
        case "$applet" in
            *power*) track="powermenu" ;;
        esac
        
        # Fall back to track-specific defaults
        if [ "$track" = "powermenu" ]; then
            t="${override_type:-$powermenu_type}"
            c="${override_color:-$powermenu_color}"
        else
            t="${override_type:-$applet_type}"
            c="${override_color:-$applet_color}"
        fi
        
        COMBOS["${track}|${t}|${c}"]=1
    done

    echo ""
    echo "  Discovered ${#COMBOS[@]} unique theme combination(s):"
    for combo in "${!COMBOS[@]}"; do
        IFS='|' read -r track t c <<< "$combo"
        echo "   • track=${track}, type=${t}, color=${c}"
    done
    echo ""

    for combo in "${!COMBOS[@]}"; do
        IFS='|' read -r track t c <<< "$combo"
        assemble_rasi "$track" "$t" "$c"
    done
fi

# ── Done ───────────────────────────────────────────────────────
echo ""
echo "→ Build complete. Output in: $OUTPUT_DIR"
echo ""
echo "To use:"
echo "  cp -r \"$OUTPUT_DIR/\"* ~/.config/rofi/"
echo ""
echo "Or symlink:"
echo "  ln -sf \"$OUTPUT_DIR/styles\" ~/.config/rofi/styles"
