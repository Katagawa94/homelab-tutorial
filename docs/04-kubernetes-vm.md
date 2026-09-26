# 04 – Die Kubernetes-VM

> **Was du am Ende hast:** Eine VM `k3s` mit Ubuntu Server, fester IP und SSH-Zugang per Key, dazu eine zweite
> Festplatte unter `/data` für Medien und Downloads. Außerdem hast du den ersten Snapshot als Sicherheitsnetz.
>
> ⏱️ **Zeit:** ca. 1 Stunde
>
> 🧠 **Neue Begriffe:** [VM](glossar.md#homelab--infrastruktur), [Snapshot](glossar.md#homelab--infrastruktur),
> [Statische IP](glossar.md#netzwerk), [SSH-Key](glossar.md#netzwerk)

---

## Überblick

Wir bauen diese VM:

| Einstellung | Wert | Warum |
|-------------|------|-------|
| Name / ID | `k3s` / `100` | |
| Betriebssystem | Ubuntu Server 24.04 LTS | Viele Anleitungen, offizielle NVIDIA-Treiber, Updates bis 2029 |
| Maschinentyp / BIOS | `q35` / `OVMF (UEFI)` | **Voraussetzung für das GPU-Passthrough** in Kapitel 15 |
| Secure Boot | aus | NVIDIA-Treiber lassen sich so ohne Signatur-Umwege installieren |
| CPU | 8 Kerne, Typ `host` | Die VM sieht die echte CPU, was schneller ist |
| RAM | 12 GB, ohne Ballooning | 4 GB bleiben für Proxmox. Mit durchgereichter GPU ist Ballooning ohnehin nicht möglich |
| Disk 1 | 60 GB | Ubuntu, k3s und die Konfigurationen aller Apps |
| Disk 2 | 300 GB, **ohne Backup** | `/data`: Medien und Downloads |

> 💡 **Warum zwei Festplatten?** Medien sind groß und lassen sich neu beschaffen. App-Konfigurationen sind klein und
> wertvoll. Mit getrennten Platten sichern wir später nur das Wichtige (Disk 1) und können Disk 2 bei Bedarf mit einem
> Klick auf eine größere Festplatte umziehen.

## 1. Ubuntu-Image herunterladen

Proxmox kann ISO-Dateien direkt aus dem Internet laden, du musst nichts hochladen.

1. Öffne auf deinem Rechner <https://releases.ubuntu.com/noble/> und kopiere den Link zur Datei
   `ubuntu-24.04.X-live-server-amd64.iso` (Rechtsklick → Link kopieren; `X` ist die aktuelle Nummer).
2. In Proxmox: links **local (pve)** → **ISO-Images** → **Von URL herunterladen**
3. Link einfügen → **URL abfragen** → **Herunterladen**. Warte auf `TASK OK`.

## 2. VM erstellen

Klicke oben rechts auf **VM erstellen** und fülle die Reiter so aus:

### Allgemein

| Feld | Wert |
|------|------|
| Knoten | `pve` |
| VM ID | `100` |
| Name | `k3s` |

### Betriebssystem

| Feld | Wert |
|------|------|
| ISO-Image | `ubuntu-24.04.X-live-server-amd64.iso` |
| Gast-OS Typ / Version | `Linux` / `6.x - 2.6 Kernel` |

### System ⚠️ wichtig

| Feld | Wert |
|------|------|
| Grafikkarte | Standard |
| Maschine | **`q35`** |
| BIOS | **`OVMF (UEFI)`** |
| EFI-Disk hinzufügen | ☑, Speicher `local-lvm` |
| Schlüssel vorregistrieren (Pre-Enroll keys) | **☐ aus** (damit ist Secure Boot deaktiviert) |
| SCSI-Controller | `VirtIO SCSI single` |
| Qemu Agent | ☑ |
| TPM hinzufügen | ☐ |

> 💡 `q35` und UEFI lassen sich nachträglich nur mit Neuinstallation ändern. Deshalb stellen wir sie schon jetzt
> passend für die Grafikkarte ein, obwohl wir sie erst in Kapitel 15 brauchen.

### Festplatten

| Feld | Wert |
|------|------|
| Bus/Gerät | `SCSI` `0` |
| Speicher | `local-lvm` |
| Größe (GiB) | `60` |
| Discard | ☑ (gibt freigewordenen Platz an Proxmox zurück) |
| IO thread | ☑ |
| SSD-Emulation | ☐ (wir haben eine HDD) |

### CPU

| Feld | Wert |
|------|------|
| Sockel | `1` |
| Kerne | `8` |
| Typ | **`host`** |

> 💡 Dein Ryzen 5 hat vermutlich 6 Kerne mit 12 Threads, also sieht Proxmox 12 CPUs. Prüfe das mit `nproc` auf Proxmox.
> Faustregel: höchstens zwei Drittel an die VM geben. Bei 8 Threads (4-Kern-Ryzen) nimm `6`.

### Speicher

| Feld | Wert |
|------|------|
| Speicher (MiB) | `12288` |
| Erweitert → Ballooning-Gerät | **☐ aus** |

(Für „Erweitert“ oben rechts im Dialog das Häkchen **Erweitert** setzen.)

### Netzwerk

| Feld | Wert |
|------|------|
| Bridge | `vmbr0` |
| Modell | `VirtIO (paravirtualisiert)` |

### Bestätigen

**Nach Erstellen starten** ☐ **nicht** anhaken, denn wir fügen zuerst die zweite Festplatte hinzu. → **Abschließen**

## 3. Zweite Festplatte für `/data`

1. Links **100 (k3s)** → **Hardware** → **Hinzufügen** → **Festplatte**
2. Ausfüllen (Häkchen **Erweitert** setzen):

| Feld | Wert |
|------|------|
| Bus/Gerät | `SCSI` `1` |
| Speicher | `local-lvm` |
| Größe (GiB) | `300` |
| Discard | ☑ |
| IO thread | ☑ |
| **Sicherung (Backup)** | **☐ aus**, damit landen die Medien nicht im Backup |

3. **Hinzufügen**

> ⚠️ **Warum nicht mehr als 300 GB?** `local-lvm` hat etwa 410 GB. 60 + 300 GB sind verplant, der Rest ist **Puffer für
> Snapshots**. Läuft `local-lvm` voll, bleiben *alle* VMs stehen. Behalte die Auslastung unter
> **local-lvm → Übersicht** im Blick.

## 4. Automatisch starten

**100 (k3s)** → **Optionen** → **Beim Booten starten** → Doppelklick → ☑ → **OK**

Jetzt startet die VM automatisch, wenn der Desktop-PC hochfährt, zum Beispiel nach einem Stromausfall.

## 5. Ubuntu installieren

Klicke oben rechts auf **Start**, dann links auf **Konsole**. Im Bootmenü **Try or Install Ubuntu Server** wählen.

Der Installer wird mit den Pfeiltasten, `Tab` und `Enter` bedient. Die Leertaste setzt Häkchen.

| Schritt | Eingabe |
|---------|---------|
| Language | **English**. Fehlermeldungen auf Englisch findet man viel leichter im Netz |
| Installer update available | **Update to the new installer** |
| Keyboard | Layout **German** |
| Type of installation | **Ubuntu Server** (nicht „minimized“) |
| Network | siehe unten ⬇️ |
| Proxy | leer lassen |
| Ubuntu archive mirror | Vorschlag übernehmen |
| Storage | siehe unten ⬇️ |
| Profile | Your name: `Homelab` · Server's name: **`k3s`** · Username: **`homelab`** · Passwort → Passwortmanager |
| Ubuntu Pro | **Skip for now** |
| SSH | ☑ **Install OpenSSH server** · Import SSH key: **from GitHub** · GitHub Username: `<DEIN-GITHUB-NAME>` · ☐ Allow password authentication |
| Featured server snaps | **nichts auswählen**, auch nicht `microk8s` oder `docker` |

### Netzwerk: feste IP

1. Wähle das Interface `ens18` → **Edit IPv4**
2. **IPv4 Method:** `Manual`

| Feld | Beispielwert |
|------|--------------|
| Subnet | `192.168.178.0/24` |
| Address | `192.168.178.11` |
| Gateway | `192.168.178.1` |
| Name servers | `192.168.178.1` |
| Search domains | *(leer)* |

### Speicher: die richtige Platte wählen ⚠️

1. **Use an entire disk** → wähle die Platte mit **60.000G** (nicht die mit 300G!)
2. ☐ **Set up this disk as an LVM group** → **abwählen**
3. **Done**. In der Übersicht muss `/` auf der 60-GB-Platte liegen. Die 300-GB-Platte bleibt unbenutzt, die richten wir gleich selbst ein.
4. **Continue** bestätigen

> 💡 Ohne LVM nutzt Ubuntu die ganze Platte direkt. Mit LVM würde Ubuntu standardmäßig nur einen Teil davon
> verwenden, was Einsteiger oft verwirrt.

### Abschluss

Die Installation dauert einige Minuten. Wenn **Reboot Now** erscheint:

1. In Proxmox: **Hardware** → **CD/DVD-Laufwerk** → **Bearbeiten** → **Keine Medien verwenden** → **OK**
2. In der Konsole **Reboot Now** wählen (ggf. danach `Enter` drücken)

Die VM startet neu und zeigt `k3s login:`. Einloggen musst du dich hier nicht, ab jetzt geht alles über SSH.

## 6. Erste Anmeldung per SSH

> 💻 **Auf deinem Rechner**

```bash
ssh homelab@192.168.178.11
```

Es wird **kein Passwort** abgefragt, weil dein SSH-Key von GitHub übernommen wurde. Die Eingabezeile ändert sich zu:

```
homelab@k3s:~$
```

## 7. Grundeinrichtung

> 🐧 **In der VM**

System aktualisieren (`sudo` fragt nach dem Passwort des Benutzers `homelab`):

```bash
sudo apt update && sudo apt full-upgrade -y
```

Den **QEMU Guest Agent** installieren. Er erlaubt Proxmox, mit der VM zu reden, z. B. um sie sauber herunterzufahren
oder die IP-Adresse anzuzeigen:

```bash
sudo apt install -y qemu-guest-agent
sudo systemctl start qemu-guest-agent
```

Zeitzone setzen und neu starten:

```bash
sudo timedatectl set-timezone Europe/Berlin
sudo reboot
```

Nach etwa 30 Sekunden kannst du dich wieder mit `ssh homelab@192.168.178.11` verbinden.
In Proxmox zeigt **100 (k3s) → Übersicht** jetzt unter **IPs** die Adresse der VM an. Das ist das Zeichen, dass der Guest Agent läuft.

## 8. Die Daten-Festplatte einrichten

> 🐧 **In der VM**

### Platte finden

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
```

```
NAME     SIZE TYPE MOUNTPOINTS
sda       60G disk
├─sda1     1G part /boot/efi
└─sda2    59G part /
sdb      300G disk
sr0     1024M rom
```

Die 300-GB-Platte ohne Partitionen und ohne Mountpoint ist unsere Daten-Platte, hier `sdb`.

### Formatieren

> ⚠️ Prüfe, dass du wirklich die **300G**-Platte formatierst.

```bash
sudo mkfs.ext4 -m 1 -L data /dev/sdb
```

- `ext4`: das Standard-Dateisystem von Linux
- `-m 1`: nur 1 % statt 5 % Reserve für den Systemverwalter. Auf einer reinen Datenplatte sparst du so ca. 12 GB
- `-L data`: gibt der Platte das Etikett (Label) `data`, unter dem wir sie gleich einbinden

### Dauerhaft einbinden

Ordner anlegen, in dem die Platte erscheinen soll:

```bash
sudo mkdir /data
```

Die Datei `/etc/fstab` legt fest, welche Platten beim Start eingebunden werden. Wir hängen eine Zeile an:

```bash
echo 'LABEL=data  /data  ext4  defaults,nofail  0  2' | sudo tee -a /etc/fstab
```

| Teil | Bedeutung |
|------|-----------|
| `LABEL=data` | die Platte mit dem Etikett `data` |
| `/data` | wird hier eingebunden |
| `ext4` | Dateisystem |
| `defaults,nofail` | Standardoptionen. `nofail`: Fehlt die Platte, startet die VM trotzdem |
| `0 2` | kein Dump-Backup, Dateisystem-Prüfung nach der Systemplatte |

Einbinden und prüfen:

```bash
sudo systemctl daemon-reload
sudo mount -a
df -h /data
```

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb        295G   28K  292G   1% /data
```

### Ordnerstruktur anlegen

```bash
sudo mkdir -p /data/media/movies /data/media/tv /data/downloads
sudo chown -R 1000:1000 /data
```

Warum `1000:1000`? Das ist die Benutzer- und Gruppennummer von `homelab`:

```bash
id
```

```
uid=1000(homelab) gid=1000(homelab) groups=1000(homelab),4(adm),27(sudo),…
```

Die Apps im Cluster (Jellyfin, Sonarr, qBittorrent …) laufen später ebenfalls mit der Nummer `1000`
(**PUID/PGID**). So dürfen alle in `/data` lesen und schreiben.

```
/data
├── downloads      ← qBittorrent lädt hierher
└── media
    ├── movies     ← Filme für Jellyfin
    └── tv         ← Serien für Jellyfin
```

> 💡 **Warum liegen Downloads und Medien auf derselben Platte?** So kann der *arr-Stack fertige Downloads per
> **Hardlink** in die Medienordner „verschieben“: Die Datei erscheint an beiden Orten, belegt aber nur einmal Platz.
> Mehr dazu in Kapitel 17.

## 9. Der erste Snapshot

Jetzt haben wir eine saubere Grundlage. Die sichern wir, bevor es mit Kubernetes losgeht.

1. In Proxmox: **100 (k3s)** → **Snapshots** → **Snapshot erstellen**
2. **Name:** `ubuntu-basis`
3. **RAM einbeziehen:** ☐
4. **Beschreibung:** `Ubuntu installiert, /data eingerichtet`
5. **OK**

> 💡 **Snapshot-Routine ab jetzt:** Vor jedem Kapitel einen Snapshot anlegen. Klappt etwas nicht:
> VM auswählen → **Snapshots** → Snapshot markieren → **Rollback**.
>
> ⚠️ Snapshots kosten Platz in `local-lvm`, der mit jeder Änderung wächst, auch in `/data`. Lösche alte Snapshots,
> sobald ein Kapitel erfolgreich abgeschlossen ist, und behalte nur die letzten zwei bis drei.

## ✅ Checkpoint

- [ ] `ssh homelab@192.168.178.11` funktioniert ohne Passwort.
- [ ] `hostname` in der VM gibt `k3s` aus.
- [ ] `df -h /data` zeigt ca. 295 GB.
- [ ] `ls -ln /data` zeigt die Ordner `downloads` und `media` mit Besitzer `1000 1000`.
- [ ] Proxmox zeigt unter **100 (k3s) → Übersicht** die IP der VM.
- [ ] Unter **Hardware** hat `scsi1` den Vermerk `backup=0`.
- [ ] Der Snapshot `ubuntu-basis` existiert.
- [ ] Test: VM über **Neustart** in Proxmox neu starten. Danach ist `/data` wieder eingebunden (`df -h /data`).

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| VM startet nicht: `KVM virtualisation configured, but not available` | SVM ist im BIOS nicht aktiviert → [Kapitel 01](01-voraussetzungen.md#5-bios-einstellen) |
| VM bootet nicht vom ISO (UEFI-Shell erscheint) | **Optionen → Bootreihenfolge**: CD-Laufwerk (`ide2`) aktivieren und nach oben schieben |
| `ssh` fragt nach einem Passwort bzw. `Permission denied (publickey)` | Der Key wurde nicht importiert. In der Proxmox-Konsole einloggen und `ssh-import-id gh:<DEIN-GITHUB-NAME>` ausführen |
| Falsche Platte für Ubuntu gewählt | VM löschen und Kapitel ab Schritt 2 wiederholen, das geht schneller als reparieren |
| `mount -a` meldet einen Fehler | Tippfehler in `/etc/fstab`. Mit `sudo nano /etc/fstab` die letzte Zeile korrigieren, **bevor** du neu startest |
| Keine Internetverbindung in der VM | IP, Gateway und DNS prüfen: `ip a`, `ip route`, `resolvectl status`. Die Einstellungen liegen in `/etc/netplan/` |

## 🎓 Was du gelernt hast

- Eine VM in Proxmox hat virtuelle Hardware: CPU, RAM, Festplatten, Netzwerk.
- `q35` und UEFI sind die Voraussetzung für das spätere Durchreichen der Grafikkarte.
- Festplatten werden formatiert (`mkfs`), eingebunden (`mount`) und über `/etc/fstab` dauerhaft eingetragen.
- Dateirechte hängen an Nummern (UID/GID). Deshalb laufen alle Apps später mit `1000`.
- Snapshots sind dein Sicherheitsnetz, aber kein Backup.

---

⬅️ **Zurück:** [03 – Tailscale auf Proxmox](03-tailscale-proxmox.md) · ➡️ **Weiter:** [05 – k3s installieren](05-k3s-installieren.md)
