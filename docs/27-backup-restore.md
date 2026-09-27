# 27 – Backup & Restore

> **Was du am Ende hast:** Jede Nacht wird die komplette VM auf eine USB-Platte gesichert, und deine Fotos zusätzlich
> mit **restic**. Du hast eine Wiederherstellung **wirklich ausprobiert** und weißt, was im Ernstfall zu tun ist.
>
> ⏱️ **Zeit:** ca. 1,5 Stunden
>
> 🧠 **Neue Begriffe:** [Backup](glossar.md#homelab--infrastruktur), 3-2-1-Regel, [CronJob](glossar.md#container--kubernetes),
> Job, [restic](glossar.md#homelab--infrastruktur), `projected`-Volume

---

## Snapshot ≠ Backup

Seit Kapitel 04 machst du Snapshots. Die liegen aber auf **derselben Festplatte** wie die VM. Stirbt die Platte,
sind VM **und** Snapshots weg. Ein **Backup** liegt auf einem **anderen** Datenträger.

Die bewährte **3-2-1-Regel**:

- **3** Kopien deiner Daten (Original + 2 Backups)
- auf **2** verschiedenen Datenträgern
- davon **1** an einem anderen Ort (außer Haus)

In diesem Kapitel schaffen wir die ersten beiden Punkte. Für den dritten gibt es am Ende einen Ausblick.

## Was muss gesichert werden?

| Daten | Wo | Wertvoll? | Gesichert durch |
|-------|-----|-----------|-----------------|
| Ubuntu, k3s, **alle Einstellungen** (PVCs mit `local-path`): Jellyfin, *arr, Vaultwarden, Paperless, Immich-Datenbank … | VM-Disk 1 (60 GB) | ⭐⭐⭐ | **Proxmox-Backup** (Schritt 2) |
| **Fotos** (Immich) | VM-Disk 2: `/data/photos` | ⭐⭐⭐ unersetzlich | **restic** (Schritt 3) |
| Filme und Serien | VM-Disk 2: `/data/media` | ⭐ lassen sich neu beschaffen | bewusst **nicht** (zu groß) |
| Downloads | VM-Disk 2: `/data/downloads` | – | nicht nötig |
| Manifeste, Einstellungen, verschlüsselte Secrets | GitHub | ⭐⭐⭐ | ist schon eine Kopie |
| Sealed-Secrets-Schlüssel, Passwörter | Passwortmanager | ⭐⭐⭐ | Kapitel 14 |

## 1. Die USB-Platte an Proxmox anschließen

Du brauchst eine externe USB-Festplatte. Empfohlen sind **mindestens 1 TB**, denn Proxmox speichert jede Sicherung vollständig.

> ⚠️ Die Platte wird **komplett gelöscht**.

1. Platte an den Desktop-PC anschließen.
2. In Proxmox: **pve → Disks**. Die neue Platte taucht auf (z. B. `/dev/sdb`, Typ `usb`).
   Hat sie schon Partitionen: markieren → **Wipe Disk**.
3. **pve → Disks → Directory → Create: Directory**:

| Feld | Wert |
|------|------|
| Disk | die USB-Platte |
| Filesystem | `ext4` |
| Name | **`usb-backup`** |
| Add Storage | ☑ |

Proxmox formatiert die Platte, bindet sie unter `/mnt/pve/usb-backup` ein und legt einen gleichnamigen **Storage** an.

4. **Rechenzentrum → Storage → usb-backup → Bearbeiten**: Bei **Inhalt** nur **VZDump-Backup-Datei** auswählen.

## 2. Nächtliches Proxmox-Backup der VM

**Rechenzentrum → Backup → Hinzufügen**:

| Reiter / Feld | Wert |
|---------------|------|
| Speicher | `usb-backup` |
| Zeitplan | `02:30` (täglich) |
| Auswahlmodus | Einbeziehen ausgewählter VMs → **100 (k3s)** |
| Modus | **Snapshot** (die VM läuft während der Sicherung weiter) |
| Komprimierung | ZSTD (schnell und gut) |
| Benachrichtigung | bei Fehlern per E-Mail (Kapitel 02: Adresse bei der Installation) |
| **Aufbewahrung** | Behalte täglich: `7` · wöchentlich: `4` · monatlich: `3` |

**OK**. Jetzt einmal von Hand starten: Job markieren → **Jetzt ausführen**. Unten in der Aufgabenliste siehst du den
Fortschritt. Die erste Sicherung dauert auf der HDD ein Weilchen.

> 💡 Die Datenplatte (`scsi1`) wird übersprungen, weil du in Kapitel 04 bei ihr **Sicherung** abgewählt hast. Im Log
> steht: `exclude disk 'scsi1' … (backup=no)`. So ist es gewollt.

Nach dem Durchlauf: **usb-backup → Backups** zeigt eine Datei wie `vzdump-qemu-100-2026_09_28-02_30_01.vma.zst`.

## 3. Die Fotos mit restic sichern

Die Fotos liegen auf der Datenplatte, und die ist vom Proxmox-Backup ausgenommen. Deshalb sichern wir sie
**aus dem Cluster heraus** mit **restic**, einem modernen Backup-Programm:

- Es sichert **inkrementell**: Nach dem ersten Mal werden nur neue und geänderte Dateien übertragen.
- Es **verschlüsselt** alles mit einem Passwort.
- Es **entfernt Duplikate** und behält beliebig viele alte Stände platzsparend.

Das Ziel ist dieselbe USB-Platte, erreichbar über SSH (SFTP) beim Proxmox-Host:

```
 VM k3s                                              Proxmox-Host
┌────────────────────────────────────┐   SSH/SFTP   ┌────────────────────────────────────┐
│ CronJob photos-backup (03:30)      │ ───────────► │ Benutzer "restic"                  │
│  liest /data (= /data/photos)      │              │ /mnt/pve/usb-backup/restic-photos/ │
└────────────────────────────────────┘              └────────────────────────────────────┘
```

### 3a. SSH-Schlüssel erzeugen

> 💻 **Auf deinem Rechner** (im Ordner `homelab-tutorial`)

```bash
ssh-keygen -t ed25519 -N "" -C "restic-photos" -f ./restic-photos-key
cat restic-photos-key.pub
```

Der Schlüssel hat **kein** Passwort (`-N ""`), denn der CronJob läuft nachts ohne dich. Deshalb bekommt er auf Proxmox
einen eigenen Benutzer, der nur Backups schreiben darf.

### 3b. Backup-Benutzer auf Proxmox

> 🟧 **Auf Proxmox** (`ssh root@pve`). Den Inhalt von `restic-photos-key.pub` einsetzen:

```bash
useradd -m -s /bin/sh restic
mkdir -p /mnt/pve/usb-backup/restic-photos
chown restic:restic /mnt/pve/usb-backup/restic-photos
install -d -m 700 -o restic -g restic /home/restic/.ssh
echo '<INHALT VON restic-photos-key.pub>' > /home/restic/.ssh/authorized_keys
chown restic:restic /home/restic/.ssh/authorized_keys
chmod 600 /home/restic/.ssh/authorized_keys
```

### 3c. Secret versiegeln

> 💻 **Auf deinem Rechner.** Ein Passwort für das restic-Repository ausdenken → **Passwortmanager!**
> Ohne dieses Passwort lässt sich das Backup nie wieder öffnen.

```bash
kubectl create secret generic restic-photos -n immich \
  --from-literal=RESTIC_PASSWORD='<RESTIC-PASSWORT>' \
  --from-file=id_ed25519=./restic-photos-key \
  --dry-run=client -o yaml \
| kubeseal --format yaml > kubernetes/secrets/immich/restic-photos.yaml
rm restic-photos-key restic-photos-key.pub
```

`--from-file` nimmt den **Inhalt einer Datei** als Wert. Danach wird der Klartext-Schlüssel gelöscht, denn er lebt jetzt nur noch verschlüsselt in Git.

### 3d. Der CronJob

[`kubernetes/apps/immich-backup/cronjob.yaml`](../kubernetes/apps/immich-backup/cronjob.yaml):

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: photos-backup
spec:
  schedule: "30 3 * * *"          # täglich um 03:30 (Minute Stunde Tag Monat Wochentag)
  timeZone: Europe/Berlin
  concurrencyPolicy: Forbid       # nie zwei Backups gleichzeitig
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: restic
              image: restic/restic:0.19.1
              args:
                - |
                  restic cat config > /dev/null 2>&1 || restic init
                  restic backup /data --tag immich --host k3s
                  restic forget --tag immich --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
                  restic check
```

| Objekt | Aufgabe |
|--------|---------|
| **CronJob** | Zeitplan: „Starte täglich um 03:30 einen Job“ |
| **Job** | „Führe diesen Pod aus, bis er **erfolgreich beendet** ist“ (anders als ein Deployment, das Pods dauerhaft laufen lässt) |
| **Pod** | macht die eigentliche Arbeit und beendet sich |

Das Skript legt beim ersten Lauf das Repository an, sichert, räumt alte Stände auf (7 tägliche, 4 wöchentliche,
12 monatliche) und prüft das Repository.

Neu ist auch das **`projected`-Volume**. Es fasst eine ConfigMap (SSH-Einstellungen) und einen Eintrag aus einem Secret
(den Schlüssel) in **einem** Ordner `/root/.ssh` zusammen, mit den strengen Dateirechten, die SSH verlangt:

```yaml
            - name: ssh
              projected:
                defaultMode: 0400
                sources:
                  - configMap:
                      name: restic-ssh-config
                  - secret:
                      name: restic-photos
                      items:
                        - key: id_ed25519
                          path: id_ed25519
```

> ⚠️ In [`kubernetes/apps/immich-backup/ssh-config`](../kubernetes/apps/immich-backup/ssh-config) steht die IP des
> Proxmox-Hosts (`192.168.178.10`). Weicht deine ab, passe sie an.

### 3e. Aktivieren und ausprobieren

```bash
cp kubernetes/katalog/immich-backup.yaml kubernetes/aktiv/
git add kubernetes/aktiv/immich-backup.yaml kubernetes/secrets/immich/restic-photos.yaml
git commit -am "Backup der Fotos mit restic"
git push
```

Nicht bis 03:30 warten: Aus dem CronJob lässt sich sofort ein Job starten:

```bash
kubectl create job -n immich --from=cronjob/photos-backup backup-test
kubectl logs -n immich -f job/backup-test
```

```
== Repository prüfen (beim ersten Mal anlegen)
created restic repository 3f2a9c1e8b at sftp:pve:/mnt/pve/usb-backup/restic-photos
== Sichern
Files:        1532 new,     0 changed,     0 unmodified
Added to the repository: 1.183 GiB (1.160 GiB stored)
snapshot 7c9f8d6b saved
== Alte Stände aufräumen
...
== Repository prüfen
no errors were found
```

```bash
kubectl delete job -n immich backup-test
```

## 4. Wiederherstellung testen ⚠️

**Ein Backup, das nie zurückgespielt wurde, ist nur eine Hoffnung.** Teste beide Backups jetzt, und danach etwa
einmal im Vierteljahr.

### Test A: Fotos aus restic

Der Test-Pod [`examples/27-backup/restore-test.yaml`](../examples/27-backup/restore-test.yaml) listet alle
Sicherungsstände und spielt einen Teil davon probeweise in den Container zurück:

```bash
kubectl apply -f examples/27-backup/restore-test.yaml
kubectl logs -n immich -f restore-test
```

```
ID        Time                 Host  Tags    Paths  Size
-----------------------------------------------------------
7c9f8d6b  2026-09-28 03:30:04  k3s   immich  /data  1.183 GiB
...
== Probe-Wiederherstellung nach /tmp/restore
Summary: Restored 1210 files/dirs (1.021 GiB) in 0:41
1.0G    /tmp/restore
```

```bash
kubectl delete -f examples/27-backup/restore-test.yaml
```

### Test B: die ganze VM aus dem Proxmox-Backup

Wir stellen das Backup als **zweite VM** wieder her, ohne Netzwerk und ohne Grafikkarte, damit sie der echten VM
nicht in die Quere kommt:

1. **usb-backup → Backups** → neueste Sicherung → **Wiederherstellen**
   - **VM:** `101` (neue ID!)
   - **Speicher:** `local-lvm`
   - ☐ **Nach Wiederherstellung starten**
2. Bei **VM 101 → Hardware**:
   - **Netzwerkgerät** → Bearbeiten → ☑ **Getrennt** (Disconnect)
   - **PCI-Gerät** (Grafikkarte) → **Entfernen**. Die gehört VM 100.
   - **scsi1** (Datenplatte) wurde nicht gesichert und fehlt, das ist korrekt.
3. **VM 101 starten** → **Konsole** → als `homelab` anmelden:

   ```bash
   sudo ls /var/lib/rancher/k3s/storage/
   ```

   Du siehst alle PVC-Ordner (Jellyfin, Vaultwarden, Paperless …) mit den Daten von letzter Nacht. ✅
4. VM 101 **stoppen** und **löschen** (**Mehr → Entfernen**, ☑ *Unreferenzierte Disks löschen*).

> 💡 **Platz beachten:** Die Kopie belegt kurzzeitig Platz in `local-lvm`. Lösch sie direkt nach dem Test.

## 5. Der Ernstfall: Notfallplan

Schreib dir diesen Plan zu den Passwörtern (bzw. drucke ihn aus):

| Was ist kaputt? | Vorgehen |
|-----------------|----------|
| **Eine App** spinnt | Argo CD → App → **Sync**, sonst Pod löschen. Notfalls Proxmox-Snapshot |
| **Die VM** ist kaputt (Update verpfuscht …) | VM aus dem letzten Proxmox-Backup wiederherstellen (wie Test B, aber mit ID 100, Netzwerk und GPU). Die Datenplatte (`backup=0`) ist nicht im Backup. Erscheint sie danach unter **Hardware** als *Unbenutzte Disk*, per Doppelklick wieder als `scsi1` anhängen (fehlt sie dort: auf Proxmox `qm rescan` ausführen) |
| **Die Festplatte** ist kaputt | 1. Neue Platte, Proxmox neu installieren (Kapitel 02–03) · 2. USB-Platte anschließen, unter **Disks → Directory** *nicht neu formatieren*, sondern in `/etc/fstab` einbinden und als Storage hinzufügen · 3. VM 100 aus dem Backup wiederherstellen · 4. Neue Datenplatte anlegen (Kapitel 04, Schritt 3/8) · 5. Fotos mit restic zurückspielen · 6. GPU wieder durchreichen (Kapitel 15) · 7. Filme neu beschaffen |

**Ohne diese Dinge geht nichts** (alle im Passwortmanager!): Proxmox-root-Passwort · VM-Passwort · **restic-Passwort** ·
**Sealed-Secrets-Schlüssel** (Kapitel 14) · Tailscale- und GitHub-Zugang.

## 6. Ausblick: die „1“ außer Haus

Brennt die Wohnung, sind PC **und** USB-Platte weg. Für die dritte Kopie außer Haus gibt es mehrere Wege:

- **Zweite USB-Platte** im Wechsel, eine davon z. B. bei Familie oder im Büro lagern.
- **restic in die Cloud:** restic kann direkt zu S3-kompatiblen Speichern (z. B. Backblaze B2, Hetzner Storage Box)
  sichern. Dafür einfach einen zweiten CronJob mit anderem `RESTIC_REPOSITORY`. Die Daten sind verschlüsselt, der
  Anbieter kann sie nicht lesen.
- **Proxmox Backup Server** (kostenlos): Er speichert inkrementell und dedupliziert und kann sich auf einen zweiten
  Server außer Haus synchronisieren. Ein gutes Projekt für später.

## ✅ Checkpoint

- [ ] Storage `usb-backup` existiert, der Backup-Job läuft täglich um 02:30.
- [ ] Mindestens ein erfolgreiches Proxmox-Backup liegt auf der USB-Platte.
- [ ] Der Test-Job `backup-test` hat die Fotos gesichert, `restic check` meldet keine Fehler.
- [ ] Test A: restic konnte Dateien wiederherstellen.
- [ ] Test B: Die wiederhergestellte VM 101 enthielt deine Daten und ist wieder gelöscht.
- [ ] restic-Passwort und Notfallplan liegen im Passwortmanager.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Proxmox-Backup: `unable to activate storage 'usb-backup'` | USB-Platte nicht angeschlossen oder nicht eingebunden → **pve → Disks** |
| Backup im Modus *Snapshot* schlägt fehl | Modus testweise auf **Stopp** stellen (VM fährt dafür kurz herunter) |
| restic: `ssh: connect to host … Connection refused / timed out` | IP in `ssh-config` richtig? Aus der VM `nc -zv 192.168.178.10 22` testen |
| restic: `Permission denied (publickey)` | Öffentlicher Schlüssel in `/home/restic/.ssh/authorized_keys`? Rechte `700` bzw. `600`, Besitzer `restic`? |
| restic: `Bad owner or permissions on /root/.ssh/config` | `defaultMode: 0400` im Manifest prüfen |
| restic: `wrong password or no key found` | Anderes Passwort als beim `init`. Das ursprüngliche Passwort ist nötig |
| Job-Pod `Pending` | Vermutlich hängt er am PVC `immich-library`. Läuft Immich? `kubectl describe pod -n immich -l app=photos-backup` |

## 🎓 Was du gelernt hast

- **Snapshots** schützen vor Fehlern, **Backups** vor Hardware-Ausfall. Die **3-2-1-Regel** gibt die Richtung vor.
- Proxmox sichert die ganze VM, Platten mit `backup=0` werden ausgelassen.
- Ein **CronJob** startet **Jobs** nach Zeitplan. Ein Job läuft bis zum Erfolg und endet dann.
- **restic** sichert verschlüsselt, inkrementell und dedupliziert.
- Ein **`projected`-Volume** kombiniert ConfigMaps und Secrets in einem Ordner.
- Nur ein **getestetes** Backup ist ein Backup.

---

⬅️ **Zurück:** [26 – Uptime Kuma](26-uptime-kuma.md) · ➡️ **Weiter:** [28 – Updates & Wartung](28-updates-wartung.md)
