# 00 – Einführung

> **Was du am Ende hast:** Du weißt, was wir bauen, wie das Tutorial aufgebaut ist und was Kubernetes grob macht.
>
> ⏱️ **Zeit:** 15 Minuten Lesen

---

## Was bauen wir?

Aus einem alten Desktop-PC wird ein kleiner Heimserver, ein **Homelab**. Darauf laufen am Ende:

- **Jellyfin**: dein eigenes „Netflix“ für Filme und Serien, auf dem Samsung-TV, dem Handy und dem Laptop
- der ***arr-Stack**: Programme, die deine Mediensammlung automatisch organisieren
- weitere nützliche Apps: Dashboard, Passwortmanager, Foto-Backup, Dokumentenarchiv
- alles erreichbar **von unterwegs über Tailscale**, ohne einen einzigen offenen Port an deinem Router

Das eigentliche Ziel ist aber: **Du lernst dabei Kubernetes.** Jedes Konzept wird genau dann erklärt,
wenn du es brauchst, und zwar an einer App, die du danach wirklich benutzt.

## Das Zielbild

```
  Unterwegs: Laptop / Handy ──── Tailscale (privates, verschlüsseltes Netz) ───┐
                                                                               │
  Zu Hause:  Samsung-TV ──── Heimnetz ──────────────────────────────┐          │
                                                                    ▼          ▼
┌──────────────── Alter Desktop-PC: Proxmox VE ──────────────────────────────────────┐
│                                                                                    │
│   ┌──────────────── VM "k3s" (Ubuntu Server + Kubernetes) ───────────────────┐     │
│   │   Jellyfin   Sonarr   Radarr   qBittorrent   Vaultwarden   Immich   …    │     │
│   │   RTX 2070 Super (für schnelles Video-Umwandeln)                         │     │
│   └──────────────────────────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────────────────────────┘
```

Die Schichten von unten nach oben:

1. **Hardware**: dein Desktop-PC (Ryzen 5, 16 GB RAM, RTX 2070 Super, 500-GB-Festplatte)
2. **Proxmox VE**: verwaltet virtuelle Maschinen. Damit kannst du jederzeit Snapshots machen und bei Fehlern zurückspringen.
3. **Eine VM mit Ubuntu Server**: das Betriebssystem, auf dem Kubernetes läuft
4. **k3s**: ein schlankes Kubernetes
5. **Deine Apps**: als Container in Kubernetes

> 💡 **Warum so viele Schichten?** Für eine einzelne App wäre das übertrieben. Aber du willst Kubernetes *lernen*,
> und Proxmox gibt dir das wichtigste Werkzeug zum Lernen: **Fehler machen dürfen.** Etwas kaputt gemacht?
> Snapshot zurückspielen, weiter geht's.

## Kubernetes in 5 Minuten

Stell dir vor, du bist Chef eines Restaurants. Du sagst deinem Küchenchef nicht jeden Handgriff, sondern nur:
*„Es sollen immer 3 Köche am Herd stehen.“* Fällt einer aus, holt der Küchenchef selbstständig Ersatz.

Genau so funktioniert Kubernetes:

- Du beschreibst in einer Textdatei (einem **Manifest**), *was* laufen soll, zum Beispiel:
  „Jellyfin soll laufen, mit 4 GB RAM, und die Filme liegen in `/data/media`.“
- Kubernetes sorgt dafür, dass es **so ist, und so bleibt**. Stürzt Jellyfin ab, startet Kubernetes es neu.
  Startet der Server neu, fährt Kubernetes alles wieder hoch.

Die wichtigsten Begriffe, die dir gleich begegnen:

| Begriff | Vergleich | Bedeutung |
|---------|-----------|-----------|
| **Cluster** | das Restaurant | alle Rechner, die zusammen Kubernetes bilden (bei uns: eine VM) |
| **Node** | ein Herd | ein einzelner Rechner im Cluster |
| **Pod** | ein Koch bei der Arbeit | eine laufende App (ein oder mehrere Container) |
| **Deployment** | „immer 1 Koch für Pizza“ | sorgt dafür, dass ein Pod läuft, und ersetzt ihn, wenn er ausfällt |
| **Service** | die Durchreiche | feste Adresse, unter der man einen Pod erreicht, egal wie oft er neu gestartet wurde |
| **kubectl** | dein Telefon zum Küchenchef | das Programm, mit dem du Kubernetes Anweisungen gibst |

Keine Sorge, wenn das noch abstrakt ist. In **Teil B** probierst du jeden Begriff selbst aus.
Alle Begriffe findest du auch im [Glossar](glossar.md).

## Wie du dieses Tutorial liest

### Aufbau jedes Kapitels

