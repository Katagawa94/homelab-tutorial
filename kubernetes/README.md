# kubernetes/: die Konfiguration deines Homelabs

Alles in diesem Ordner beschreibt, was im Cluster läuft. **Argo CD** liest ihn und gleicht den Cluster
daran an (GitOps, [Kapitel 11](../docs/11-argocd.md)).

| Ordner | Inhalt |
|--------|--------|
| [`bootstrap/`](bootstrap/) | `root.yaml`: die Wurzel-Application, einmalig mit `kubectl apply` angelegt |
| [`katalog/`](katalog/) | Argo-CD-Applications für **alle** verfügbaren Apps (Vorlagen) |
| [`aktiv/`](aktiv/) | Applications, die **wirklich laufen sollen**. Aktivieren = Datei aus `katalog/` hierher kopieren |
| [`infrastructure/`](infrastructure/) | Einstellungen (Helm-Values) für Argo CD, Tailscale Operator, Sealed Secrets, NVIDIA |
| [`apps/`](apps/) | Eigene Manifeste für die Apps (Kustomize), z. B. Vaultwarden, Nextcloud, Jellyfin |
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
| `tailscale-operator.yaml` | 10 (erst per Helm, ab 11 über Argo CD) |
| `argocd.yaml`, `hallo.yaml` | 11 (`hallo` ist nur eine Demo und wird wieder entfernt) |
| `sealed-secrets.yaml`, `secrets.yaml` | 12 |
| `vaultwarden.yaml` | 13 |
| `nextcloud.yaml` | 14 (braucht `secrets/nextcloud/nextcloud-secrets.yaml` und den Ordner `/data/nextcloud` in der VM) |
| `pihole.yaml` | 15 (braucht `secrets/pihole/pihole-secrets.yaml`) |
| `media-basis.yaml`, `jellyfin.yaml` | 16 |
| `nvidia-device-plugin.yaml` | 19 |
| `qbittorrent.yaml` | 21 (braucht das SealedSecret `secrets/media/gluetun-protonvpn.yaml`) |
| `prowlarr.yaml` | 22 |
| `sonarr.yaml`, `radarr.yaml` | 23 |
| `bazarr.yaml`, `seerr.yaml` | 24 |
| `homepage.yaml` | 25 (optional: SealedSecret `secrets/homepage/homepage-keys.yaml`) |
| `immich.yaml` | 26 (braucht `secrets/immich/immich-db.yaml` und den Ordner `/data/photos` in der VM) |
| `paperless.yaml` | 27 (braucht `secrets/paperless/paperless-secrets.yaml`) |
| `uptime-kuma.yaml` | 28 |
| `backup.yaml` | 29 (braucht `secrets/backup/restic-backup.yaml` und den Benutzer `restic` auf Proxmox) |
| `monitoring.yaml` | 33 (braucht `secrets/monitoring/grafana-admin.yaml`) |

> **Tailnet-Name:** Einige Manifeste enthalten den Platzhalter `tail1a2b3c.ts.net`. Er wird in Kapitel 13 einmalig in `kubernetes/apps/`
> durch deinen Tailnet-Namen ersetzt.
