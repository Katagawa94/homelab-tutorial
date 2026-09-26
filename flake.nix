{
  description = "Homelab-Tutorial: alle Werkzeuge für deinen Rechner (nix develop)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            # Kubernetes
            kubectl          # Kubernetes steuern
            kubernetes-helm  # Helm-Charts installieren (Kapitel 09)
            k9s              # Terminal-Oberfläche für den Cluster (Kapitel 06)
            kubectx          # schnell zwischen Clustern/Namespaces wechseln
            kustomize        # Manifeste zusammensetzen
            stern            # Logs mehrerer Pods gleichzeitig ansehen
            kubeseal         # Sealed Secrets verschlüsseln (Kapitel 14)
            argocd           # Argo-CD-CLI (Kapitel 13)

            # Prüfen (scripts/validate.sh)
            kubeconform      # Manifeste gegen Kubernetes-Schemas prüfen
            yamllint         # YAML-Stil prüfen

            # Allgemeine Helfer
            jq               # JSON lesen
            yq-go            # YAML lesen
          ];

          shellHook = ''
            echo "🏠 Homelab-Werkzeuge geladen: kubectl, helm, k9s, kubeseal, argocd, …"
          '';
        };
      });
    };
}
