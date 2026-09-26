# Plan: Homelab-Tutorial mit Kubernetes, Jellyfin & Tailscale

Dieses Dokument ist der Fahrplan für das Repository. Ziel ist ein **Schritt-für-Schritt-Tutorial für Einsteiger**,
mit dem man auf einem **alten Desktop-Rechner** ein eigenes Homelab aufsetzt und dabei **Kubernetes von Grund auf lernt**.
Am Ende laufen Jellyfin, der *arr-Stack und weitere Self-Hosted-Apps im Cluster – von unterwegs erreichbar
**über Tailscale**, zu Hause auch direkt für den **Smart-TV**.

---

## 1. Ziele

| Ziel | Ergebnis |
|------|----------|
| Kubernetes lernen | Konzepte (Pod, Deployment, Service, Ingress, PV/PVC, ConfigMap, Secret, Namespace, Helm, GitOps) werden *beim Bauen* erklärt, nicht als Theorieblock vorab. |
| Einsteigerfreundlich | Keine Vorkenntnisse in Kubernetes nötig. Befehle zum Kopieren, erwartete Ausgaben, Checkpoints, Troubleshooting, Glossar. |
| Medienserver | Jellyfin mit Medien auf der lokalen Platte, abspielbar auf Smart-TV, Handy, Laptop |
| Medien-Automatisierung | *arr-Stack (Prowlarr, Sonarr, Radarr, Bazarr, qBittorrent, Jellyseerr) |
| Weitere Apps | Dashboard, Passwortmanager, Fotos, Dokumente, Uptime-Monitoring (erweiterbar) |
| Sicherer Zugriff | Von unterwegs nur über Tailscale mit HTTPS (`https://jellyfin.<tailnet>.ts.net`). Kein offener Port im Router. |
| Reproduzierbar | Der gesamte Cluster-Zustand liegt in diesem Git-Repo (GitOps). Proxmox-Snapshots erlauben gefahrloses Ausprobieren. |

---

## 2. Rahmenbedingungen (aus den Antworten)

- **Hardware:** vorhandener alter Desktop-PC
- **Unterbau:** **Proxmox VE** auf dem Desktop, Kubernetes läuft in einer **VM**
- **Medien:** auf einer Festplatte im Desktop
- **Eigener Rechner:** NixOS. Das Tutorial geht davon aus, dass die Werkzeuge (`kubectl`, `helm`, `k9s`, `kubeseal`, `tailscale` …) **bereits installiert** sind. Es gibt nur eine kurze Werkzeugliste und als Bonus eine `flake.nix` mit einer `devShell` (`nix develop`). Installationsanleitungen für andere Betriebssysteme gibt es nicht, nur Links.
- **Zielgruppe:** Einsteiger
- **Smart-TV** soll Jellyfin nutzen können
- ***arr-Stack** ist gewünscht

---

## 3. Architektur-Entscheidungen

| Bereich | Wahl | Warum (einsteigerfreundlich) | Alternativen (im Tutorial erwähnt) |
|---------|------|------------------------------|-----------------------------------|
| Hypervisor | **Proxmox VE** | Web-Oberfläche, **Snapshots vor jedem Kapitel**, einfache VM-Backups | direkt auf Blech installieren |
| VM-Betriebssystem | **Ubuntu Server 24.04 LTS** | Am meisten Anleitungen im Netz, Fehler lassen sich leicht googeln | Debian, NixOS, Talos |
| Kubernetes | **k3s** (Single-Node) | Ein Befehl zur Installation, vollwertiges Kubernetes, bringt Traefik, ServiceLB und local-path gleich mit | k0s, MicroK8s, kubeadm |
| Pakete | **Helm** (+ etwas Kustomize) | Standard im K8s-Ökosystem | – |
| GitOps | **Argo CD** | Anschauliche Web-UI, man *sieht*, was Kubernetes tut | Flux |
| Zugriff von unterwegs | **Tailscale Kubernetes Operator** | Jede App bekommt einen eigenen Namen im Tailnet und automatisch HTTPS | Tailscale nur auf dem Host + Traefik |
| Zugriff zu Hause (Smart-TV) | k3s **ServiceLB** (`LoadBalancer`) → `http://<VM-IP>:8096` | Der TV braucht kein Tailscale. Funktioniert mit jeder Jellyfin-TV-App | Traefik mit lokalem DNS-Namen (Ausblick) |
| Medien-Platte | Physische Platte per **Disk-Passthrough** an die VM, gemountet als `/data` | Die Platte bleibt ein normales ext4-Laufwerk und die Daten überleben einen VM-Neuaufbau | virtuelle Disk auf der Platte, NFS |
| Storage im Cluster | `local-path` (App-Konfigurationen), **statisches PV** auf `/data` (Medien + Downloads) | Man lernt PV/PVC an einem echten Fall | Longhorn (Multi-Node) |
| Ordnerstruktur | `/data/media/{movies,tv}`, `/data/downloads` auf **einer** Platte | Hardlinks funktionieren, also kein doppelter Speicherplatz durch den *arr-Stack | – |
| Secrets | **Sealed Secrets** | Verschlüsselte Secrets dürfen ins Git-Repo | SOPS + age |
| Backup | **Proxmox vzdump** (ganze VM inkl. App-Konfigurationen) auf zweite Platte/USB | Ein Klick in der Web-UI, Restore leicht zu testen. Die Medien werden bewusst separat behandelt. | Velero, restic |
| Monitoring | Uptime Kuma (einfach), optional kube-prometheus-stack | Einsteiger zuerst mit dem einfachen Werkzeug | Netdata |
| Hardware-Transcoding | **optionales Fortgeschrittenen-Kapitel** (GPU-Passthrough in die VM) | Hängt stark von der Hardware ab. Smart-TVs spielen meist direkt ab (Direct Play). | – |
| Updates | Renovate Bot | Erstellt automatisch PRs für neue Versionen | manuell |