| Abschnitt | Inhalt |
|-----------|--------|
| **Was du am Ende hast** | Das Ziel des Kapitels in einem Satz |
| ⏱️ **Zeit** | Grobe Dauer |
| 🧠 **Neue Begriffe** | Was du in diesem Kapitel lernst |
| **Schritte** | Die eigentliche Anleitung |
| ✅ **Checkpoint** | So prüfst du, ob alles geklappt hat. **Nicht überspringen!** |
| 🔧 **Wenn etwas schiefgeht** | Die häufigsten Probleme und ihre Lösung |
| 🎓 **Was du gelernt hast** | Kurze Zusammenfassung |

### Wo wird ein Befehl ausgeführt?

Du arbeitest an drei verschiedenen Orten. Vor jedem Befehl steht, wo er hingehört:

| Symbol | Ort | Woran du es erkennst |
|--------|-----|----------------------|
| 💻 | **Dein Rechner** (NixOS-Laptop/PC) | Dein normales Terminal |
| 🟧 | **Proxmox** (der Desktop-PC) | Shell in der Proxmox-Weboberfläche oder `ssh root@pve` |
| 🐧 | **Die VM `k3s`** | `ssh homelab@k3s`, die Eingabezeile zeigt `homelab@k3s:~$` |

Beispiel:

> 🐧 **In der VM**

```bash
hostname
```

Erwartete Ausgabe:

```
k3s
```

### Platzhalter

Werte, die du durch deine eigenen ersetzen musst, stehen in spitzen Klammern: `<DEIN-WERT>`.
Die Klammern selbst gehören nicht dazu. Beispiel: Aus `ssh <BENUTZER>@k3s` wird `ssh homelab@k3s`.

In [Kapitel 01](01-voraussetzungen.md) legst du einen **Spickzettel** mit all deinen Werten an.

### Kopieren und einfügen, aber lesen!

Du darfst alle Befehle kopieren. Lies aber vorher die Erklärung dazu: Das Tutorial soll dir etwas beibringen,
nicht nur einen Server hinstellen.

## Kapitelübersicht

### Teil A – Fundament
- [00 – Einführung](00-einfuehrung.md) ← du bist hier
- [01 – Voraussetzungen](01-voraussetzungen.md)
- [02 – Proxmox installieren](02-proxmox-installieren.md)
- [03 – Tailscale auf Proxmox](03-tailscale-proxmox.md)
- [04 – Die Kubernetes-VM](04-kubernetes-vm.md)
- [05 – k3s installieren](05-k3s-installieren.md)

### Teil B – Kubernetes-Grundlagen
- [06 – Erster Pod](06-erster-pod.md)
- [07 – Deployments & Services](07-deployments-services.md)
- [08 – Konfiguration & Daten](08-konfiguration-daten.md)
- [09 – Helm](09-helm.md)

### Teil C – Das Homelab-Herz
- [10 – Tailscale Operator](10-tailscale-operator.md)
- [11 – Jellyfin](11-jellyfin.md)
- [12 – Jellyfin auf dem Samsung-TV](12-samsung-tv.md)
- [13 – GitOps mit Argo CD](13-argocd.md)
- [14 – Secrets im Git](14-sealed-secrets.md)
- [15 – GPU an die VM durchreichen](15-gpu-passthrough.md)
- [16 – GPU in Kubernetes](16-gpu-kubernetes.md)

### Teil D – *arr-Stack mit Proton VPN
- [17 – Wie der *arr-Stack zusammenspielt](17-arr-ueberblick.md)
- [18 – qBittorrent + Proton VPN](18-qbittorrent-vpn.md)
- [19 – Prowlarr](19-prowlarr.md)
- [20 – Sonarr & Radarr](20-sonarr-radarr.md)
- [21 – Bazarr & Seerr](21-bazarr-seerr.md)

### Teil E – Weitere Apps
- [22 – Homepage](22-homepage.md)
- [23 – Vaultwarden](23-vaultwarden.md)
- [24 – Immich](24-immich.md)
- [25 – Paperless-ngx](25-paperless.md)
- [26 – Uptime Kuma](26-uptime-kuma.md)

### Teil F – Betrieb
- [27 – Backup & Restore](27-backup-restore.md)
- [28 – Updates & Wartung](28-updates-wartung.md)
- [29 – Troubleshooting-Handbuch](29-troubleshooting.md)

### Teil G – Ausbau
- [30 – SSD nachrüsten](30-ssd-nachruesten.md)
- [31 – Monitoring mit Prometheus & Grafana](31-monitoring.md)
- [32 – Mehr Nodes](32-mehr-nodes.md)

Die vollständige Planung findest du in [PLAN.md](../PLAN.md).

## 🎓 Was du gelernt hast

- Wir bauen ein Homelab in Schichten: Hardware → Proxmox → VM → k3s → Apps.
- Kubernetes sorgt dafür, dass der *beschriebene* Zustand dauerhaft eingehalten wird.
- Jedes Kapitel hat Checkpoints, und vor jedem Befehl steht, wo er ausgeführt wird (💻 / 🟧 / 🐧).

---

➡️ **Weiter:** [01 – Voraussetzungen](01-voraussetzungen.md)
