# 🏠 Homelab-Tutorial

Ein Schritt-für-Schritt-Tutorial **für Einsteiger**: Aus einem alten Desktop-PC wird mit **Proxmox** und
**Kubernetes (k3s)** ein Homelab. Darauf laufen **Jellyfin** (auch auf dem Samsung-TV, mit GPU-Transcoding),
der ***arr-Stack** mit Proton VPN und weitere Self-Hosted-Apps, von unterwegs sicher erreichbar über **Tailscale**.

Das eigentliche Ziel: **Kubernetes lernen**, an Apps, die du danach wirklich benutzt.


```
Alter Desktop-PC ─► Proxmox VE ─► VM (Ubuntu) ─► k3s ─► Jellyfin, *arr, Vaultwarden, Immich, …
                                                          ▲
                              Laptop / Handy ── Tailscale ┘   Samsung-TV ── Heimnetz
```

## Voraussetzungen

- Ein alter PC (hier: Ryzen 5, 16 GB RAM, RTX 2070 Super, 500 GB HDD)
- Ein eigener Rechner mit Linux, macOS oder Windows. Die Werkzeuge liefert unter Nix die [`flake.nix`](../flake.nix) (`nix develop`)
- Keine Kubernetes-Vorkenntnisse. Grundlegende Terminal-Erfahrung hilft

## Inhalt

➡️ **Los geht's mit [00 – Einführung](00-einfuehrung.md).** Alle 33 Kapitel (00–32) sind fertig.

### Teil A – Fundament ✅
| # | Kapitel |
|---|---------|
| 00 | [Einführung](00-einfuehrung.md) |
| 01 | [Voraussetzungen](01-voraussetzungen.md) |
| 02 | [Proxmox installieren](02-proxmox-installieren.md) |
| 03 | [Tailscale auf Proxmox](03-tailscale-proxmox.md) |
| 04 | [Die Kubernetes-VM](04-kubernetes-vm.md) |
| 05 | [k3s installieren](05-k3s-installieren.md) |

### Teil B – Kubernetes-Grundlagen ✅
| # | Kapitel |
|---|---------|
| 06 | [Erster Pod](06-erster-pod.md) |
| 07 | [Deployments & Services](07-deployments-services.md) |
| 08 | [Konfiguration & Daten](08-konfiguration-daten.md) |
| 09 | [Helm](09-helm.md) |

### Teil C – Das Homelab-Herz ✅
| # | Kapitel |
|---|---------|
| 10 | [Tailscale Operator](10-tailscale-operator.md) |
| 11 | [Jellyfin](11-jellyfin.md) |
| 12 | [Jellyfin auf dem Samsung-TV](12-samsung-tv.md) |
| 13 | [GitOps mit Argo CD](13-argocd.md) |
| 14 | [Secrets im Git](14-sealed-secrets.md) |
| 15 | [GPU an die VM durchreichen](15-gpu-passthrough.md) |
| 16 | [GPU in Kubernetes](16-gpu-kubernetes.md) |

### Teil D – *arr-Stack ✅
| # | Kapitel |
|---|---------|
| 17 | [Wie der *arr-Stack zusammenspielt](17-arr-ueberblick.md) |
| 18 | [qBittorrent + Proton VPN](18-qbittorrent-vpn.md) |
| 19 | [Prowlarr](19-prowlarr.md) |
| 20 | [Sonarr & Radarr](20-sonarr-radarr.md) |
| 21 | [Bazarr & Seerr](21-bazarr-seerr.md) |

### Teil E – Weitere Apps ✅
| # | Kapitel |
|---|---------|
| 22 | [Homepage](22-homepage.md) |
| 23 | [Vaultwarden](23-vaultwarden.md) |
| 24 | [Immich](24-immich.md) |
| 25 | [Paperless-ngx](25-paperless.md) |
| 26 | [Uptime Kuma](26-uptime-kuma.md) |

### Teil F – Betrieb ✅
| # | Kapitel |
|---|---------|
| 27 | [Backup & Restore](27-backup-restore.md) |
| 28 | [Updates & Wartung](28-updates-wartung.md) |
| 29 | [Troubleshooting-Handbuch](29-troubleshooting.md) |

### Teil G – Ausbau ✅
| # | Kapitel |
|---|---------|
| 30 | [SSD nachrüsten](30-ssd-nachruesten.md) |
| 31 | [Monitoring mit Prometheus & Grafana](31-monitoring.md) |
| 32 | [Mehr Nodes](32-mehr-nodes.md) |

📖 [Glossar](glossar.md) · 🗺️ [Gesamtplan](../PLAN.md)

## Repository-Struktur

```
docs/          Tutorial-Kapitel
kubernetes/    Die echte Cluster-Konfiguration, von Argo CD ausgerollt (ab Teil C)
examples/      Lern- und Test-Manifeste
scripts/       Hilfsskripte (validate.sh prüft alle Manifeste)
flake.nix      Werkzeuge für deinen Rechner (nix develop)
mkdocs.yml     Website (GitHub Pages): lokal ansehen mit `mkdocs serve`
```
