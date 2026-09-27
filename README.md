# 🏠 Homelab-Tutorial: Kubernetes lernen mit Jellyfin & Tailscale

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
- Ein eigener Rechner mit Linux, macOS oder Windows. Die Werkzeuge liefert unter Nix die [`flake.nix`](flake.nix) (`nix develop`)
- Keine Kubernetes-Vorkenntnisse. Grundlegende Terminal-Erfahrung hilft

## Inhalt

### Teil A – Fundament ✅
| # | Kapitel |
|---|---------|
| 00 | [Einführung](docs/00-einfuehrung.md) |
| 01 | [Voraussetzungen](docs/01-voraussetzungen.md) |
| 02 | [Proxmox installieren](docs/02-proxmox-installieren.md) |
| 03 | [Tailscale auf Proxmox](docs/03-tailscale-proxmox.md) |
| 04 | [Die Kubernetes-VM](docs/04-kubernetes-vm.md) |
| 05 | [k3s installieren](docs/05-k3s-installieren.md) |

### Teil B – Kubernetes-Grundlagen ✅
| # | Kapitel |
|---|---------|
| 06 | [Erster Pod](docs/06-erster-pod.md) |
| 07 | [Deployments & Services](docs/07-deployments-services.md) |
| 08 | [Konfiguration & Daten](docs/08-konfiguration-daten.md) |
| 09 | [Helm](docs/09-helm.md) |

### Teil C – Das Homelab-Herz ✅
| # | Kapitel |
|---|---------|
| 10 | [Tailscale Operator](docs/10-tailscale-operator.md) |
| 11 | [Jellyfin](docs/11-jellyfin.md) |
| 12 | [Jellyfin auf dem Samsung-TV](docs/12-samsung-tv.md) |
| 13 | [GitOps mit Argo CD](docs/13-argocd.md) |
| 14 | [Secrets im Git](docs/14-sealed-secrets.md) |
| 15 | [GPU an die VM durchreichen](docs/15-gpu-passthrough.md) |
| 16 | [GPU in Kubernetes](docs/16-gpu-kubernetes.md) |

### Teil D – *arr-Stack ✅
| # | Kapitel |
|---|---------|
| 17 | [Wie der *arr-Stack zusammenspielt](docs/17-arr-ueberblick.md) |
| 18 | [qBittorrent + Proton VPN](docs/18-qbittorrent-vpn.md) |
| 19 | [Prowlarr](docs/19-prowlarr.md) |
| 20 | [Sonarr & Radarr](docs/20-sonarr-radarr.md) |
| 21 | [Bazarr & Seerr](docs/21-bazarr-seerr.md) |

### Teil E – Weitere Apps ✅
| # | Kapitel |
|---|---------|
| 22 | [Homepage](docs/22-homepage.md) |
| 23 | [Vaultwarden](docs/23-vaultwarden.md) |
| 24 | [Immich](docs/24-immich.md) |
| 25 | [Paperless-ngx](docs/25-paperless.md) |
| 26 | [Uptime Kuma](docs/26-uptime-kuma.md) |

### Teil F – Betrieb 🚧
27 Backup & Restore · 28 Updates & Wartung · 29 Troubleshooting-Handbuch

### Teil G – Ausbau 🚧
30 SSD nachrüsten · 31 Monitoring · 32 Mehr Nodes

📖 [Glossar](docs/glossar.md) · 🗺️ [Gesamtplan](PLAN.md)

## Repository-Struktur

```
docs/          Tutorial-Kapitel
kubernetes/    Die echte Cluster-Konfiguration, von Argo CD ausgerollt (ab Teil C)
examples/      Lern- und Test-Manifeste
scripts/       Hilfsskripte (validate.sh prüft alle Manifeste)
flake.nix      Werkzeuge für deinen Rechner (nix develop)
```
