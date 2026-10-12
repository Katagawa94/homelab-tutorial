# 32 – Speicher erweitern: die 1-TB-HDD einbinden

> **Was du am Ende hast:** Die 1-TB-HDD ist eingebaut. Die Datenplatte `/data` (Medien, Nextcloud, Fotos) ist im
> laufenden Betrieb von der SSD auf die HDD umgezogen und auf rund 850 GB gewachsen. Die SSD hat wieder Platz für System,
> Datenbanken und Snapshots.
>
> ⏱️ **Zeit:** ca. 1–2 Stunden (plus Einbau, das Umziehen läuft größtenteils von allein)
>
> 🧠 **Neue Begriffe:** Storage verschieben (Move Disk), Disk vergrößern (Resize), `resize2fs`, `growpart`

---

## Ausgangslage und Ziel

Bisher liegt alles auf der 500-GB-SSD: Proxmox, die Systemplatte der VM (60 GB) und die Datenplatte `/data` (300 GB).
Die SSD ist damit fast voll, und für Filme und Fotos sind 300 GB knapp.

```
 Vorher                                         Nachher
┌──────────────── SSD 500 GB ────────────────┐   ┌──────── SSD 500 GB ────────┐  ┌───────── HDD 1 TB ─────────┐
│ Proxmox │ VM-System 60 │ /data 300 │ frei  │   │ Proxmox │ VM-System 120 │  │ /data ~850         │ Puffer │
└────────────────────────────────────────────┘   │         │ frei (Snapshots)│  └────────────────────────────┘
                                                 └─────────────────────────────┘
```

| Was | Liegt danach auf | Warum |
|-----|------------------|-------|
| Proxmox | SSD | bleibt, wo es ist |
| VM-Systemplatte (Ubuntu, k3s, Datenbanken, App-Einstellungen) | **SSD** | viele kleine Zugriffe, da zählt Geschwindigkeit |
| Datenplatte `/data` (Filme, Serien, Nextcloud-Dateien, Fotos) | **HDD** | große Dateien, da zählt Platz. Eine HDD liefert locker genug für mehrere Filme gleichzeitig |

Das Beste daran: Für die VM und Kubernetes **ändert sich nichts**. In der VM heißt die Platte weiter `/dev/sdb` und ist
weiter unter `/data` eingebunden. Kein Manifest muss angepasst werden.

## Wie der „Umzug“ funktioniert

Proxmox kann die virtuelle Festplatte einer VM **im laufenden Betrieb** auf einen anderen Speicher verschieben
(*Move Disk*):

1. Proxmox legt auf der HDD eine leere Kopie der Platte an.
2. Im Hintergrund werden alle Daten von der SSD auf die HDD kopiert. Die VM läuft weiter, und was sie währenddessen
   schreibt, wird auf beiden Seiten nachgezogen (*Spiegeln*).
3. Sind beide Seiten gleich, schaltet Proxmox die VM in einem Augenblick auf die HDD um und löscht die alte Kopie.

Die Apps merken davon nichts, außer dass die Platte während des Kopierens etwas langsamer ist. Genau so tauschst du
später auch einmal eine Platte gegen eine größere: neue Platte → neuer Speicher → Platte verschieben → alte Platte ausbauen.

## 1. Vorbereiten

1. **Backup prüfen:** Im Proxmox unter **usb-backup → Backups** muss eine Sicherung von heute oder gestern liegen,
   und der restic-Job (Kapitel 29) sollte erfolgreich gelaufen sein: `kubectl get jobs -n backup`.
2. **Snapshots löschen:** Proxmox verschiebt keine Platten, zu denen es noch Snapshots gibt.
   **100 (k3s) → Snapshots** → alle Snapshots markieren → **Entfernen**.
3. Optional: Laufende Downloads in qBittorrent pausieren. Dann muss beim Umzug weniger nachgezogen werden.

## 2. HDD einbauen

PC herunterfahren (in Proxmox oben rechts **Herunterfahren**), Strom ab, die HDD mit SATA-Daten- und Stromkabel
anschließen, wieder einschalten.

In Proxmox unter **pve → Disks** taucht die neue Platte auf, z. B. als `/dev/sdb` mit Typ `hdd` und ca. 931 GB.

> ⚠️ Prüfe Größe und Typ genau, damit du im nächsten Schritt nicht die SSD erwischst. War die HDD schon einmal in Benutzung
> (Partitionen sichtbar), markiere sie und klicke **Wipe Disk**. Alles darauf wird gelöscht.

