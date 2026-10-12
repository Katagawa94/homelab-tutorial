# 🏠 Homelab-Tutorial

Ein Schritt-für-Schritt-Tutorial **für Einsteiger**: Aus einem alten Desktop-PC wird mit **Proxmox** und
**Kubernetes (k3s)** ein Homelab. Zuerst kommen die wichtigsten Dienste: **Vaultwarden** (Passwörter),
**Nextcloud** (eigene Cloud) und **Pi-hole** (Werbeblocker). Danach **Jellyfin** (auch auf dem Samsung-TV, mit
GPU-Transcoding), der ***arr-Stack** mit Proton VPN und weitere Self-Hosted-Apps, alles von unterwegs sicher erreichbar
über **Tailscale**.

Das eigentliche Ziel: **Kubernetes lernen**, an Apps, die du danach wirklich benutzt.


```
Alter Desktop-PC ─► Proxmox VE ─► VM (Ubuntu) ─► k3s ─► Vaultwarden, Nextcloud, Pi-hole, Jellyfin, *arr, …
                                                          ▲
                              Laptop / Handy ── Tailscale ┘   Samsung-TV ── Heimnetz
```

## Voraussetzungen

- Ein alter PC (hier: Ryzen 5, 16 GB RAM, RTX 2070 Super, 500 GB SSD + 1 TB HDD)
- Ein eigener Rechner mit Linux, macOS oder Windows. Die Werkzeuge liefert unter Nix die [`flake.nix`](../flake.nix) (`nix develop`)
- Keine Kubernetes-Vorkenntnisse. Grundlegende Terminal-Erfahrung hilft

## Inhalt

➡️ **Los geht's mit [00 – Einführung](00-einfuehrung.md).** Alle 36 Kapitel (00–35) sind fertig.

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

### Teil C – Die Plattform ✅
| # | Kapitel |
|---|---------|
| 10 | [Tailscale Operator](10-tailscale-operator.md) |
| 11 | [GitOps mit Argo CD](11-argocd.md) |
| 12 | [Secrets im Git](12-sealed-secrets.md) |

### Teil D – Die wichtigsten Dienste ✅
| # | Kapitel |
|---|---------|
| 13 | [Vaultwarden](13-vaultwarden.md) |
| 14 | [Nextcloud](14-nextcloud.md) |
| 15 | [Pi-hole](15-pihole.md) |

### Teil E – Heimkino und *arr-Stack ✅
| # | Kapitel |
|---|---------|
| 16 | [Jellyfin](16-jellyfin.md) |
| 17 | [Jellyfin auf dem Samsung-TV](17-samsung-tv.md) |
| 18 | [GPU an die VM durchreichen](18-gpu-passthrough.md) |
| 19 | [GPU in Kubernetes](19-gpu-kubernetes.md) |
| 20 | [Wie der *arr-Stack zusammenspielt](20-arr-ueberblick.md) |
| 21 | [qBittorrent + Proton VPN](21-qbittorrent-vpn.md) |
| 22 | [Prowlarr](22-prowlarr.md) |
| 23 | [Sonarr & Radarr](23-sonarr-radarr.md) |
| 24 | [Bazarr & Seerr](24-bazarr-seerr.md) |

### Teil F – Weitere Apps ✅
| # | Kapitel |
|---|---------|
| 25 | [Homepage](25-homepage.md) |
| 26 | [Immich](26-immich.md) |
| 27 | [Paperless-ngx](27-paperless.md) |
| 28 | [Uptime Kuma](28-uptime-kuma.md) |

### Teil G – Betrieb ✅
| # | Kapitel |
|---|---------|
| 29 | [Backup & Restore](29-backup-restore.md) |
| 30 | [Updates & Wartung](30-updates-wartung.md) |
| 31 | [Troubleshooting-Handbuch](31-troubleshooting.md) |

### Teil H – Ausbau ✅
| # | Kapitel |
|---|---------|
| 32 | [Speicher erweitern](32-speicher-erweitern.md) |
| 33 | [Monitoring mit Prometheus & Grafana](33-monitoring.md) |
| 34 | [Mehr Nodes](34-mehr-nodes.md) |
| 35 | [Strom sparen](35-strom-sparen.md) |
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
