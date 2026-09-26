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

### Teil B – Kubernetes-Grundlagen 🚧
06 Erster Pod · 07 Deployments & Services · 08 Konfiguration & Daten · 09 Helm

### Teil C – Das Homelab-Herz 🚧
10 Tailscale Operator · 11 Jellyfin · 12 Jellyfin auf dem Samsung-TV · 13 GitOps mit Argo CD ·
14 Secrets im Git · 15 GPU an die VM durchreichen · 16 GPU in Kubernetes

### Teil D – *arr-Stack 🚧
17 Wie der *arr-Stack zusammenspielt · 18 qBittorrent + Proton VPN · 19 Prowlarr · 20 Sonarr & Radarr · 21 Bazarr & Jellyseerr

### Teil E – Weitere Apps 🚧
22 Homepage · 23 Vaultwarden · 24 Immich · 25 Paperless-ngx · 26 Uptime Kuma

### Teil F – Betrieb 🚧
27 Backup & Restore · 28 Updates & Wartung · 29 Troubleshooting-Handbuch

### Teil G – Ausbau 🚧
30 SSD nachrüsten · 31 Monitoring · 32 Mehr Nodes

📖 [Glossar](docs/glossar.md) · 🗺️ [Gesamtplan](PLAN.md)

## Repository-Struktur

```
docs/          Tutorial-Kapitel
kubernetes/    Cluster-Konfiguration für GitOps (ab Teil C)
examples/      Beispiel-Manifeste für Teil B
flake.nix      Werkzeuge für deinen Rechner (nix develop)
```