## 3. Die HDD als Speicher einrichten

**pve → Disks → LVM-Thin → Create: Thinpool**:

| Feld | Wert |
|------|------|
| Disk | die neue HDD |
| Name | **`hdd`** |
| Add Storage | ☑ |

Unter **Rechenzentrum → Storage** gibt es jetzt `hdd` neben `local-lvm` (der SSD). Das ist derselbe Speichertyp wie
`local-lvm` (Kapitel 02), nur auf der anderen Platte.

## 4. Den Speicher tauschen: `/data` auf die HDD verschieben

**100 (k3s) → Hardware**:

1. Die Datenplatte **Festplatte (scsi1)** markieren (die mit 300 GB, nicht `scsi0`!).
2. **Disk-Aktion → Speicher verschieben**
   - **Ziel-Speicher:** `hdd`
   - ☑ **Quelle löschen**
3. **Disk verschieben**

Es öffnet sich ein Fenster mit dem Fortschritt:

```
drive-scsi1: transferred 112.4 GiB of 300.0 GiB (37.47%) in 12m 3s
...
drive-scsi1: transferred 300.0 GiB of 300.0 GiB (100.00%) in 32m 41s, ready
all 'mirror' jobs are ready
switching to actively synced mode
drive-scsi1: Completing block job...
drive-scsi1: Completed successfully.
TASK OK
```

Je nach Füllstand dauert das 10 bis 60 Minuten. Du kannst das Fenster schließen, die Aufgabe läuft weiter (unten in der
Aufgabenliste). Danach steht unter **Hardware** bei `scsi1` jetzt `hdd:vm-100-disk-…`.

Weil die Platte jetzt eine echte HDD ist: `scsi1` → **Bearbeiten** → **SSD-Emulation** ☐ abwählen → **OK**. (Das wirkt
erst beim nächsten Neustart der VM und ist nur eine Feinheit, eilt also nicht.)

## 5. Die Datenplatte vergrößern

Auf der HDD ist reichlich Platz. Wir vergrößern `/data` in zwei Schritten: erst die „Hardware“ in Proxmox, dann das
Dateisystem in der VM.

### In Proxmox

Wie viel ist frei? **hdd → Übersicht**: ca. 930 GB. Lass wie auf der SSD einen **Puffer von mindestens 50 GB** für
Snapshots frei (ein volles Thin-Pool legt die VM lahm, Kapitel 04).

**scsi1** markieren → **Disk-Aktion → Größe ändern** → Zuwachs `550` (GiB) → **Größe ändern**. Die Platte hat dann 850 GB.

### In der VM

> 🐧 **In der VM** (`ssh homelab@k3s`)

```bash
lsblk -o NAME,SIZE,MOUNTPOINTS /dev/sdb
```

```
NAME  SIZE MOUNTPOINTS
sdb   850G /data
```

Die VM sieht die neue Größe bereits, das Dateisystem aber noch nicht:

```bash
df -h /data
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb        295G  212G   80G  73% /data
```

Das Dateisystem wachsen lassen (geht im laufenden Betrieb):

```bash
sudo resize2fs /dev/sdb
df -h /data
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb        837G  212G  616G  26% /data
```

Weil `/dev/sdb` keine Partitionen hat (Kapitel 04), reicht dieser eine Befehl.

> 💡 Zeigt `lsblk` noch die alte Größe? Dann die Platte neu einlesen lassen:
> `echo 1 | sudo tee /sys/class/block/sdb/device/rescan`

## 6. Die Systemplatte auf der SSD vergrößern

Auf der SSD sind jetzt rund 300 GB frei geworden. Die Systemplatte (Datenbanken, Container-Images, App-Einstellungen)
bekommt davon mehr Luft. Der Rest bleibt als Puffer für Snapshots.

1. In Proxmox: **scsi0** markieren → **Disk-Aktion → Größe ändern** → Zuwachs `60` (GiB). Die Platte hat dann 120 GB.
2. In der VM die Partition und das Dateisystem mitwachsen lassen:

```bash
sudo growpart /dev/sda 2          # Partition 2 bis zum Ende der Platte vergrößern
sudo resize2fs /dev/sda2          # Dateisystem auf die neue Partitionsgröße bringen
df -h /
```

