# Plan: Homelab-Tutorial mit Kubernetes, Jellyfin & Tailscale

Dieses Dokument ist der Fahrplan für das Repository. Ziel ist ein **Schritt-für-Schritt-Tutorial für Einsteiger**,
mit dem man auf einem **alten Desktop-Rechner** ein eigenes Homelab aufsetzt und dabei **Kubernetes von Grund auf lernt**.
Am Ende laufen Jellyfin (mit GPU-Transcoding), der *arr-Stack und weitere Self-Hosted-Apps im Cluster – von unterwegs
erreichbar **über Tailscale**, zu Hause auch direkt für den **Smart-TV**.

---

## 1. Ziele

| Ziel | Ergebnis |
|------|----------|
| Kubernetes lernen | Konzepte (Pod, Deployment, Service, Ingress, PV/PVC, ConfigMap, Secret, Namespace, Helm, GitOps) werden *beim Bauen* erklärt, nicht als Theorieblock vorab. |
| Einsteigerfreundlich | Keine Vorkenntnisse in Kubernetes nötig. Befehle zum Kopieren, erwartete Ausgaben, Checkpoints, Troubleshooting, Glossar. |
| Medienserver | Jellyfin, abspielbar auf Smart-TV, Handy, Laptop, mit **Hardware-Transcoding über die NVIDIA-GPU** |
| Medien-Automatisierung | *arr-Stack (Prowlarr, Sonarr, Radarr, Bazarr, qBittorrent, Seerr) |
| Weitere Apps | Dashboard, Passwortmanager, Fotos, Dokumente, Uptime-Monitoring (erweiterbar) |
| Sicherer Zugriff | Von unterwegs nur über Tailscale mit HTTPS (`https://jellyfin.<tailnet>.ts.net`). Kein offener Port im Router. |
| Reproduzierbar | Der gesamte Cluster-Zustand liegt in diesem Git-Repo (GitOps). Proxmox-Snapshots erlauben gefahrloses Ausprobieren. |

---

## 2. Rahmenbedingungen

| Thema | Stand |
|-------|-------|
| Hardware | Alter Desktop-PC: **AMD Ryzen 5 (ältere Generation)**, **NVIDIA RTX 2070 Super**, **500 GB HDD** |
| Unterbau | **Proxmox VE** auf dem Desktop, Kubernetes läuft in einer **VM** |
| Medien | lokal auf der Platte |
| Eigener Rechner | NixOS. Die Werkzeuge (`kubectl`, `helm`, `k9s`, `kubeseal`, `tailscale` …) werden als **installiert vorausgesetzt**. Als Bonus gibt es eine `flake.nix` mit `devShell` (`nix develop`). |
| Zielgruppe | Einsteiger |
| VM-Betriebssystem | Ubuntu Server (bestätigt) |
| Clients | **Samsung Smart-TV (Tizen)** zu Hause, Laptop/Handy (auch unterwegs) |
| VPN für Downloads | **Proton VPN** (noch kein Abo vorhanden) |
| *arr-Stack | gewünscht |

### Was die Hardware für den Plan bedeutet

- **Ryzen 5 ohne integrierte Grafik** (außer bei „G“-Modellen): Die RTX 2070 Super ist die einzige Grafikkarte.
  Wird sie an die VM durchgereicht, hat Proxmox **kein Bild mehr am Monitor**. Das ist kein Problem, denn Proxmox wird ohnehin
  über die Web-Oberfläche bedient. Das Tutorial weist aber deutlich darauf hin und macht den GPU-Schritt erst,
  wenn alles andere läuft.
- **RTX 2070 Super (Turing, NVENC 7. Gen.):** hervorragend für Jellyfin-Transcoding (H.264/HEVC inkl. 10-Bit HDR→SDR-Tonemapping,
  mehrere Streams gleichzeitig). Kein AV1 – das ist für einen Heimserver aber kein Nachteil. Bonus: Die GPU kann später per
  *Time-Slicing* auch mit Immich (Gesichtserkennung) geteilt werden.
- **Ältere Ryzen-Plattform:** IOMMU/AMD-Vi muss im BIOS aktiviert werden, und bei älteren Boards (B350/X370) können die
  IOMMU-Gruppen ungünstig sein. Kapitel 02 enthält deshalb direkt nach der Installation einen Check.
