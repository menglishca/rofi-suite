# nix/default.nix — Package derivation for rofi-suite
#
# Builds the rofi-suite by running build-theme.sh and packaging
# the result along with scripts and config.
#
# Usage (from flake):
#   nix build .#default
#
# The build uses defaults.json + user_config.json from the source tree.
# To customize the theme, override via preBuild hook or postPatch to
# inject config files before build-theme.sh runs.

{ lib
, stdenv
, bash
, jq
, src ? ./..
}:

stdenv.mkDerivation {
  pname = "rofi-suite";
  version = "unstable";

  inherit src;

  nativeBuildInputs = [ bash jq ];

  postPatch = ''
    chmod +x build-theme.sh 2>/dev/null || true
    chmod +x bin/* 2>/dev/null || true
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    bash ./build-theme.sh --output "$out/share/rofi-suite"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/rofi-suite/bin"

    # Install scripts
    if [ -d bin ]; then
      cp -r bin/* "$out/share/rofi-suite/bin/"
      chmod +x "$out/share/rofi-suite/bin/"*
    fi

    # Install config files
    cp defaults.json "$out/share/rofi-suite/" 2>/dev/null || true

    runHook postInstall
  '';

  meta = with lib; {
    description = "Modular rofi theme suite — DRY, config-driven, NixOS-friendly";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