### Zielbild

```
  Unterwegs: Laptop / Handy ──── Tailnet (WireGuard, privat) ────┐
                                                                  │ https://jellyfin.<tailnet>.ts.net
  Zu Hause:  Smart-TV ──── LAN ── http://192.168.x.y:8096 ──┐     │
                                                            ▼     ▼
┌─────────────────────────── Alter Desktop-PC: Proxmox VE ───────────────────────────┐
│  Tailscale (Zugriff auf Proxmox-Web-UI von unterwegs)                               │
│                                                                                    │
│  ┌──────────────────────── VM "k3s" (Ubuntu Server) ────────────────────────────┐  │
│  │  tailscale-operator ─► ein Tailscale-Ingress pro App (HTTPS, MagicDNS)       │  │
│  │  argocd  ◄── synchronisiert ── GitHub: homelab-tutorial/kubernetes/          │  │
│  │                                                                              │  │
│  │  media:   jellyfin  jellyseerr  sonarr  radarr  prowlarr  bazarr  qbittorrent │  │
│  │  apps:    homepage  vaultwarden  immich  paperless-ngx  uptime-kuma           │  │
│  │  system:  sealed-secrets  (optional: monitoring, intel-gpu-plugin)           │  │
│  │                                                                              │  │
│  │  /var/lib/rancher/k3s/storage  → App-Konfigurationen (VM-Disk)               │  │
│  │  /data                          → Medien-Platte (Disk-Passthrough)           │  │
│  └──────────────────────────────────────────────────────────────────────────────┘  │
│  vzdump-Backups der VM → Backup-Ziel (2. Platte / USB)                              │
└────────────────────────────────────────────────────────────────────────────────────┘
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
│   ├── bootstrap/             # Argo CD selbst + "App of Apps"
│   ├── infrastructure/        # tailscale-operator, sealed-secrets, storage (PV für /data), …
│   └── apps/
│       ├── media/             # jellyfin, sonarr, radarr, prowlarr, bazarr, qbittorrent, jellyseerr
│       └── …                  # homepage, vaultwarden, immich, paperless-ngx, uptime-kuma
├── examples/                  # Lern-Manifeste für die Grundlagenkapitel (nginx, whoami, …)
└── scripts/                   # Hilfsskripte (VM-Vorbereitung, k3s-Installation, Checks)
```

Jede App bekommt einen eigenen Ordner mit der gleichen Struktur. So lernt man das Muster einmal und verwendet es danach immer wieder.

---

## 5. Tutorial-Kapitel (Lernpfad)

**Aufbau jedes Kapitels:** Was du am Ende hast → Zeitaufwand → Neue Begriffe → Schritte (Befehle zum Kopieren und erwartete Ausgabe)
→ ✅ Checkpoint → 🔧 Wenn etwas schiefgeht → Was du gelernt hast.
Vor jedem Kapitel gibt es den Hinweis: **Proxmox-Snapshot anlegen**, damit man jederzeit zurückspringen kann.

### Teil A – Fundament
| # | Kapitel | Inhalt |
|---|---------|--------|
| 00 | Einführung | Was ist ein Homelab, was bauen wir, wie liest man das Tutorial, Kubernetes in 5 Minuten, Glossar |
| 01 | Voraussetzungen | Hardware-Check des Desktops (RAM, Platten, Virtualisierung im BIOS aktivieren), Werkzeuge auf dem eigenen Rechner, Tailscale-Account, GitHub-Account |
| 02 | Proxmox installieren | USB-Stick erstellen, Installation, Web-Oberfläche, Paketquellen & Updates |
| 03 | Tailscale auf Proxmox | Proxmox ins Tailnet aufnehmen, damit die Web-UI von unterwegs erreichbar ist |
| 04 | Die Kubernetes-VM | VM anlegen (CPU/RAM/Disk), Ubuntu installieren, feste IP, SSH-Key, Medien-Platte durchreichen, `/data`-Ordnerstruktur |
| 05 | k3s installieren | k3s installieren, VM ins Tailnet, `kubectl` vom eigenen Rechner über Tailscale, erster Snapshot mit „frischem Cluster“ |

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
| 12 | Jellyfin auf dem Smart-TV | Jellyfin-App auf dem TV, Verbindung über LAN-IP, Direct Play vs. Transcoding, Hinweise für Android-/Apple-TV (dort gibt es auch Tailscale) | – |
| 13 | GitOps mit Argo CD | Argo CD installieren, dieses Repo verbinden, App-of-Apps, Jellyfin „umziehen“ | GitOps, Reconciliation, Drift |
| 14 | Secrets im Git | Sealed Secrets einrichten, Tailscale-OAuth-Secret verschlüsselt ins Repo | Controller, Verschlüsselung |