- **Nur eine 500-GB-HDD:** Proxmox, VM und Medien teilen sich eine Platte.
  - Die Medien kommen auf eine **eigene virtuelle Disk** der VM (`/data`). Die lässt sich später per Klick auf eine
    neue Platte verschieben („Move Disk“) und wird aus den VM-Backups ausgeklammert.
  - Realistische Aufteilung: ca. 40 GB Proxmox, 60 GB VM-System, **ca. 300 GB Medien** (grob 60–80 Filme in 1080p),
    der Rest bleibt als Puffer für Snapshots frei (ein volles LVM-Thin-Pool legt alle VMs lahm).
  - Eine HDD ist für VMs langsam, aber ausreichend. **Empfohlenes Upgrade** (im Tutorial als Tipp): eine günstige SSD für
    Proxmox + VM, die HDD dann komplett für Medien. Das Tutorial beschreibt den Umzug.
  - Backups brauchen ein zweites Ziel (USB-Platte o. Ä.).

---

## 3. Architektur-Entscheidungen

| Bereich | Wahl | Warum (einsteigerfreundlich) | Alternativen (im Tutorial erwähnt) |
|---------|------|------------------------------|-----------------------------------|
| Hypervisor | **Proxmox VE** | Web-Oberfläche, **Snapshots vor jedem Kapitel**, einfache VM-Backups, PCIe-Passthrough für die GPU | direkt auf Blech installieren |
| VM | **Ubuntu Server 24.04 LTS**, Maschinentyp **q35 + UEFI (OVMF)**, CPU-Typ `host`, 4–8 vCPUs | q35/UEFI von Anfang an, damit das GPU-Passthrough später ohne Neuinstallation klappt. Ubuntu hat die meisten Anleitungen und die offiziellen NVIDIA-Treiberpakete | Debian, NixOS, Talos |
| Kubernetes | **k3s** (Single-Node) | Ein Befehl zur Installation, vollwertiges Kubernetes, bringt Traefik, ServiceLB und local-path mit, **erkennt die NVIDIA-Runtime automatisch** | k0s, MicroK8s, kubeadm |
| Pakete | **Helm** (+ etwas Kustomize) | Standard im K8s-Ökosystem | – |
| GitOps | **Argo CD** | Anschauliche Web-UI, man *sieht*, was Kubernetes tut | Flux |
| Zugriff von unterwegs | **Tailscale Kubernetes Operator** | Jede App bekommt einen eigenen Namen im Tailnet und automatisch HTTPS | Tailscale nur auf dem Host + Traefik |
| Zugriff zu Hause (Samsung-TV) | k3s **ServiceLB** (`LoadBalancer`) → `http://<VM-IP>:8096` | Auf Samsung Tizen gibt es kein Tailscale, der TV verbindet sich daher direkt im Heimnetz | Traefik mit lokalem DNS-Namen (Ausblick) |
| VPN für qBittorrent | **Gluetun** als Sidecar im qBittorrent-Pod, **Proton VPN per WireGuard** mit Port-Forwarding | Nur der Download-Traffic läuft durchs VPN, Kill-Switch inklusive. Der WireGuard-Schlüssel liegt als Sealed Secret im Repo | anderer Gluetun-kompatibler Anbieter (z. B. Mullvad, AirVPN) |
| Medien-Speicher | **Zweite virtuelle Disk** der VM, ext4, gemountet als `/data` | Funktioniert mit nur einer physischen Platte, lässt sich später auf eine neue Platte verschieben und aus Backups ausschließen | Disk-Passthrough (sobald eine eigene Medienplatte existiert), NFS |
| Storage im Cluster | `local-path` (App-Konfigurationen), **statisches PV** auf `/data` (Medien + Downloads) | Man lernt PV/PVC an einem echten Fall | Longhorn (Multi-Node) |
| Ordnerstruktur | `/data/media/{movies,tv}`, `/data/downloads` auf **einer** Disk | Hardlinks funktionieren, also kein doppelter Speicherplatz durch den *arr-Stack | – |
| GPU | **PCIe-Passthrough** der RTX 2070 Super in die VM → NVIDIA-Treiber + Container Toolkit in der VM → **NVIDIA Device Plugin** im Cluster | Standardweg, Jellyfin fordert die GPU wie CPU/RAM als Ressource an (`nvidia.com/gpu: 1`) | NVIDIA GPU Operator (mehr Automatik, schwerer zu verstehen) |
| Secrets | **Sealed Secrets** | Verschlüsselte Secrets dürfen ins Git-Repo | SOPS + age |
| Backup | **Proxmox vzdump** der VM-Systemdisk (inkl. aller App-Konfigurationen) auf USB-Platte | Ein Klick in der Web-UI, Restore leicht zu testen. Die Medien-Disk ist ausgenommen. | Velero, restic |
| Monitoring | Uptime Kuma (einfach), optional kube-prometheus-stack | Einsteiger zuerst mit dem einfachen Werkzeug | Netdata |
| Updates | Renovate Bot | Erstellt automatisch PRs für neue Versionen | manuell |

