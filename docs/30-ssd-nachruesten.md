# 30 – SSD nachrüsten

> **Was du am Ende hast:** Die Systemplatte der VM liegt auf einer schnellen SSD. Die alte HDD steht fast vollständig
> für Medien und Fotos zur Verfügung.
>
> ⏱️ **Zeit:** ca. 1 Stunde (plus Einbau)
>
> 🧠 **Neue Begriffe:** Storage verschieben (Move Disk), Disk vergrößern (Resize), `resize2fs`

---

## Warum?

Mit nur einer HDD teilen sich Proxmox, die VM-Systemplatte (Apps, Datenbanken, Container-Images) und die Medien
denselben langsamen Datenträger. Zwei typische Folgen:

- **Langsam:** Datenbanken (Immich, Sonarr …) und Container-Starts warten auf die HDD.
- **Eng:** 300 GB für Medien und Fotos sind schnell voll, und auf der 60-GB-Systemplatte wird es mit großen Images
  (z. B. Immich-CUDA) auch knapp.

Eine SSD mit **500 GB bis 1 TB** kostet nicht viel und löst beides.

## Der Plan

```
 Vorher (eine HDD)                         Nachher
┌──────────── HDD 500 GB ────────────┐    ┌──── SSD (neu) ────┐  ┌──────── HDD 500 GB ─────────┐
│ Proxmox │ VM-System 60 │ Daten 300 │    │ VM-System 60 → 120│  │ Proxmox │ Daten 300 → ~380  │
└────────────────────────────────────┘    └───────────────────┘  └─────────────────────────────┘
```

Proxmox selbst bleibt auf der HDD. Das ist unkritisch, denn Proxmox liest und schreibt wenig.
Wir verschieben nur die **VM-Systemplatte** auf die SSD und vergrößern danach die **Datenplatte**.
Proxmox kann Platten verschieben, **während die VM läuft**.

> 📸 Vorher: Prüfen, dass das nächtliche Backup (Kapitel 27) von heute erfolgreich war.

## 1. SSD einbauen

- **SATA-SSD** (2,5"): SATA-Kabel und Strom anschließen.
- **NVMe-SSD** (M.2): in den M.2-Steckplatz des Mainboards. Handbuch prüfen, bei manchen Boards teilt sich ein
  M.2-Slot die Anschlüsse mit SATA-Ports.

Nach dem Einschalten in Proxmox unter **pve → Disks** nachsehen: Die SSD taucht auf (z. B. `/dev/sdc` oder `/dev/nvme0n1`).

## 2. SSD als Speicher einrichten

**pve → Disks → LVM-Thin → Create: Thinpool**:

| Feld | Wert |
|------|------|
| Disk | die neue SSD |
| Name | **`ssd`** |
| Add Storage | ☑ |

Unter **Rechenzentrum → Storage** gibt es jetzt `ssd` (Inhalt: Disk-Image, Container).

## 3. Die Systemplatte umziehen

**100 (k3s) → Hardware**:

1. **Festplatte (scsi0)** markieren → **Disk-Aktion → Speicher verschieben**
   - Ziel-Speicher: **`ssd`**
   - ☑ **Quelle löschen**
   - **Disk verschieben**. Die VM läuft währenddessen weiter, die Kopie dauert je nach Belegung einige Minuten.
2. **EFI-Disk** ebenso auf `ssd` verschieben. (Geht das im laufenden Betrieb nicht: VM herunterfahren, verschieben, starten.)
3. Die **Datenplatte (scsi1)** bleibt auf `local-lvm`.

Unter **Hardware** steht jetzt `ssd:vm-100-disk-…` bei `scsi0`.

### Optional: Systemplatte vergrößern

Auf der SSD ist Platz, also bekommt das System mehr Luft:

1. **scsi0** markieren → **Disk-Aktion → Größe ändern** → `60` (GiB) hinzufügen.
2. In der VM die Partition und das Dateisystem mitwachsen lassen:

> 🐧 **In der VM:**

```bash
sudo growpart /dev/sda 2          # Partition 2 bis zum Ende der Platte vergrößern
sudo resize2fs /dev/sda2          # Dateisystem auf die neue Partitionsgröße bringen
df -h /
```

> 💡 Beide Befehle funktionieren im laufenden Betrieb. `growpart` kommt aus dem Paket `cloud-guest-utils`, das bei
> Ubuntu Server vorinstalliert ist.

## 4. Die Datenplatte vergrößern

Auf der HDD ist jetzt der Platz frei, den vorher die Systemplatte belegt hat. Wie viel?
**local-lvm → Übersicht**. Lass weiterhin **mindestens 30 GB frei** (Puffer für Snapshots, Kapitel 04).

1. **scsi1** markieren → **Disk-Aktion → Größe ändern** → z. B. `80` (GiB) hinzufügen.
2. In der VM das Dateisystem vergrößern. Da `/dev/sdb` keine Partitionen hat (Kapitel 04), reicht ein Befehl:

```bash
sudo resize2fs /dev/sdb
df -h /data
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb        374G  212G  159G  58% /data
```

3. Optional: Die Größenangaben in `kubernetes/apps/media/basis/pv-data.yaml` und `pvc-data.yaml` anpassen. Sie sind nur
   Beschreibungen (hostPath prüft sie nicht), aber so bleibt Git ehrlich.

## Alternative: die ganze HDD für Medien

Wer die HDD **komplett** für Medien will, installiert Proxmox neu auf der SSD und reicht die HDD per
**Disk-Passthrough** an die VM durch (`qm set 100 -scsi1 /dev/disk/by-id/ata-…`). Das ist aufwendiger (Neuinstallation,
Restore der VM aus dem Backup, Daten umkopieren) und nur nötig, wenn jedes Gigabyte zählt. Die Anleitung aus Kapitel 27
(Notfallplan) ist dafür der Fahrplan.

## ✅ Checkpoint

- [ ] Storage `ssd` existiert.
- [ ] `scsi0` und die EFI-Disk liegen auf `ssd`.
- [ ] `df -h /data` in der VM zeigt die neue, größere Datenplatte.
- [ ] `local-lvm` hat noch mindestens 30 GB frei.
- [ ] Alle Apps laufen (Argo CD grün, Uptime Kuma grün).

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| SSD erscheint nicht unter **Disks** | BIOS: Wird sie erkannt? Bei NVMe: M.2-Slot aktiviert? |
| „Speicher verschieben“ bricht ab | Genug Platz auf `ssd`? VM herunterfahren und erneut versuchen |
| `resize2fs`: `Nothing to do!` | Die Platte wurde in Proxmox noch nicht vergrößert, oder bei scsi0 fehlte `growpart` |
| Backup-Job meldet Fehler | Backup-Job nutzt weiterhin `usb-backup`, das ist unverändert. Log lesen |

## 🎓 Was du gelernt hast

- Proxmox kann VM-Platten **im laufenden Betrieb** auf einen anderen Speicher verschieben.
- Platten werden in zwei Schritten vergrößert: erst in Proxmox (die „Hardware“), dann in der VM (`growpart` + `resize2fs`).
- Die Trennung von System- und Datenplatte aus Kapitel 04 zahlt sich jetzt aus.

---

⬅️ **Zurück:** [29 – Troubleshooting-Handbuch](29-troubleshooting.md) · ➡️ **Weiter:** [31 – Monitoring](31-monitoring.md)