Anders als `/dev/sdb` hat die Systemplatte Partitionen (EFI + System, Kapitel 04). Deshalb kommt hier zuerst `growpart`.
Das Werkzeug ist bei Ubuntu Server vorinstalliert.

## 7. Und Kubernetes?

Nichts zu tun. Alle PVs zeigen per `hostPath` auf Ordner unter `/data`, und die liegen jetzt einfach auf einer größeren
Platte. Prüfen:

```bash
kubectl get pods -A | grep -v -e Running -e Completed
```

Die Ausgabe sollte nur die Überschrift zeigen.

> 💡 In `pv-data.yaml` & Co. stehen Größen wie `300Gi`. Das sind bei `hostPath` nur Beschreibungen, und Kubernetes prüft
> sie nicht. **Lass die PVCs unverändert:** Ein PVC ohne StorageClass lässt sich nicht nachträglich vergrößern, und Argo CD
> würde beim Versuch einen Fehler melden.

Zum Schluss einen neuen Snapshot anlegen (`nach-hdd`), damit du wieder ein Sicherheitsnetz hast.

## Alternative: die HDD direkt durchreichen

Statt die HDD als Proxmox-Speicher zu nutzen, kann man sie auch komplett an die VM durchreichen
(`qm set 100 -scsi2 /dev/disk/by-id/ata-…`). Dann ist sie ein normales ext4-Laufwerk, das sich zur Not auch in einem
anderen PC lesen lässt. Nachteile: kein Live-Umzug (die Daten müssen per `rsync` umkopiert werden) und keine Snapshots
dieser Platte. Für dieses Homelab ist der Weg oben einfacher.

## ✅ Checkpoint

- [ ] Unter **Rechenzentrum → Storage** gibt es `hdd`.
- [ ] Bei **100 (k3s) → Hardware** liegt `scsi1` auf `hdd`, `scsi0` auf `local-lvm`.
- [ ] `df -h /data` in der VM zeigt ca. 837 GB, `df -h /` ca. 118 GB.
- [ ] `hdd` und `local-lvm` haben jeweils noch mindestens 50 GB frei.
- [ ] Alle Apps laufen (Argo CD grün, Uptime Kuma grün), und Jellyfin, Nextcloud und Immich zeigen ihre Dateien.
- [ ] Ein neuer Snapshot ist angelegt.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| „Speicher verschieben“ meldet etwas zu Snapshots | Es gibt noch Snapshots der VM → Schritt 1 |
| HDD erscheint nicht unter **Disks** | Wird sie im BIOS erkannt? SATA- und Stromkabel prüfen |
| Verschieben bricht ab: `not enough space` | Ist `hdd` groß genug? Wurde der richtige Ziel-Speicher gewählt? |
| `resize2fs`: `The filesystem is already … blocks long. Nothing to do!` | Die VM kennt die neue Größe noch nicht → `rescan` (siehe Tipp in Schritt 5) bzw. Proxmox-Vergrößerung prüfen |
| `growpart`: `NOCHANGE` | Die Systemplatte wurde in Proxmox noch nicht vergrößert |
| Apps sind nach dem Umzug langsamer | Beim Start nach dem Umzug normal (Caches leer). Datenbanken liegen auf der SSD und sind nicht betroffen |
| Nach einem Neustart fehlt `/data` | `sudo blkid \| grep data` muss die Platte mit `LABEL="data"` zeigen. Die Zeile in `/etc/fstab` (Kapitel 04) bleibt unverändert gültig |

## 🎓 Was du gelernt hast

- Proxmox kann VM-Platten **im laufenden Betrieb** auf einen anderen Speicher verschieben, indem es sie spiegelt und dann umschaltet.
- Schnelle SSD für viele kleine Zugriffe (System, Datenbanken), große HDD für große Dateien (Medien, Fotos).
- Platten werden in zwei Schritten vergrößert: erst in Proxmox (die „Hardware“), dann in der VM (`resize2fs`, bei Partitionen vorher `growpart`).
- Die Trennung von System- und Datenplatte aus Kapitel 04 zahlt sich jetzt aus: Der Umzug ist für Kubernetes unsichtbar.

---

⬅️ **Zurück:** [31 – Troubleshooting-Handbuch](31-troubleshooting.md) · ➡️ **Weiter:** [33 – Monitoring mit Prometheus & Grafana](33-monitoring.md)