### Zielbild

```
  Unterwegs: Laptop / Handy ──── Tailnet (WireGuard, privat) ────┐
                                                                  │ https://jellyfin.<tailnet>.ts.net
  Zu Hause:  Smart-TV ──── LAN ── http://192.168.x.y:8096 ──┐     │
                                                            ▼     ▼
┌──────────────── Alter Desktop-PC (Ryzen 5, RTX 2070 Super, 500 GB HDD): Proxmox VE ─────────────┐
│  Tailscale (Zugriff auf Proxmox-Web-UI von unterwegs)                                            │
│                                                                                                  │
│  ┌──────────────────────── VM "k3s" (Ubuntu Server, q35/UEFI) ─────────────────────────────────┐ │
│  │  RTX 2070 Super (PCIe-Passthrough) ─► nvidia-device-plugin ─► jellyfin (nvidia.com/gpu: 1)  │ │
│  │  tailscale-operator ─► ein Tailscale-Ingress pro App (HTTPS, MagicDNS)                      │ │
│  │  argocd  ◄── synchronisiert ── GitHub: homelab-tutorial/kubernetes/                         │ │
│  │                                                                                             │ │
│  │  media:   jellyfin  seerr  sonarr  radarr  prowlarr  bazarr  qbittorrent                │ │
│  │  apps:    homepage  vaultwarden  immich  paperless-ngx  uptime-kuma                          │ │
│  │  system:  sealed-secrets  nvidia-device-plugin  (optional: monitoring)                      │ │
│  │                                                                                             │ │
│  │  Disk 1 (~60 GB):  Ubuntu + /var/lib/rancher/k3s/storage (App-Konfigurationen) → Backup     │ │
│  │  Disk 2 (~300 GB): /data  (Medien + Downloads)                                 → kein Backup │ │
│  └─────────────────────────────────────────────────────────────────────────────────────────────┘ │
│  vzdump-Backups der VM → USB-Platte                                                              │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Repository-Struktur

```
homelab-tutorial/
├── README.md                  # Einstieg, Überblick, Inhaltsverzeichnis
├── PLAN.md                    # dieser Plan
├── flake.nix                  # devShell mit allen Werkzeugen (nix develop)
├── docs/                      # Die Tutorial-Kapitel (Deutsch)
│   ├── 00-einfuehrung.md
│   ├── glossar.md
│   └── …
├── kubernetes/                # Alles, was im Cluster läuft (GitOps-Quelle)
│   ├── bootstrap/root.yaml    # Wurzel-Application (App-of-Apps), einmalig per kubectl
│   ├── katalog/               # Argo-CD-Applications aller verfügbaren Apps (Vorlagen)
│   ├── aktiv/                 # aktivierte Applications (Kopie aus katalog/), von root ausgerollt
│   ├── infrastructure/        # Helm-Values: argocd, tailscale-operator, sealed-secrets, nvidia-device-plugin
│   ├── apps/
│   │   ├── media/             # basis (Namespace, PV/PVC /data), jellyfin, später *arr-Stack
│   │   └── …                  # homepage, vaultwarden, immich, paperless-ngx, uptime-kuma
│   └── secrets/<namespace>/   # SealedSecrets (verschlüsselt)
├── examples/                  # Lern-Manifeste für die Grundlagenkapitel (nginx, whoami, …)
└── scripts/validate.sh       # prüft alle Manifeste (auch in der CI)
```

Jede App bekommt einen eigenen Ordner mit der gleichen Struktur. So lernt man das Muster einmal und verwendet es danach immer wieder.

**Aktivieren statt alles auf einmal:** Das Repository enthält den *Endzustand*, aber Argo CD rollt nur aus, was in
`kubernetes/aktiv/` liegt. So kann man Kapitel für Kapitel vorgehen. Argo CD beobachtet dieses (private) Repository direkt.

---

## 5. Tutorial-Kapitel (Lernpfad)

**Aufbau jedes Kapitels:** Was du am Ende hast → Zeitaufwand → Neue Begriffe → Schritte (Befehle zum Kopieren und erwartete Ausgabe)
→ ✅ Checkpoint → 🔧 Wenn etwas schiefgeht → Was du gelernt hast.
Vor jedem Kapitel gibt es den Hinweis: **Proxmox-Snapshot anlegen**, damit man jederzeit zurückspringen kann.

### Teil A – Fundament
| # | Kapitel | Inhalt |
|---|---------|--------|
| 00 | Einführung | Was ist ein Homelab, was bauen wir, wie liest man das Tutorial, Kubernetes in 5 Minuten, Glossar |
| 01 | Voraussetzungen | Hardware-Check (RAM, Platte), **BIOS: SVM + IOMMU aktivieren**, Werkzeuge auf dem eigenen Rechner, Tailscale- und GitHub-Account, USB-Platte für Backups |
| 02 | Proxmox installieren | USB-Stick erstellen, Installation auf die HDD, Web-Oberfläche, Paketquellen & Updates, Speicheraufteilung, **IOMMU-Gruppen prüfen** |
| 03 | Tailscale auf Proxmox | Proxmox ins Tailnet aufnehmen, damit die Web-UI von unterwegs erreichbar ist |
| 04 | Die Kubernetes-VM | VM anlegen (**q35, UEFI, CPU `host`**, RAM), Ubuntu installieren, feste IP, SSH-Key, **zweite Disk für `/data`** anlegen und mounten, Ordnerstruktur |
| 05 | k3s installieren | k3s installieren, VM ins Tailnet, `kubectl` vom eigenen Rechner über Tailscale, Snapshot „frischer Cluster“ |

### Teil B – Kubernetes-Grundlagen (am Beispiel)
| # | Kapitel | Inhalt | K8s-Konzepte |
|---|---------|--------|--------------|
| 06 | Erster Pod | nginx starten, Logs ansehen, `exec`, löschen, `k9s` kennenlernen | Pod, `get/describe/logs/exec` |
| 07 | Deployments & Services | Skalieren, Pod löschen und Self-Healing beobachten, Service im LAN erreichen | Deployment, ReplicaSet, Service, LoadBalancer, Labels |
| 08 | Konfiguration & Daten | App mit Konfiguration und persistentem Speicher, Daten überleben Neustart | Namespace, ConfigMap, Secret, PV, PVC, StorageClass |
| 09 | Helm | Chart installieren, Values anpassen, Upgrade & Rollback | Chart, Release, Values |

### Teil C – Das Homelab-Herz
| # | Kapitel | Inhalt | K8s-Konzepte |
|---|---------|--------|--------------|
| 10 | Tailscale Operator | OAuth-Client anlegen, Operator per Helm, erster Dienst im Tailnet mit HTTPS | Operator, CRD, IngressClass |
| 11 | Jellyfin | Jellyfin mit eigenen Manifesten, `/data/media` einbinden, Bibliotheken anlegen, Erreichbarkeit per Tailscale **und** im LAN | Deployment mit PVCs, Probes, Resources |
| 12 | Jellyfin auf dem Samsung-TV | Jellyfin-App für Tizen installieren (App-Store bzw. Sideload, je nach Modelljahr), Verbindung über LAN-IP, feste IP per DHCP-Reservierung im Router, Direct Play vs. Transcoding: Samsung-TVs können u. a. **kein DTS-Audio** und keine Bild-Untertitel (PGS) → Jellyfin wandelt um, später mit GPU-Unterstützung | – |
| 13 | GitOps mit Argo CD | Argo CD installieren, dieses Repo verbinden, App-of-Apps, Jellyfin „umziehen“ | GitOps, Reconciliation, Drift |
| 14 | Secrets im Git | Sealed Secrets einrichten, Tailscale-OAuth-Secret verschlüsselt ins Repo | Controller, Verschlüsselung |
| 15 | GPU an die VM durchreichen | IOMMU prüfen, `vfio` einrichten, RTX 2070 Super per PCIe-Passthrough an die VM, NVIDIA-Treiber + Container Toolkit in der VM, `nvidia-smi` | – |
| 16 | GPU in Kubernetes | RuntimeClass `nvidia`, NVIDIA Device Plugin, Jellyfin fordert `nvidia.com/gpu` an, NVENC in Jellyfin aktivieren, Test mit 4K-HDR-Datei | DaemonSet, Device Plugins, RuntimeClass, Extended Resources |

### Teil D – Medien-Automatisierung (*arr-Stack)
> ⚖️ Hinweis im Tutorial: Nur für legal erworbene bzw. frei verfügbare Inhalte nutzen.

| # | Kapitel | Inhalt | K8s-Konzepte |
|---|---------|--------|--------------|
| 17 | Wie der *arr-Stack zusammenspielt | Überblick, Ordnerstruktur, Hardlinks, Benutzer/Rechte (PUID/PGID), Speicherplatz im Blick behalten (500 GB!) | ein Volume in mehreren Pods |
| 18 | qBittorrent + Proton VPN | Proton-VPN-Abo (Plus, P2P + Port-Forwarding nötig; der Gratis-Plan erlaubt kein P2P), WireGuard-Konfiguration erzeugen, Gluetun als Sidecar, Kill-Switch testen (IP-Check im Pod), weitergeleiteten Port automatisch in qBittorrent setzen | Sidecar-Container, gemeinsames Netzwerk im Pod, `securityContext`/`NET_ADMIN`, Sealed Secret |
| 19 | Prowlarr | Indexer zentral verwalten | Service-zu-Service-Kommunikation, Cluster-DNS |
| 20 | Sonarr & Radarr | Serien & Filme, Anbindung an qBittorrent & Jellyfin, Qualitätsprofile passend zur kleinen Platte | – |
| 21 | Bazarr & Seerr | Untertitel, Wunschliste für Familie/Mitbewohner | – |

### Teil E – Weitere Apps (kurz, gleiches Muster)
| # | App | Zweck |
|---|-----|-------|
| 22 | Homepage | Dashboard mit Links zu allen Diensten |
| 23 | Vaultwarden | Passwortmanager (Bitwarden-kompatibel) |
| 24 | Immich | Foto-Backup vom Handy (Apps mit Datenbank, mehreren Komponenten, optional GPU per Time-Slicing geteilt) |
| 25 | Paperless-ngx | Dokumente scannen & durchsuchen |
| 26 | Uptime Kuma | Überwacht, ob alle Dienste laufen |

### Teil F – Betrieb
| # | Kapitel | Inhalt |
|---|---------|--------|
| 27 | Backup & Restore | Proxmox-Backups der VM auf USB-Platte planen, Medien-Disk ausklammern, **Restore wirklich testen** |
| 28 | Updates & Wartung | Proxmox, Ubuntu, NVIDIA-Treiber, k3s und Apps aktualisieren, Renovate |
| 29 | Troubleshooting-Handbuch | Die häufigsten Fehler (`Pending`, `CrashLoopBackOff`, `ImagePullBackOff`, Rechte auf `/data`, GPU nicht gefunden, Platte voll) und wie man sie findet |

### Teil G – Ausbau (optional)
| # | Kapitel | Inhalt |
|---|---------|--------|
| 30 | SSD nachrüsten | Proxmox/VM auf eine SSD umziehen, HDD komplett für Medien (Move Disk bzw. Disk-Passthrough) |
| 31 | Monitoring | kube-prometheus-stack, Grafana-Dashboards (GPU-Metriken: Ausblick auf nvidia_gpu_exporter, da DCGM GeForce-Karten nur eingeschränkt unterstützt) |
| 32 | Mehr Nodes | Zweite VM/zweiter Rechner als Worker, Scheduling, Ausblick Longhorn/HA |

---

## 6. Umsetzungs-Phasen (für das Repo)

1. **Phase 1 – Gerüst & Fundament:** README, Repo-Struktur, `flake.nix`, Glossar, Kapitel 00–05.
2. **Phase 2 – Grundlagen:** Kapitel 06–09 mit Beispiel-Manifesten in `examples/`.
3. **Phase 3 – Homelab-Herz:** Kapitel 10–16, Manifeste in `kubernetes/` (Tailscale Operator, Jellyfin, Argo CD, Sealed Secrets, NVIDIA).
4. **Phase 4 – *arr-Stack:** Kapitel 17–21.
5. **Phase 5 – Weitere Apps:** Kapitel 22–26.
6. **Phase 6 – Betrieb & Ausbau:** Kapitel 27–32, Renovate-Konfiguration.
7. **Laufend:** CI-Check (yamllint, kubeconform, Markdown-Linkcheck), damit die Manifeste immer gültig sind.

Jede Phase wird als eigener Commit/PR umgesetzt.

**Status:** Phase 1 ✅ · Phase 2 ✅ · Phase 3 ✅ · Phase 4 ✅ · Phase 5 ✅ · Phase 6 ✅

---

## 7. Offene Fragen (alle geklärt)

| Frage | Antwort |
|-------|-------------------|
| ~~RAM des Desktops?~~ | ✅ 16 GB → VM bekommt 12 GB |
| ~~Ryzen-Modell / Mainboard?~~ | ✅ Ryzen 5 1600/2600-Klasse auf B350/B450 → IOMMU-Check in Kapitel 02 |
| ~~Modelljahr des Samsung-TVs?~~ | ✅ Neueres Modell → Jellyfin-App aus dem App-Store; Sideload nur als Hinweis |
