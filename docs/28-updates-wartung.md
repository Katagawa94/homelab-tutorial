# 28 – Updates & Wartung

> **Was du am Ende hast:** Du weißt, wie jede Schicht deines Homelabs aktualisiert wird. Für die Apps schlägt dir
> **Renovate** neue Versionen automatisch als Pull Request vor. Ein Wartungskalender sagt dir, wann was dran ist.
>
> ⏱️ **Zeit:** ca. 45 Minuten (Einrichtung), danach ca. 15 Minuten pro Woche
>
> 🧠 **Neue Begriffe:** [Renovate](glossar.md#container--kubernetes), Pull Request, `cordon`/`drain`, Versionssprung (major/minor/patch)

---

## Die Schichten und wer sie aktualisiert

| Schicht | Wie | Wie oft |
|---------|-----|---------|
| Proxmox | Weboberfläche → **Updates** | monatlich |
| Ubuntu in der VM | Sicherheitsupdates **automatisch** (`unattended-upgrades`), Neustart von Hand | Neustart monatlich |
| NVIDIA-Treiber | kommt mit den Ubuntu-Updates, Versionssprung (z. B. 580 → 590) von Hand | selten |
| k3s (Kubernetes) | Installationsskript mit neuer Version | alle 2–3 Monate |
| Apps und Helm-Charts | **Renovate** → Pull Request → Merge → Argo CD | wöchentlich |

> 📸 **Vor jedem größeren Update:** Snapshot (bzw. prüfen, ob das nächtliche Backup von heute da ist).

## Versionsnummern lesen

Die meisten Programme nutzen **Semantic Versioning**: `MAJOR.MINOR.PATCH`, z. B. `4.0.20`.

| Teil | Beispiel | Bedeutung | Risiko |
|------|----------|-----------|--------|
| **Patch** | 4.0.20 → 4.0.21 | Fehlerbehebungen | gering |
| **Minor** | 4.0 → 4.1 | neue Funktionen, abwärtskompatibel | gering bis mittel |
| **Major** | 4 → 5 | große Änderungen, evtl. inkompatibel | **Release Notes lesen!** |

## 1. Renovate: Updates für die Apps

In `kubernetes/` stehen überall feste Versionen, z. B. `image: lscr.io/linuxserver/sonarr:4.0.20` oder
`targetRevision: 1.102.4`. Das ist gut, denn nichts ändert sich ungefragt. Aber wer merkt, dass es 4.0.21 gibt?

**Renovate** ist ein Bot, der dein Repository regelmäßig durchsucht, neue Versionen findet und dir für jede einen
**Pull Request** (Änderungsvorschlag) auf GitHub öffnet. Du prüfst und klickst auf **Merge**. Argo CD rollt es aus.

```
 Renovate findet Sonarr 4.0.21
        │
        ▼
 Pull Request "Update lscr.io/linuxserver/sonarr to 4.0.21"   ← mit Release Notes
        │   CI prüft die Manifeste (scripts/validate.sh)
        ▼
 Du: Merge ✔  ──► main ──► Argo CD ──► Cluster
```

### Die Konfiguration

Die liegt schon im Repository: [`renovate.json`](../renovate.json). Die wichtigsten Teile:

```json
{
  "extends": ["config:recommended"],
  "schedule": ["before 6am on saturday"],
  "kubernetes": {
    "managerFilePatterns": ["/^kubernetes/.+\\.yaml$/", "/^examples/.+\\.yaml$/"]
  },
  "argocd": {
    "managerFilePatterns": ["/^kubernetes/(katalog|aktiv)/.+\\.yaml$/"]
  },
  "packageRules": [
    {
      "matchUpdateTypes": ["major"],
      "dependencyDashboardApproval": true
    }
  ]
}
```

| Teil | Bedeutung |
|------|-----------|
| `schedule` | PRs nur samstags früh, dann hast du am Wochenende Zeit |
| `kubernetes` | in diesen Dateien nach `image:` suchen |
| `argocd` | in den Argo-CD-Applications nach Helm-Chart-Versionen suchen, in `katalog/` **und** `aktiv/`, damit beide Kopien gleich bleiben |
| `major` → `dependencyDashboardApproval` | Große Sprünge kommen erst nach deiner ausdrücklichen Freigabe |

Außerdem gibt es Sonderregeln: Immich-Server und -ML werden immer gemeinsam aktualisiert, die Immich-Datenbank gar nicht
automatisch (dort gelten die Anweisungen aus den Immich-Release-Notes).

### Renovate einschalten

1. Öffne <https://github.com/apps/renovate> → **Install** (bzw. **Configure**).
2. **Only select repositories** → `homelab-tutorial` → **Install**.
3. Fertig. Innerhalb einer Stunde legt Renovate im Repository ein Issue **„Dependency Dashboard“** an: eine Übersicht
   aller gefundenen Abhängigkeiten und anstehenden Updates.

> 💡 Renovate arbeitet auf dem **Standard-Branch**, genau wie Argo CD. Die ersten PRs erscheinen zum nächsten Termin
> (samstags). Willst du nicht warten, setz im Dependency Dashboard ein Häkchen bei einem Update.

### Einen Renovate-PR bearbeiten

1. PR auf GitHub öffnen. Renovate hat die **Release Notes** gleich in die Beschreibung kopiert: kurz überfliegen.
2. Unten müssen die **Checks grün** sein (unsere CI: `scripts/validate.sh`).
3. **Merge pull request** → **Confirm merge**.
4. In Argo CD **Refresh** oder bis zu drei Minuten warten. Die App wird aktualisiert.
5. Kurz prüfen: Läuft die App? Uptime Kuma grün?

**Und wenn es schiefgeht?** Auf GitHub im gemergten PR auf **Revert** klicken → neuer PR → Merge. Argo CD rollt die alte
Version zurück. Das ist GitOps in Aktion.

> ⚠️ **Datenbanken rollen nicht immer zurück.** Manche Apps ändern beim Update ihre Datenbank (z. B. Jellyfin 10 → 12),
> und die alte Version kann sie dann nicht mehr lesen. Bei **Major-Updates** deshalb vorher einen Snapshot machen und die
> Release Notes lesen.

## 2. Proxmox aktualisieren

**pve → Updates → Refresh → Upgrade** (wie in Kapitel 02). Wurde ein neuer Kernel installiert: **Neustart**. Proxmox
fährt die VM dabei über den Guest Agent sauber herunter und startet sie danach wieder (dank **Beim Booten starten**).

Große Versionssprünge (z. B. Proxmox 9 → 10) folgen einer eigenen Anleitung im
[Proxmox-Wiki](https://pve.proxmox.com/wiki/Category:Upgrade). Dafür lieber ein ruhiges Wochenende einplanen.

## 3. Ubuntu in der VM und Neustarts

Ubuntu installiert Sicherheitsupdates **von selbst** (`unattended-upgrades`). Manche davon, vor allem neue Kernel und
Treiber, wirken erst nach einem Neustart. Ob einer nötig ist:

> 🐧 **In der VM:**

```bash
cat /var/run/reboot-required 2>/dev/null || echo "Kein Neustart nötig"
```

Übrige Updates (nicht nur Sicherheit) von Hand:

```bash
sudo apt update && sudo apt full-upgrade -y
```

### Sauber neu starten: `drain`

Bevor du einen Node neu startest, sagst du Kubernetes Bescheid, damit die Apps geordnet beendet werden (Datenbanken
schreiben ihre Daten fertig):

> 💻 **Auf deinem Rechner:**

```bash
kubectl drain k3s --ignore-daemonsets --delete-emptydir-data
```

| Befehl | Wirkung |
|--------|---------|
| `kubectl cordon k3s` | Node für **neue** Pods sperren |
| `kubectl drain k3s` | sperren **und** alle Pods geordnet beenden |
| `kubectl uncordon k3s` | Sperre aufheben |

Mit nur einem Node gibt es keinen Ort, wohin die Pods umziehen könnten, sie bleiben also `Pending`. Genau das ist hier
gewollt: ein geordnetes Herunterfahren.

```bash
ssh homelab@k3s sudo reboot
# … warten, bis die VM wieder da ist
kubectl uncordon k3s
kubectl get pods -A          # nach ein paar Minuten läuft alles wieder
```

> 💡 Nach einem Treiber-Update: `nvidia-smi` in der VM prüfen und in Jellyfin einmal etwas transkodieren (Kapitel 16).

## 4. k3s aktualisieren

k3s wird aktualisiert, indem man das Installationsskript mit der gewünschten Version erneut ausführt. Die Einstellungen
aus `/etc/rancher/k3s/config.yaml` bleiben erhalten.

**Regel:** immer nur **eine Minor-Version** auf einmal (z. B. 1.34 → 1.35, nicht 1.34 → 1.36).

1. Aktuelle Version: `kubectl get nodes` (Spalte `VERSION`).
2. Verfügbare Versionen: <https://github.com/k3s-io/k3s/releases>. Die neueste Version der **nächsten** Minor-Reihe wählen
   und die Release Notes überfliegen.
3. Snapshot machen, dann:

> 🐧 **In der VM** (Version einsetzen):

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.35.3+k3s1' sh -
```

4. Prüfen:

```bash
kubectl get nodes
kubectl get pods -A | grep -v -e Running -e Completed
```

Die zweite Zeile sollte nach ein paar Minuten nur noch die Überschrift zeigen.

> 💡 Für Fortgeschrittene gibt es den **system-upgrade-controller**, der k3s-Updates selbst per GitOps ausführt.

## 5. Wartungskalender

| Wann | Was | Wo |
|------|-----|-----|
| **wöchentlich** (Samstag) | Renovate-PRs prüfen und mergen | GitHub |
| wöchentlich | kurzer Blick auf Uptime Kuma und Argo CD: alles grün? | Tailnet |
| **monatlich** | Proxmox-Updates + Neustart | Proxmox |
| monatlich | VM: `apt full-upgrade`, `drain`, Neustart, `uncordon` | VM |
| monatlich | Plattenplatz: `df -h /data` in der VM, `local-lvm` und `usb-backup` in Proxmox | |
| **vierteljährlich** | Restore-Test (Kapitel 27, Test A und B) | |
| vierteljährlich | k3s um eine Minor-Version anheben | VM |
| **jährlich** | GitHub-Token für Argo CD erneuern (Kapitel 13/14: neuer Token → neu versiegeln) | GitHub |
| jährlich | Proton-VPN-Abo und WireGuard-Schlüssel prüfen | Proton |

Trag dir die Termine in deinen Kalender ein.

## ✅ Checkpoint

- [ ] Die Renovate-App ist für dein Repository installiert, das Issue **Dependency Dashboard** existiert.
- [ ] Du hast mindestens einen Renovate-PR geprüft und gemergt (oder weißt, wie es geht).
- [ ] Du hast die VM einmal mit `drain` → Neustart → `uncordon` neu gestartet.
- [ ] Der Wartungskalender steht in deinem Kalender.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Renovate öffnet keine PRs | Dependency Dashboard lesen, dort stehen Fehler. App wirklich für das Repository freigegeben? |
| Renovate schlägt komische Versionen vor (z. B. mit Datum) | In `renovate.json` eine Regel mit `allowedVersions` ergänzen, wie bei Jellyfin |
| Nach dem Merge ist eine App kaputt | PR auf GitHub **reverten**. Bei Datenbank-Problemen: Snapshot/Backup zurückspielen |
| `kubectl drain` hängt | Meist wartet er auf einen Pod mit lokalem Speicher: `--delete-emptydir-data` vergessen? Mit `Strg+C` abbrechen ist harmlos, dann `kubectl uncordon k3s` |
| Nach dem Neustart bleiben Pods `Pending` | `kubectl uncordon k3s` vergessen |
| Nach dem k3s-Update: `Unable to connect` | `sudo systemctl status k3s` und `sudo journalctl -u k3s -n 100` in der VM |

## 🎓 Was du gelernt hast

- Jede Schicht (Proxmox, Ubuntu, Treiber, k3s, Apps) hat ihren eigenen Update-Weg.
- **Renovate** bringt Updates als Pull Request. Zusammen mit CI und Argo CD sind Updates ein Klick, und Rückgängig auch.
- **Semantic Versioning** hilft, das Risiko eines Updates einzuschätzen.
- `cordon`/`drain`/`uncordon` bereiten einen Node auf Wartung vor.
- k3s wird immer nur um eine Minor-Version angehoben.

---

⬅️ **Zurück:** [27 – Backup & Restore](27-backup-restore.md) · ➡️ **Weiter:** [29 – Troubleshooting-Handbuch](29-troubleshooting.md)
