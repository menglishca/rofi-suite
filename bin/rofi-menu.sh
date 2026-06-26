#!/usr/bin/env bash
#
# rofi-menu.sh - Custom data-driven menu runner
#
# Reads applet definitions from defaults.json merged with user_config.json
# and shows a rofi menu with a user-provided theme.
#
# Usage: rofi-menu.sh [options] <menu_name>
#   e.g.: rofi-menu.sh apps
#         rofi-menu.sh --theme /path/to/theme.rasi powermenu
#         rofi-menu.sh --config /path/to/user_config.json volume
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
POSITIONAL=()

show_help() {
    cat <<EOF
Usage: $(basename "$0") [options] <menu_name>

Custom data-driven menu runner. Reads applet definitions from
defaults.json merged with user_config.json and shows a rofi menu.

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
  $(basename "$0") apps
  $(basename "$0") --theme /path/to/theme.rasi powermenu
  $(basename "$0") --config /path/to/user_config.json volume
  $(basename "$0") --defaults /path/to/defaults.json --theme /path/to/theme.rasi apps
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)   CONFIG_FILE="$2"; shift 2 ;;
        --defaults) DEFAULTS_FILE="$2"; shift 2 ;;
        --theme)    THEME_FILE="$2"; shift 2 ;;
        --help|-h)  show_help; exit 0 ;;
        -*)         echo "Unknown option: $1"; echo "Try '$(basename "$0") --help'"; exit 1 ;;
        *)          POSITIONAL+=("$1"); shift ;;
    esac
done

# ── Require menu name ──────────────────────────────────────────
if [ ${#POSITIONAL[@]} -lt 1 ]; then
    echo "Error: No menu name specified"
    echo "Usage: $(basename "$0") [options] <menu_name>"
    echo "Try '$(basename "$0") --help' for more information."
    exit 1
fi

APPLET="${POSITIONAL[0]}"

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
fi

# ── Merge defaults + user config ───────────────────────────────
if [ -n "$CONFIG_FILE" ]; then
    ROFI_CONFIG=$(mktemp)
    trap "rm -f $ROFI_CONFIG" EXIT
    jq -s '.[0] * .[1]' "$DEFAULTS_FILE" "$CONFIG_FILE" > "$ROFI_CONFIG"
else
    ROFI_CONFIG="$DEFAULTS_FILE"
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

# ── Check jq ────────────────────────────────────────────────────
JQ=$(command -v jq 2>/dev/null || echo "none")
if [ "$JQ" = "none" ]; then
    echo "Error: jq is required. Install it with: sudo apt install jq"
    exit 1
fi

# ── Validate applet exists ──────────────────────────────────────
if ! jq -e ".applets.$APPLET" "$ROFI_CONFIG" >/dev/null 2>&1; then
    echo "Error: Menu '$APPLET' not found in configuration"
    echo "Available: $(jq -r '.applets | keys[]' "$ROFI_CONFIG")"
    exit 1
fi

# ── Extract theme type name from path ──────────────────────────
type_name=$(basename "$THEME_FILE" .rasi)

# ── Get layout overrides for current type from config ──────────
get_layout() {
    local key="$1"
    local layout_value
    layout_value=$(jq -r ".applets.$APPLET.layout_overrides.$type_name.$key // null" "$ROFI_CONFIG")
    # Fall back to type-level layout from theme section
    if [ "$layout_value" = "null" ] || [ -z "$layout_value" ]; then
        layout_value=$(jq -r ".applets.$APPLET.layout_overrides.$type_name.$key // 1" "$ROFI_CONFIG")
    fi
    echo "$layout_value"
}

list_col=$(get_layout "list_col")
list_row=$(get_layout "list_row")
win_width=$(get_layout "win_width" "")

# ── Build option arrays ────────────────────────────────────────
parse_options() {
    local count
    count=$(jq -r ".applets.$APPLET.options | length" "$ROFI_CONFIG")

    for i in $(seq 0 $((count - 1))); do
        # Read option fields
        local option_label_text option_label_icon
        option_label_text=$(jq -r ".applets.$APPLET.options[$i].label.text // \"\"" "$ROFI_CONFIG")
        option_label_icon=$(jq -r ".applets.$APPLET.options[$i].label.icon // \"\"" "$ROFI_CONFIG")
        option_cmd=$(jq -r ".applets.$APPLET.options[$i].command" "$ROFI_CONFIG")
        option_confirm=$(jq -r ".applets.$APPLET.options[$i].require_confirm // false" "$ROFI_CONFIG")

        # Resolve shell substitutions in both text and icon
        option_label_text=$(eval "echo \"$option_label_text\"" 2>/dev/null || echo "$option_label_text")
        option_label_icon=$(eval "echo \"$option_label_icon\"" 2>/dev/null || echo "$option_label_icon")

        if [ "$USE_ICON" = "YES" ]; then
            echo "LABEL:$option_label_icon"
        elif [ -n "$option_label_icon" ]; then
            echo "LABEL:${option_label_icon} ${option_label_text}"
        else
            echo "LABEL:$option_label_text"
        fi
        echo "CMD:$option_cmd"
        echo "CONFIRM:$option_confirm"
        echo "---"
    done
}

# ── Check USE_ICON ─────────────────────────────────────────────
USE_ICON="NO"
if [ -f "$THEME_FILE" ]; then
    USE_ICON=$(grep 'USE_ICON' "$THEME_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]') || true
fi

# ── Get prompt info ────────────────────────────────────────────
prompt=$(jq -r ".applets.$APPLET.prompt.message // \"$APPLET\"" "$ROFI_CONFIG")
prompt=$(eval "echo \"$prompt\"" 2>/dev/null || echo "$prompt")

message=$(jq -r ".applets.$APPLET.message // \"\"" "$ROFI_CONFIG")
message=$(eval "echo \"$message\"" 2>/dev/null || echo "$message")

prompt_icon=$(jq -r ".applets.$APPLET.prompt.icon // \"::\"" "$ROFI_CONFIG")

# ── Build rofi theme string ────────────────────────────────────
theme_str="listview {columns: $list_col; lines: $list_row;}"
if [ -n "${win_width:-}" ] && [ "$win_width" != "null" ]; then
    theme_str="window {width: $win_width;} $theme_str"
fi
theme_str="textbox-prompt-colon {str: \"$prompt_icon\";} $theme_str"

# ── Determine active/urgent states ────────────────────────────
# Each option can declare "urgent_check" or "active_check" commands.
# If the command exits 0, that option's index is highlighted.
active_indices=""
urgent_indices=""
option_count=$(jq -r ".applets.$APPLET.options | length" "$ROFI_CONFIG" 2>/dev/null)
for ((i=0; i<option_count; i++)); do
    urgent_check=$(jq -r ".applets.$APPLET.options[$i].urgent_check // empty" "$ROFI_CONFIG" 2>/dev/null)
    active_check=$(jq -r ".applets.$APPLET.options[$i].active_check // empty" "$ROFI_CONFIG" 2>/dev/null)
    if [ -n "$urgent_check" ] && eval "$urgent_check" 2>/dev/null; then
        urgent_indices="${urgent_indices:+$urgent_indices,}$i"
    fi
    if [ -n "$active_check" ] && eval "$active_check" 2>/dev/null; then
        active_indices="${active_indices:+$active_indices,}$i"
    fi
done

# ── Build the rofi dmenu ───────────────────────────────────────
rofi_cmd() {
    local args=()
    args+=(-theme-str "$theme_str")
    args+=(-dmenu)
    args+=(-p "$prompt")
    [ -n "$message" ] && args+=(-mesg "$message")
    args+=(-markup-rows)
    [ -n "$active_indices" ] && args+=(-a "$active_indices")
    [ -n "$urgent_indices" ] && args+=(-u "$urgent_indices")
    args+=(-theme "$THEME_FILE")
    rofi "${args[@]}"
}

# ── Confirmation dialog ────────────────────────────────────────
confirm_cmd() {
    local yes no
    yes=$(jq -r ".applets.$APPLET.confirm_yes // \" Yes\"" "$ROFI_CONFIG")
    no=$(jq -r ".applets.$APPLET.confirm_no // \" No\"" "$ROFI_CONFIG")

    printf '%s\n' "$yes" "$no" | rofi \
        -theme-str 'window {location: center; anchor: center; fullscreen: false; width: 350px;}' \
        -theme-str 'mainbox {orientation: vertical; children: [ "message", "listview" ];}' \
        -theme-str 'listview {columns: 2; lines: 1;}' \
        -theme-str 'element-text {horizontal-align: 0.5;}' \
        -theme-str 'textbox {horizontal-align: 0.5;}' \
        -dmenu \
        -p "$(jq -r ".applets.$APPLET.confirm_title // \"Confirmation\"" "$ROFI_CONFIG")" \
        -mesg "$(jq -r ".applets.$APPLET.confirm_message // \"Are you Sure?\"" "$ROFI_CONFIG")" \
        -theme "$THEME_FILE"
}

# ── Display menu and capture selection ─────────────────────────
# Parse options into arrays
declare -a option_labels=()
declare -a option_commands=()
declare -a option_confirm=()

while IFS= read -r line; do
    case "$line" in
        LABEL:*) option_labels+=("${line#LABEL:}") ;;
        CMD:*)   option_commands+=("${line#CMD:}") ;;
        CONFIRM:*) option_confirm+=("${line#CONFIRM:}") ;;
    esac