### Teil D – Medien-Automatisierung (*arr-Stack)
> ⚖️ Hinweis im Tutorial: Nur für legal erworbene bzw. frei verfügbare Inhalte nutzen.

| # | Kapitel | Inhalt | K8s-Konzepte |
|---|---------|--------|--------------|
| 15 | Wie der *arr-Stack zusammenspielt | Überblick, Ordnerstruktur, Hardlinks, Benutzer-/Rechte (PUID/PGID) | ein Volume in mehreren Pods |
| 16 | qBittorrent | Download-Client, optional mit VPN (Gluetun als Sidecar) | Sidecar-Container, `securityContext` |
| 17 | Prowlarr | Indexer zentral verwalten | Service-zu-Service-Kommunikation, Cluster-DNS |
| 18 | Sonarr & Radarr | Serien & Filme, Anbindung an qBittorrent & Jellyfin | – |
| 19 | Bazarr & Jellyseerr | Untertitel, Wunschliste für Familie/Mitbewohner | – |

### Teil E – Weitere Apps (kurz, gleiches Muster)
| # | App | Zweck |
|---|-----|-------|
| 20 | Homepage | Dashboard mit Links zu allen Diensten |
| 21 | Vaultwarden | Passwortmanager (Bitwarden-kompatibel) |
| 22 | Immich | Foto-Backup vom Handy (Lernbeispiel für Apps mit Datenbank und mehreren Komponenten) |
| 23 | Paperless-ngx | Dokumente scannen & durchsuchen |
| 24 | Uptime Kuma | Überwacht, ob alle Dienste laufen |

### Teil F – Betrieb
| # | Kapitel | Inhalt |
|---|---------|--------|
| 25 | Backup & Restore | Proxmox-Backups der VM planen, **Restore wirklich testen**, was mit den Medien passiert |
| 26 | Updates & Wartung | Proxmox, Ubuntu, k3s und Apps aktualisieren, Renovate |
| 27 | Troubleshooting-Handbuch | Die häufigsten Fehler (`Pending`, `CrashLoopBackOff`, `ImagePullBackOff`, Rechteprobleme auf `/data`) und wie man sie findet |

### Teil G – Für Fortgeschrittene (optional)
| # | Kapitel | Inhalt |
|---|---------|--------|
| 28 | Hardware-Transcoding | GPU-Passthrough (Intel iGPU/NVIDIA) von Proxmox in die VM, Device Plugin, Jellyfin-Einstellungen |
| 29 | Monitoring | kube-prometheus-stack, Grafana-Dashboards |
| 30 | Mehr Nodes | Zweite VM als Worker, Scheduling, Ausblick Longhorn/HA |

---

## 6. Umsetzungs-Phasen (für das Repo)

1. **Phase 1 – Gerüst & Fundament:** README, Repo-Struktur, `flake.nix`, Glossar, Kapitel 00–05.
2. **Phase 2 – Grundlagen:** Kapitel 06–09 mit Beispiel-Manifesten in `examples/`.
3. **Phase 3 – Homelab-Herz:** Kapitel 10–14, Manifeste in `kubernetes/` (Tailscale Operator, Jellyfin, Argo CD, Sealed Secrets).
4. **Phase 4 – *arr-Stack:** Kapitel 15–19.
5. **Phase 5 – Weitere Apps:** Kapitel 20–24.
6. **Phase 6 – Betrieb & Fortgeschritten:** Kapitel 25–30, Renovate-Konfiguration.
7. **Laufend:** CI-Check (yamllint, kubeconform, Markdown-Linkcheck), damit die Manifeste immer gültig sind.

Jede Phase wird als eigener Commit/PR umgesetzt.

---

## 7. Noch offene Fragen

1. **Desktop-Details:** Welche CPU (Intel/AMD, Generation), wie viel RAM, welche Platten (SSD für System + HDD für Medien?), gibt es eine Grafikkarte? → bestimmt VM-Größe und ob Kapitel 28 realistisch ist.
2. **Smart-TV:** Welches System (Samsung Tizen, LG webOS, Android/Google TV, Fire TV, Apple TV)?
3. **VPN für qBittorrent:** Hast du einen VPN-Anbieter (z. B. Mullvad, ProtonVPN)? Dann kommt Gluetun als Sidecar hinein, sonst wird es nur als optional beschrieben.
4. **NixOS:** Richtig verstanden, dass NixOS auf deinem *eigenen Rechner* läuft und die Werkzeuge dort vorausgesetzt werden? Oder soll die **VM** auch NixOS sein? (Für Einsteiger empfehle ich Ubuntu in der VM.)
