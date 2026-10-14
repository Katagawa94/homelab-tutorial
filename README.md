# 🏠 Homelab-Tutorial: Kubernetes lernen mit Jellyfin & Tailscale

Ein Schritt-für-Schritt-Tutorial **für Einsteiger**: Aus einem alten Desktop-PC wird mit **Proxmox** und
**Kubernetes (k3s)** ein Homelab. Zuerst kommen die wichtigsten Dienste: **Vaultwarden** (Passwörter),
**Nextcloud** (eigene Cloud) und **Pi-hole** (Werbeblocker). Danach **Jellyfin** (auch auf dem Samsung-TV, mit
GPU-Transcoding), der ***arr-Stack** mit Proton VPN und weitere Self-Hosted-Apps, alles von unterwegs sicher erreichbar
über **Tailscale**.

Das eigentliche Ziel: **Kubernetes lernen**, an Apps, die du danach wirklich benutzt.

📖 **Als Website lesen (mit Suche und Navigation):** <https://katagawa94.github.io/homelab-tutorial/>

```
Alter Desktop-PC ─► Proxmox VE ─► VM (Ubuntu) ─► k3s ─► Vaultwarden, Nextcloud, Pi-hole, Jellyfin, *arr, …
                                                          ▲
                              Laptop / Handy ── Tailscale ┘   Samsung-TV ── Heimnetz
```

## Voraussetzungen

- Ein alter PC (hier: Ryzen 5, 16 GB RAM, RTX 2070 Super, 500 GB SSD + 1 TB HDD)
- Ein eigener Rechner mit Linux, macOS oder Windows. Die Werkzeuge liefert unter Nix die [`flake.nix`](flake.nix) (`nix develop`)
- Keine Kubernetes-Vorkenntnisse. Grundlegende Terminal-Erfahrung hilft

## Inhalt

➡️ **Los geht's mit [00 – Einführung](docs/00-einfuehrung.md).** Alle 37 Kapitel (00–36) sind fertig.

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

### Teil C – Die Plattform ✅
| # | Kapitel |
|---|---------|
| 10 | [Tailscale Operator](docs/10-tailscale-operator.md) |
| 11 | [GitOps mit Argo CD](docs/11-argocd.md) |
| 12 | [Secrets im Git](docs/12-sealed-secrets.md) |

### Teil D – Die wichtigsten Dienste ✅
| # | Kapitel |
|---|---------|
| 13 | [Vaultwarden](docs/13-vaultwarden.md) |
| 14 | [Nextcloud](docs/14-nextcloud.md) |
| 15 | [Pi-hole](docs/15-pihole.md) |

### Teil E – Heimkino und *arr-Stack ✅
| # | Kapitel |
|---|---------|
| 16 | [Jellyfin](docs/16-jellyfin.md) |
| 17 | [Jellyfin auf dem Samsung-TV](docs/17-samsung-tv.md) |
| 18 | [GPU an die VM durchreichen](docs/18-gpu-passthrough.md) |
| 19 | [GPU in Kubernetes](docs/19-gpu-kubernetes.md) |
| 20 | [Wie der *arr-Stack zusammenspielt](docs/20-arr-ueberblick.md) |
| 21 | [qBittorrent + Proton VPN](docs/21-qbittorrent-vpn.md) |
| 22 | [Prowlarr](docs/22-prowlarr.md) |
| 23 | [Sonarr & Radarr](docs/23-sonarr-radarr.md) |
| 24 | [Bazarr & Seerr](docs/24-bazarr-seerr.md) |

### Teil F – Weitere Apps ✅
| # | Kapitel |
|---|---------|
| 25 | [Homepage](docs/25-homepage.md) |
| 26 | [Immich](docs/26-immich.md) |
| 27 | [Paperless-ngx](docs/27-paperless.md) |
| 28 | [Uptime Kuma](docs/28-uptime-kuma.md) |

### Teil G – Betrieb ✅
| # | Kapitel |
|---|---------|
| 29 | [Backup & Restore](docs/29-backup-restore.md) |
| 30 | [Updates & Wartung](docs/30-updates-wartung.md) |
| 31 | [Troubleshooting-Handbuch](docs/31-troubleshooting.md) |

### Teil H – Ausbau ✅
| # | Kapitel |
|---|---------|
| 32 | [Speicher erweitern](docs/32-speicher-erweitern.md) |
| 33 | [Monitoring mit Prometheus & Grafana](docs/33-monitoring.md) |
| 34 | [Mehr Nodes](docs/34-mehr-nodes.md) |
| 35 | [Strom sparen](docs/35-strom-sparen.md) |

### Teil I – Ein anderer Weg (optional)
| # | Kapitel |
|---|---------|
| 36 | [NixOS-Server auf dem ThinkPad](docs/36-nixos-thinkpad.md) |
📖 [Glossar](docs/glossar.md) · 🗺️ [Gesamtplan](PLAN.md)

## Repository-Struktur

```
docs/          Tutorial-Kapitel
kubernetes/    Die echte Cluster-Konfiguration, von Argo CD ausgerollt (ab Teil C)
nixos/         NixOS-Server auf dem ThinkPad als Code (Kapitel 36)
examples/      Lern- und Test-Manifeste
scripts/       Hilfsskripte (validate.sh prüft alle Manifeste, validate-nixos.sh die NixOS-Konfiguration)
flake.nix      Werkzeuge für deinen Rechner (nix develop)
mkdocs.yml     Website (GitHub Pages): lokal ansehen mit `mkdocs serve`
```