done < <(parse_options)

# Build menu text
menu_text=""
for label in "${option_labels[@]}"; do
    menu_text="${menu_text}${label}\n"
done
menu_text="${menu_text%\\n}"

# Show rofi
chosen=$(echo -e "$menu_text" | rofi_cmd)

# ── Match selection to option ─────────────────────────────────
selected_index=""
for i in "${!option_labels[@]}"; do
    if [ "$chosen" = "${option_labels[$i]}" ]; then
        selected_index=$i
        break
    fi
done

if [ -z "${selected_index:-}" ]; then
    exit 0
fi

# ── Confirm if needed ─────────────────────────────────────────
if [ "${option_confirm[$selected_index]}" = "true" ]; then
    user_confimration_result=$(confirm_cmd)
    target_confirmation_value=$(jq -r ".applets.$APPLET.confirm_yes // \" Yes\"" "$ROFI_CONFIG")
    if [ "$user_confimration_result" != "$target_confirmation_value" ]; then
        exit 0
    fi
fi

# ── Execute command ────────────────────────────────────────────
command=$(eval "echo \"${option_commands[$selected_index]}\"")

# Execute pre_commands if defined (before the main command)
if jq -e ".applets.$APPLET.options[$selected_index].pre_commands" "$ROFI_CONFIG" >/dev/null 2>&1; then
    for pre_command in $(jq -r ".applets.$APPLET.options[$selected_index].pre_commands[]" "$ROFI_CONFIG"); do
        eval "$pre_command" || true
    done
fi

eval "$command"
