#!/usr/bin/env bash
# Prüft alle Kubernetes-Manifeste in examples/ und kubernetes/.
# Benötigt: kubeconform, kustomize (lokal z. B. per "nix develop", in der CI automatisch).
set -euo pipefail
cd "$(dirname "$0")/.."

KUBECONFORM=(kubeconform -strict -summary
  -schema-location default
  # Schemas für Argo CD Applications, SealedSecrets & Co.
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json')

# 1. Ordner mit kustomization.yaml: erst zusammensetzen, dann prüfen
mapfile -t kustomize_dirs < <(find examples kubernetes -name kustomization.yaml -exec dirname {} \; | sort)
for dir in "${kustomize_dirs[@]}"; do
  echo "▶ kustomize build $dir"
  kustomize build "$dir" | "${KUBECONFORM[@]}" -
done

# 2. Alle übrigen YAML-Dateien einzeln prüfen.
#    Übersprungen: Helm-Values, Kustomize-Ordner (schon geprüft) und Patches.
mapfile -t files < <(
  find examples kubernetes -name '*.yaml' \
    ! -name 'values.yaml' ! -name '*-values.yaml' ! -name '*-patch.yaml' | sort
)
plain=()
for f in "${files[@]}"; do
  skip=false
  for dir in "${kustomize_dirs[@]}"; do
    [[ "$f" == "$dir"/* ]] && skip=true
  done
  $skip || plain+=("$f")
done
echo "▶ ${#plain[@]} einzelne Dateien"
"${KUBECONFORM[@]}" "${plain[@]}"

# 3. Den GPU-Patch testweise mitbauen, damit er nicht erst in Kapitel 16 auffällt
echo "▶ Jellyfin mit GPU-Patch"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -r kubernetes/apps/media/jellyfin/. "$tmp"
sed -i 's/^# patches:/patches:/; s/^#   - path: gpu-patch.yaml/  - path: gpu-patch.yaml/' "$tmp/kustomization.yaml"
grep -q '^patches:' "$tmp/kustomization.yaml"
kustomize build "$tmp" | tee "$tmp/out.yaml" | "${KUBECONFORM[@]}" -
grep -q 'nvidia.com/gpu: 1' "$tmp/out.yaml"

echo "✅ Alles gültig"
