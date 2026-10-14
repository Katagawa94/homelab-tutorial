#!/usr/bin/env bash
# Prüft, ob sich die NixOS-Konfiguration (nixos/, Kapitel 36) auswerten lässt, ohne etwas zu bauen.
# Dafür werden der SSH-Schlüssel und secrets.yaml in einer Kopie durch Platzhalter ersetzt.
# Benötigt: nix. Weitere Argumente gehen direkt an "nix eval" (z. B. --override-input).
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -r nixos/. "$tmp"
sed -i 's/AAAA-HIER-DEINEN-SCHLUESSEL-EINFUEGEN/AAAAC3NzaC1lZDI1NTE5AAAAIPlatzhalterFuerDieCI/' "$tmp/thinkpad/settings.nix"
[[ -f "$tmp/thinkpad/secrets.yaml" ]] || echo "tailscale-authkey: platzhalter" > "$tmp/thinkpad/secrets.yaml"

host=$(sed -n 's/^ *hostName = "\(.*\)";/\1/p' nixos/thinkpad/settings.nix)
echo "▶ nix eval nixosConfigurations.$host"
nix eval --extra-experimental-features 'nix-command flakes' "$@" \
  "path:$tmp#nixosConfigurations.$host.config.system.build.toplevel.drvPath"
echo "✅ NixOS-Konfiguration lässt sich auswerten"
