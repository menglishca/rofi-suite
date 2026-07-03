# Plan: Three-Track Type System

## Overview

Reorganize the type template system into three tracks to properly represent the different widget compositions used by launchers, applets, and power menus in the original adi1090x/rofi repository.

---

## Current State

```
templates/
├── _base.rasi              ← shared variable mappings
├── _elements.rasi          ← shared element styling
├── _widgets.rasi           ← shared widget definitions
├── colors/                 ← shared color palettes (13 files)
└── types/                  ← 5 launcher types only
    ├── bordered.rasi
    ├── compact.rasi
    ├── horizontal.rasi
    ├── iconic.rasi
    └── rounded.rasi
```

**Problems:**
1. Missing 2 launcher types: `grid` (type-3) and `pill` (type-7)
2. Missing 6 power menu types (type-1 through type-6 in original)
3. Applets use launcher templates with wrong widgets (search bar, mode-switcher, element-icon)
4. No way to specify which widget set to use per applet

---

## Proposed Architecture

### Directory Structure

```
templates/
├── _base.rasi              ← shared (variable mappings)
├── _elements.rasi          ← shared (element styling)
├── _widgets.rasi           ← shared (widget definitions)
├── colors/                 ← shared (13 color palettes)
├── launcher-types/         ← full widget set (7 files)
│   ├── rounded.rasi        ← type-1: centered modal, 2-col grid, scrollbar
│   ├── compact.rasi        ← type-2: narrow 400px popup
│   ├── grid.rasi           ← type-3: glassmorphism 5-col icon grid (NEW)
│   ├── bordered.rasi       ← type-4: boxy, 1px border
│   ├── iconic.rasi         ← type-5: show-icons, 15 rows
│   ├── horizontal.rasi     ← type-6: horizontal orientation
│   └── pill.rasi           ← type-7: bg-image, circular elements (NEW)
├── applet-types/           ← simplified, no search/mode-switcher (7 files)
│   ├── rounded.rasi
│   ├── compact.rasi
│   ├── grid.rasi
│   ├── bordered.rasi
│   ├── iconic.rasi
│   ├── horizontal.rasi
│   └── pill.rasi
└── powermenu-types/        ← unique powermenu layouts (6 files)
    ├── centered.rasi       ← type-1: 400px centered column, 5 items
    ├── inline-grid.rasi    ← type-2: 800px horizontal 5-col grid
    ├── fullscreen.rasi     ← type-3: fullscreen overlay, CSS vars
    ├── pill.rasi           ← type-4: fullscreen overlay, pill buttons
    ├── hero.rasi           ← type-5: bg-image + 6-col grid
    └── split.rasi          ← type-6: imagebox left, list right
```

### Widget Composition by Track

| Component | Launcher | Applet | Powermenu |
|-----------|----------|--------|-----------|
| `configuration` | Full modi/display-*/format | Minimal | Minimal |
| `inputbar` | ✅ With search entry | ❌ | ❌ |
| `mode-switcher` | ✅ | ❌ | ❌ |
| `element-icon` | ✅ 24-64px | ❌ Text glyphs | ❌ Feather glyphs |
| Element states | 6 variants | 2 variants | 2 variants |
| `scrollbar` | Varies | ❌ | ❌ |
| `message` | ✅ | ✅ | ❌ |

### Build Output Convention

```
output/
└── styles/
    ├── launcher/                    ← launcher types
    │   ├── bordered-nord.rasi
    │   ├── rounded-dracula.rasi
    │   └── ...
    ├── applet/                      ← applet types
    │   ├── compact-nord.rasi
    │   ├── rounded-catppuccin.rasi
    │   └── ...
    └── powermenu/                   ← powermenu types
        ├── centered-nord.rasi
        ├── fullscreen-dracula.rasi
        └── ...
```

---

## Config Schema Changes

### defaults.json

Top-level keys per track, each with its own defaults:

```json
{
  "launcher_theme": {
    "type": "bordered",
    "color_scheme": "nord",
    "style_overrides": {}
  },
  "applet_theme": {
    "type": "rounded",
    "color_scheme": "nord"
  },
  "power_menu_theme": {
    "type": "centered",
    "color_scheme": "dracula"
  },
  "desktop": {
    "drun": { "theme": { "type": "horizontal" } },
    "run": { "theme": { "type": "compact" } },
    "filebrowser": {},
    "window": { "theme": { "type": "compact" } }
  },
  "applets": {
    "apps": {
      "theme": { "type": "rounded" },
      "prompt": { "message": "Applications", "icon": "" },
      ...
    },
    "powermenu": {
      "theme": { "type": "centered" },
      "prompt": { "message": "$(hostname)", "icon": "" },
      ...
    },
    "volume": {
      "theme": { "type": "compact" },
      ...
    }
  }
}
```

### Resolution Rules

1. Each track has its own global defaults: `launcher_theme`, `applet_theme`, `power_menu_theme`
2. Per-applet/desktop overrides inherit from their respective track defaults:
   - `desktop.*.theme` → inherits from `launcher_theme`
   - `applets.*.theme` (non-powermenu) → inherits from `applet_theme`
   - `applets.powermenu.theme` → inherits from `power_menu_theme`
3. Build-time: `styles/<track>/<type>-<color>.rasi`

---

## build-theme.sh Changes

### Auto-Discovery Logic

```
1. Read merged config
2. For each desktop mode:
   - Resolve type + color from launcher_theme defaults
   - Apply per-mode overrides
   - Add to combos: launcher|type|color
3. For each applet:
   - Determine track: "powermenu" if name contains "power", else "applet"
   - Resolve type + color from <track>_theme defaults
   - Apply per-applet overrides
   - Add to combos: <track>|type|color
4. Build each unique combo
```

### CLI Flags

```bash
# Build all combos (auto-discover)
./build-theme.sh

# Build specific track
./build-theme.sh --track launcher
./build-theme.sh --track powermenu

# Build specific combo
./build-theme.sh --track launcher --type rounded --color dracula
```

---

## Script Changes

### rofi-menu.sh

Add track-aware theme resolution:

```bash
resolve_theme() {
  local applet_name="$1"
  local merged="$2"
  
  # Determine track from applet name
  local track="applet"
  case "$applet_name" in
    *power*) track="powermenu" ;;
  esac
  
  # Get applet's theme override
  local type=$(echo "$merged" | jq -re ".applets.${applet_name}.theme.type // empty")
  local color=$(echo "$merged" | jq -re ".applets.${applet_name}.theme.color_scheme // empty")
  
  # Fall back to track-specific defaults
  local defaults_key="${track}_theme"
  type="${type:-$(echo "$merged" | jq -re ".${defaults_key}.type // "bordered"')}"
  color="${color:-$(echo "$merged" | jq -re ".${defaults_key}.color_scheme // "nord"')}"
  
  # Resolve path
  echo "$ROFI_CONFIG_DIR/styles/${track}/${type}-${color}.rasi"
}
```

### rofi-desktop.sh

Similar track-aware resolution (always uses "launcher" track):

```bash
resolve_theme() {
  local mode="$1"
  local merged="$2"
  
  # Desktop modes always use launcher track
  local type=$(echo "$merged" | jq -re ".desktop.${mode}.theme.type // empty")
  local color=$(echo "$merged" | jq -re ".desktop.${mode}.theme.color_scheme // empty")
  
  type="${type:-$(echo "$merged" | jq -re '.launcher_theme.type // "bordered"')}"
  color="${color:-$(echo "$merged" | jq -re '.launcher_theme.color_scheme // "nord"')}"
  
  echo "$ROFI_CONFIG_DIR/styles/launcher/${type}-${color}.rasi"
}
```

---

## Nix Module Changes

### nix/stylix.nix

Replace `themeType` with per-track theme options:

