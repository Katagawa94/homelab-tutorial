# kubernetes/: die Konfiguration deines Homelabs

Alles in diesem Ordner beschreibt, was im Cluster läuft. **Argo CD** liest ihn und gleicht den Cluster
daran an (GitOps, [Kapitel 13](../docs/13-argocd.md)).

| Ordner | Inhalt |
|--------|--------|
| [`bootstrap/`](bootstrap/) | `root.yaml`: die Wurzel-Application, einmalig mit `kubectl apply` angelegt |
| [`katalog/`](katalog/) | Argo-CD-Applications für **alle** verfügbaren Apps (Vorlagen) |
| [`aktiv/`](aktiv/) | Applications, die **wirklich laufen sollen**. Aktivieren = Datei aus `katalog/` hierher kopieren |
| [`infrastructure/`](infrastructure/) | Einstellungen (Helm-Values) für Argo CD, Tailscale Operator, Sealed Secrets, NVIDIA |
| [`apps/`](apps/) | Eigene Manifeste für die Apps (Kustomize), z. B. Jellyfin |
| [`secrets/`](secrets/) | Verschlüsselte Secrets (SealedSecrets), sortiert nach Namespace |

## Arbeitsablauf

```bash
# ändern …
git add -A && git commit -m "Was ich geändert habe" && git push
# … Argo CD rollt es innerhalb von 3 Minuten aus (oder sofort per "Refresh")
```

Vor dem Push prüfen, ob alle Manifeste gültig sind:

```bash
scripts/validate.sh
```

## Welche App gehört zu welchem Kapitel?

| Datei in `katalog/` | Kapitel |
|---------------------|---------|
| `tailscale-operator.yaml` | 10 (erst per Helm, ab 13 über Argo CD) |
| `media-basis.yaml`, `jellyfin.yaml` | 11 (erst per `kubectl`, ab 13 über Argo CD) |
| `argocd.yaml` | 13 |
| `sealed-secrets.yaml`, `secrets.yaml` | 14 |
| `nvidia-device-plugin.yaml` | 16 |
| `qbittorrent.yaml` | 18 (braucht das SealedSecret `secrets/media/gluetun-protonvpn.yaml`) |
| `prowlarr.yaml` | 19 |
| `sonarr.yaml`, `radarr.yaml` | 20 |
| `bazarr.yaml`, `seerr.yaml` | 21 |
| `homepage.yaml` | 22 (optional: SealedSecret `secrets/homepage/homepage-keys.yaml`) |
| `vaultwarden.yaml` | 23 |
| `immich.yaml` | 24 (braucht `secrets/immich/immich-db.yaml` und den Ordner `/data/photos` in der VM) |
| `paperless.yaml` | 25 (braucht `secrets/paperless/paperless-secrets.yaml`) |
| `uptime-kuma.yaml` | 26 |

> **Tailnet-Name:** Einige Manifeste enthalten den Platzhalter `tail1a2b3c.ts.net`. Er wird in Kapitel 22 einmalig in `kubernetes/apps/`
> durch deinen Tailnet-Namen ersetzt.
