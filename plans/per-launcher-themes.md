# Plan: Per-Launcher Theme Overrides

## Problem

The repo produces a single theme file shared across all launchers. No way to assign different type+color combinations to individual launchers.

## Root Cause

- [`build-theme.sh`](build-theme.sh:183) builds one file from one `--type` + `--color`
- [`defaults.json`](defaults.json:2-6) has a single global `theme.type` and `theme.color_scheme`
- Both launcher scripts resolve a single `theme.rasi`
- [`nix/stylix.nix`](nix/stylix.nix:192-193) deploys one `theme.rasi`

## Solution

### Config Schema

Per-applet and per-desktop-mode `theme` overrides in [`defaults.json`](defaults.json):

```json
{
  "theme": {
    "type": "bordered",
    "color_scheme": "nord",
    "style_overrides": {}
  },
  "desktop": {
    "drun": { "theme": { "type": "horizontal" } },
    "run": { "theme": { "type": "compact" } },
    "filebrowser": {},
    "window": { "theme": { "type": "compact" } }
  },
  "applets": {
    "powermenu": {
      "theme": { "type": "rounded", "color_scheme": "dracula" },
      "prompt": { ... },
      ...
    },
    "volume": {
      "prompt": { ... },
      ...
    }
  }
}
```

Each launcher can override `type`, `color_scheme`, or both. When a field is missing, the global `theme` value is used.

### Theme Resolution

1. Read merged config
2. Check launcher-specific `theme.type` and `theme.color_scheme`
3. Fall back to global `theme.type` and `theme.color_scheme`
4. Construct path: `styles/<type>-<color>.rasi`

### Build Output

`styles/<type>-<color>.rasi` for every unique combination found in the config. No `theme.rasi` fallback — everything uses the explicit naming convention.

---

## Implementation Steps

### Step 1: Update `defaults.json` config schema

Add `desktop` section with per-mode theme overrides. Add per-applet `theme` overrides.

Files: [`defaults.json`](defaults.json)

### Step 2: Update `build-theme.sh` for multi-combination builds

- Parse merged config to discover all unique type+color pairs
- Build each as `styles/<type>-<color>.rasi`
- Keep `--type`/`--color` CLI args for single-theme builds

Files: [`build-theme.sh`](build-theme.sh)

### Step 3: Update `rofi-menu.sh` with per-applet theme resolution

- Add `resolve_theme` function reading `applets.<name>.theme` with global fallback
- Resolve to `styles/<type>-<color>.rasi`

Files: [`bin/rofi-menu.sh`](bin/rofi-menu.sh)

### Step 4: Update `rofi-desktop.sh` with per-mode theme resolution

- Add `resolve_theme` function reading `desktop.<mode>.theme` with global fallback
- Resolve to `styles/<type>-<color>.rasi`

Files: [`bin/rofi-desktop.sh`](bin/rofi-desktop.sh)

### Step 5: Update Nix module for multi-theme deployment

- Deploy `styles/` directory instead of single `theme.rasi`
- Support per-launcher overrides in module options

Files: [`nix/stylix.nix`](nix/stylix.nix), [`nix/default.nix`](nix/default.nix)

### Step 6: Update README

Document new per-launcher theme override capability.

Files: [`README.md`](README.md)