```nix
{
  # ... existing options ...
  
  # Track-specific theme defaults
  launcherTheme = lib.mkOption {
    type = lib.types.submodule {
      options = {
        type = lib.mkOption {
          type = lib.types.enum ["rounded" "compact" "grid" "bordered" "iconic" "horizontal" "pill"];
          default = "bordered";
          description = "Default launcher type";
        };
        color_scheme = lib.mkOption {
          type = lib.types.str;
          default = "nord";
          description = "Default launcher color scheme";
        };
      };
    };
    default = {};
    description = "Default launcher theme settings";
  };
  
  appletTheme = lib.mkOption {
    type = lib.types.submodule {
      options = {
        type = lib.mkOption {
          type = lib.types.enum ["rounded" "compact" "grid" "bordered" "iconic" "horizontal" "pill"];
          default = "rounded";
          description = "Default applet type";
        };
        color_scheme = lib.mkOption {
          type = lib.types.str;
          default = "nord";
          description = "Default applet color scheme";
        };
      };
    };
    default = {};
    description = "Default applet theme settings";
  };
  
  powerMenuTheme = lib.mkOption {
    type = lib.types.submodule {
      options = {
        type = lib.mkOption {
          type = lib.types.enum ["centered" "inline-grid" "fullscreen" "pill" "hero" "split"];
          default = "centered";
          description = "Default power menu type";
        };
        color_scheme = lib.mkOption {
          type = lib.types.str;
          default = "dracula";
          description = "Default power menu color scheme";
        };
      };
    };
    default = {};
    description = "Default power menu theme settings";
  };
  
  # Per-applet theme overrides (same as before)
  appletThemes = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        type = lib.mkOption {
          type = lib.types.str;
          default = null;
          description = "Applet-specific type override";
        };
        color_scheme = lib.mkOption {
          type = lib.types.str;
          default = null;
          description = "Applet-specific color scheme override";
        };
      };
    });
    default = {};
    example = {
      powermenu = { type = "centered"; color_scheme = "dracula"; };
      volume = { type = "compact"; };
    };
    description = "Per-applet theme overrides";
  };
}
```

---

## Implementation Steps

### Step 1: Create launcher-types/ directory

- Move existing 5 type files to `launcher-types/`
- Add `grid.rasi` (type-3: glassmorphism 5-col icon grid)
- Add `pill.rasi` (type-7: bg-image, circular elements)

### Step 2: Create applet-types/ directory

- Create simplified versions of all 7 launcher types
- Remove inputbar/search, mode-switcher, element-icon
- Use text glyphs for item labels
- Simpler element states (2 variants)

### Step 3: Create powermenu-types/ directory

- Create 6 unique powermenu layouts:
  - `centered.rasi` (type-1)
  - `inline-grid.rasi` (type-2)
  - `fullscreen.rasi` (type-3)
  - `pill.rasi` (type-4)
  - `hero.rasi` (type-5)
  - `split.rasi` (type-6)

### Step 4: Update defaults.json

- Replace `theme` with top-level keys: `launcher_theme`, `applet_theme`, `power_menu_theme`
- Each track gets its own `type`, `color_scheme`, `style_overrides`
- Update desktop/applet overrides to inherit from respective track defaults
- Add layout_overrides for powermenu types

### Step 5: Update build-theme.sh

- Add `--track` CLI flag
- Update auto-discovery to read from `<track>_theme` defaults
- Create track-specific output directories: `styles/<track>/`

### Step 6: Update rofi-menu.sh

- Add track-aware theme resolution using `<track>_theme` defaults
- Infer track from applet name (powermenu vs applet)
- Handle powermenu-specific layouts

### Step 7: Update rofi-desktop.sh

- Update to use `launcher_theme` defaults consistently
- Ensure backward compatibility

### Step 8: Update nix/stylix.nix

- Replace `themeType` with `launcherTheme`, `appletTheme`, `powerMenuTheme` options
- Update deployment to handle multi-track builds
- Update user_config generation with track-specific defaults

### Step 9: Update README.md

- Document three-track system
- Add powermenu type reference
- Update configuration examples with new schema

### Step 10: Test and validate

- Build all track combinations
- Test launcher, applet, and powermenu rendering
- Verify NixOS deployment works
