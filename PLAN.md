# Plan: Homelab-Tutorial mit Kubernetes, Jellyfin & Tailscale

Dieses Dokument ist der Fahrplan für das Repository. Ziel ist ein **Schritt-für-Schritt-Tutorial**,
mit dem man ein eigenes Homelab aufsetzt und dabei **Kubernetes von Grund auf lernt**.
Am Ende laufen Jellyfin und weitere Self-Hosted-Apps im Cluster, erreichbar **nur über Tailscale**
(kein offener Port im Heimrouter).

---

## 1. Ziele

| Ziel | Ergebnis |
|------|----------|
| Kubernetes lernen | Konzepte (Pod, Deployment, Service, Ingress, PV/PVC, ConfigMap, Secret, Namespace, Helm, GitOps) werden *beim Bauen* erklärt, nicht vorab als Theorieblock. |
| Medienserver | Jellyfin mit Hardware-Transcoding (Intel Quick Sync) |
| Weitere Apps | Dashboard, Passwortmanager, Fotos, Dokumente, Monitoring … (erweiterbar) |
| Sicherer Zugriff | Alle Dienste über Tailscale mit HTTPS (`https://jellyfin.<tailnet>.ts.net`), nichts direkt im Internet |
| Reproduzierbar | Der gesamte Cluster-Zustand liegt in diesem Git-Repo (GitOps) – Neuaufbau ist jederzeit möglich |

---

## 2. Architektur-Entscheidungen

Bewusst einfach gehalten, aber „echtes“ Kubernetes – keine Spielzeug-Abkürzungen, die man später wieder verlernen muss.

| Bereich | Wahl | Warum | Alternativen (im Tutorial erwähnt) |
|---------|------|-------|-----------------------------------|
| Hardware | 1× Mini-PC (z. B. Intel N100/N150, 16 GB RAM, NVMe) + Datenplatte für Medien | Stromsparend, leise, Quick Sync für Jellyfin | Alter Laptop/PC, Raspberry Pi 5 (kein gutes Transcoding), mehrere Nodes |
| Betriebssystem | Ubuntu Server 24.04 LTS | Weit verbreitet, viel Doku, gute Intel-GPU-Treiber | Debian, Talos Linux (später als Ausblick) |
| Kubernetes-Distribution | **k3s** | Leichtgewichtig, Single-Binary, zertifiziertes Kubernetes, ideal zum Lernen | k0s, MicroK8s, kubeadm, Talos |
| Paketverwaltung | **Helm** | Standard für Apps im K8s-Ökosystem | Kustomize (wird ergänzend genutzt) |
| GitOps | **Argo CD** | Anschauliche Web-UI – man *sieht*, was Kubernetes tut | Flux |
| Remote-Zugriff | **Tailscale Kubernetes Operator** | Jeder Service bekommt eigenen MagicDNS-Namen + automatisches HTTPS-Zertifikat; auch `kubectl` über Tailscale | Tailscale auf dem Host + Traefik-Ingress |
| Ingress (lokal) | Traefik (bei k3s dabei) | Optional für Zugriff im LAN | ingress-nginx |
| Storage | k3s `local-path` für App-Konfigurationen, `hostPath`/NFS für Medien | Einfach, versteht man sofort | Longhorn (bei mehreren Nodes) |
| Secrets | **Sealed Secrets** | Verschlüsselte Secrets dürfen ins Git-Repo | SOPS + age, External Secrets |
| GPU | Intel GPU Device Plugin (+ Node Feature Discovery) | Hardware-Transcoding für Jellyfin im Pod | – |
| Monitoring | kube-prometheus-stack (Prometheus + Grafana), Loki für Logs | De-facto-Standard | Netdata, Uptime Kuma (einfacher) |
| Backup | Velero bzw. restic-basiertes Backup der PVCs auf externes Ziel | Cluster *und* Daten wiederherstellbar | k8up, VolSync |
| Updates | Renovate Bot | Erstellt automatisch PRs für neue Image-/Chart-Versionen | manuell |

### Zielbild

```
                Tailnet (WireGuard, privat)
   Laptop / Handy / TV ───────────────┐
                                      ▼
┌──────────────────────── Mini-PC (Ubuntu + k3s) ───────────────────────┐
│                                                                        │
│  tailscale-operator ──► Tailscale-Ingress pro App (HTTPS, MagicDNS)    │
│                                                                        │
│  argocd  ◄── synchronisiert ── GitHub: homelab-tutorial/kubernetes/    │
│                                                                        │
│  media:      jellyfin (+ Intel GPU)   jellyseerr   (optional *arr)     │
│  apps:       homepage  vaultwarden  immich  paperless-ngx  uptime-kuma │
│  monitoring: prometheus  grafana  loki                                 │
│  system:     sealed-secrets  intel-gpu-plugin  backup                  │
│                                                                        │
│  Storage: /var/lib/rancher/k3s/storage (Configs)  /mnt/media (Medien)  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Repository-Struktur

```
homelab-tutorial/
├── README.md                  # Einstieg, Überblick, Inhaltsverzeichnis
├── PLAN.md                    # dieser Plan
├── docs/                      # Die Tutorial-Kapitel (Deutsch)
│   ├── 00-einfuehrung.md
│   ├── 01-hardware.md
│   └── …
├── kubernetes/                # Alles, was im Cluster läuft (GitOps-Quelle)
│   ├── bootstrap/             # Argo CD selbst + "App of Apps"
│   ├── infrastructure/        # tailscale-operator, sealed-secrets, intel-gpu, monitoring, backup
│   └── apps/                  # jellyfin, homepage, vaultwarden, immich, …
├── examples/                  # Lern-Manifeste für die Grundlagenkapitel (nginx, whoami, …)
└── scripts/                   # Hilfsskripte (Host-Vorbereitung, k3s-Installation, Checks)
```

Jede App bekommt einen eigenen Ordner mit gleicher Struktur (`namespace.yaml`, `values.yaml` bzw.
Manifeste, `ingress.yaml`, `kustomization.yaml`), damit man das Muster einmal lernt und dann wiederverwendet.

---

## 4. Tutorial-Kapitel (Lernpfad)

Jedes Kapitel hat: **Ziel → Konzepte → Schritte → Überprüfung → Troubleshooting → „Was hast du gelernt?“**

### Teil A – Fundament
| # | Kapitel | Inhalt | K8s-Konzepte |
|---|---------|--------|--------------|
| 00 | Einführung | Was ist ein Homelab, was bauen wir, was ist Kubernetes (kurz) | Überblick Control Plane / Node |
| 01 | Hardware & Planung | Hardware-Empfehlungen, Stromverbrauch, Platten, Netzwerk | – |
| 02 | Betriebssystem | Ubuntu Server installieren, SSH-Keys, Updates, feste IP, Medienplatte mounten | – |
| 03 | Tailscale auf dem Host | Tailnet anlegen, Server beitreten lassen, SSH nur noch über Tailscale | – |
| 04 | k3s installieren | Installation, `kubectl` + kubeconfig auf dem Laptop (über Tailscale) | Cluster, Node, kubeconfig, Context |

### Teil B – Kubernetes-Grundlagen (am Beispiel)
| # | Kapitel | Inhalt | K8s-Konzepte |
|---|---------|--------|--------------|
| 05 | Erster Pod | nginx per Hand starten, Logs ansehen, `exec`, löschen | Pod, `kubectl get/describe/logs/exec` |
| 06 | Deployments & Services | Skalieren, Self-Healing ausprobieren, Service erreichen | Deployment, ReplicaSet, Service, Labels/Selectors |
| 07 | Konfiguration & Daten | App mit Config + persistentem Speicher | Namespace, ConfigMap, Secret, PV, PVC, StorageClass |
| 08 | Helm | Chart installieren, Values anpassen, Upgrade/Rollback | Helm Chart, Release, Values |

### Teil C – Das echte Homelab
| # | Kapitel | Inhalt | K8s-Konzepte |
|---|---------|--------|--------------|
| 09 | Tailscale Operator | OAuth-Client anlegen, Operator per Helm, erster Service im Tailnet mit HTTPS | Operator, CRD, IngressClass |
| 10 | Jellyfin | Jellyfin mit eigenen Manifesten, Medien einbinden, per Tailscale erreichen | StatefulSet vs. Deployment, hostPath, Probes, Resources |
| 11 | Hardware-Transcoding | Intel GPU Device Plugin, GPU dem Jellyfin-Pod zuweisen, Test | DaemonSet, Device Plugins, Node Labels |
| 12 | GitOps mit Argo CD | Argo CD installieren, dieses Repo verbinden, App-of-Apps, Jellyfin migrieren | GitOps, Reconciliation, Drift |
| 13 | Secrets im Git | Sealed Secrets einrichten, Tailscale-OAuth-Secret verschlüsseln | Controller, Verschlüsselung |

### Teil D – Weitere Apps (jeweils kurz, gleiches Muster)
| # | App | Zweck |
|---|-----|-------|
| 14 | Homepage | Dashboard mit Links zu allen Diensten (nutzt K8s-API für Auto-Discovery) |
| 15 | Jellyseerr | Wunschliste/Anfragen für Filme & Serien |
| 16 | Vaultwarden | Passwortmanager (Bitwarden-kompatibel) |
| 17 | Immich | Foto-Backup vom Handy (mehrere Komponenten + Postgres + Redis → Lernbeispiel für Multi-Service-Apps) |
| 18 | Paperless-ngx | Dokumentenverwaltung mit OCR |
| 19 | Uptime Kuma | Einfaches Uptime-Monitoring |
| (opt.) | *arr-Stack | Sonarr/Radarr/Prowlarr – optional, mit Hinweis auf rechtliche Lage |
| (opt.) | Home Assistant | Smart Home (Sonderfall: `hostNetwork`) |

### Teil E – Betrieb
| # | Kapitel | Inhalt | K8s-Konzepte |
|---|---------|--------|--------------|
| 20 | Monitoring & Logs | kube-prometheus-stack, Grafana-Dashboards, Loki | ServiceMonitor, Metrics |
| 21 | Backup & Restore | PVC-Backups auf externes Ziel, **Restore wirklich testen** | Snapshots, CronJob |
| 22 | Updates & Wartung | Renovate, k3s-Upgrades, Node drainen | Rolling Updates, `drain`/`cordon` |
| 23 | Ausblick | Zweiter Node, Longhorn, HA, Talos, NetworkPolicies, Resource Quotas | Multi-Node, Scheduling |

---

## 5. Umsetzungs-Phasen (für das Repo)

1. **Phase 1 – Gerüst:** README, Repo-Struktur, Kapitel 00–04 (Fundament) + Skripte zur Host-Vorbereitung.
2. **Phase 2 – Grundlagen:** Kapitel 05–08 mit Beispiel-Manifesten in `examples/`.
3. **Phase 3 – Kern-Homelab:** Kapitel 09–13, Manifeste in `kubernetes/` (Tailscale Operator, Jellyfin, GPU, Argo CD, Sealed Secrets).
4. **Phase 4 – Apps:** Kapitel 14–19, je App ein Ordner unter `kubernetes/apps/`.
5. **Phase 5 – Betrieb:** Kapitel 20–23, Monitoring, Backup, Renovate-Konfiguration.
6. **Laufend:** CI-Check (yamllint, kubeconform, Markdown-Linkcheck), damit Manifeste immer valide sind.

Jede Phase wird als eigener Commit/PR umgesetzt, sodass man den Fortschritt nachvollziehen kann.

---

## 6. Offene Fragen (bitte beantworten, dann passe ich den Plan an)

1. **Hardware:** Welche Hardware ist vorhanden oder geplant (CPU/GPU, RAM, Platten)? Ein Node oder mehrere?
2. **Medien:** Wo liegen die Medien – lokale Platte im Server oder ein NAS (NFS/SMB)?
3. **Betriebssystem:** Ist Ubuntu Server ok, oder lieber Debian / Proxmox als Unterbau (k3s in einer VM)?
4. **Apps:** Welche Apps neben Jellyfin sind dir wichtig? Soll der *arr-Stack rein?
5. **Vorwissen:** Wie viel Linux-/Docker-Erfahrung ist vorhanden? (bestimmt die Tiefe von Teil B)
6. **Zugriff:** Soll Jellyfin auch für Familie/Freunde erreichbar sein (Tailscale-Sharing) oder für Geräte ohne Tailscale (z. B. Smart-TV → Tailscale Subnet Router / Funnel)?
7. **Sprache:** Tutorial komplett auf Deutsch (Annahme), Code-Kommentare ebenfalls Deutsch?
