# 02 – Proxmox installieren

> **Was du am Ende hast:** Proxmox VE läuft auf dem Desktop-PC, ist aktuell und über den Browser erreichbar.
> Außerdem weißt du, ob sich die Grafikkarte später an eine VM durchreichen lässt.
>
> ⏱️ **Zeit:** ca. 1 Stunde
>
> 🧠 **Neue Begriffe:** [Hypervisor](glossar.md#homelab--infrastruktur), [Proxmox VE](glossar.md#homelab--infrastruktur),
> [LVM-Thin](glossar.md#homelab--infrastruktur), [IOMMU](glossar.md#homelab--infrastruktur)

---

## Was ist Proxmox?

Proxmox VE ist ein **Hypervisor**: ein Betriebssystem, dessen Aufgabe es ist, virtuelle Maschinen (VMs) zu betreiben.
Du installierst es einmal auf dem Desktop-PC und bedienst es danach nur noch über den Browser.
Monitor und Tastatur kannst du nach diesem Kapitel abstecken.

## 1. Installations-Stick erstellen

> 💻 **Auf deinem Rechner**

1. Lade das aktuelle **Proxmox VE ISO Installer**-Image herunter: <https://www.proxmox.com/de/downloads>
   (Version 9.x oder neuer).
2. Stecke den USB-Stick ein und finde seinen Gerätenamen heraus:

   ```bash
   lsblk -d -o NAME,SIZE,MODEL,TRAN
   ```

   Beispielausgabe:

   ```
   NAME      SIZE MODEL              TRAN
   sda      14.6G Cruzer Blade       usb
   nvme0n1 476.9G Samsung SSD 970    nvme
   ```

   Der Stick ist das Gerät mit `TRAN` = `usb` und passender Größe, hier `sda`.

3. Image auf den Stick schreiben. **Ersetze `sdX` durch den Namen deines Sticks.**

   ```bash
   sudo dd if=proxmox-ve_*.iso of=/dev/sdX bs=4M status=progress conv=fsync
   ```

> ⚠️ **Doppelt prüfen!** `dd` fragt nicht nach. Wählst du die falsche Festplatte, ist sie gelöscht.
> Im Zweifel: Stick abziehen, `lsblk` ausführen, Stick einstecken, `lsblk` ausführen und vergleichen. Das Gerät, das neu dazugekommen ist, ist der Stick.

## 2. Vom Stick starten

1. Stick in den Desktop-PC stecken, Netzwerkkabel anschließen, einschalten.
2. Sofort mehrmals die Taste für das **Boot-Menü** drücken:
   ASUS `F8` · MSI `F11` · Gigabyte `F12` · ASRock `F11`
3. Den Eintrag mit **UEFI:** und dem Namen des Sticks wählen.

## 3. Installation

Wähle **Install Proxmox VE (Graphical)** und akzeptiere die Lizenz.

### Zielfestplatte

Wähle bei **Target Harddisk** die 500-GB-Festplatte und klicke auf **Options**:

| Feld | Wert | Erklärung |
|------|------|-----------|
| Filesystem | `ext4` | Einfach und robust, ideal für eine einzelne Festplatte |
| hdsize | *(unverändert)* | ganze Platte nutzen |
| swapsize | `4` | Auslagerungsspeicher für Proxmox selbst |
| maxroot | `40` | Platz für Proxmox und ISO-Dateien |
| minfree | `8` | Reserve im Volume-Manager |
| maxvz | *(leer)* | der gesamte Rest wird Speicher für VM-Festplatten |

> 💡 **Was passiert hier?** Proxmox teilt die Platte in zwei Bereiche:
> - **`local`** (ca. 40 GB): Proxmox selbst, ISO-Dateien, Vorlagen
> - **`local-lvm`** (ca. 410 GB): Speicher für die Festplatten deiner VMs (als LVM-Thin)

### Ort und Zeitzone

| Feld | Wert |
|------|------|
| Country | Germany |
| Time zone | Europe/Berlin |
| Keyboard Layout | German |

### Passwort und E-Mail

- **Password:** ein starkes Passwort für den Benutzer `root` → in den Passwortmanager!
- **Email:** deine E-Mail-Adresse, Proxmox schickt dorthin Warnungen (z. B. fehlgeschlagene Backups).

### Netzwerk

Hier kommen die Werte von deinem [Spickzettel](01-voraussetzungen.md#spickzettel-ausfüllen) zum Einsatz:

| Feld | Beispielwert |
|------|--------------|
| Management Interface | die Netzwerkkarte mit Kabel (z. B. `enp5s0`) |
| Hostname (FQDN) | `pve.home.arpa` |
| IP Address (CIDR) | `192.168.178.10/24` |
| Gateway | `192.168.178.1` |
| DNS Server | `192.168.178.1` |

> 💡 `home.arpa` ist die offiziell für Heimnetze reservierte Domain. Sie kann nie mit echten Internet-Adressen kollidieren.

### Los geht's

Prüfe die Zusammenfassung, lass **Automatically reboot after successful installation** angehakt und klicke **Install**.
Nach ein paar Minuten startet der PC neu. **Zieh jetzt den USB-Stick ab.**

Auf dem Monitor erscheint danach:

```
Welcome to the Proxmox Virtual Environment. Please use your web browser to
configure this server - connect to:

  https://192.168.178.10:8006/
```

## 4. Die Weboberfläche

> 💻 **Auf deinem Rechner**

1. Öffne im Browser `https://192.168.178.10:8006`.
2. Der Browser warnt vor einem unsicheren Zertifikat. Das ist normal: Proxmox hat sich selbst ein Zertifikat
   ausgestellt, das dein Browser noch nicht kennt. Klicke auf **Erweitert → Risiko akzeptieren und fortfahren**.
   (In Kapitel 03 bekommst du über Tailscale ein echtes Zertifikat.)
3. Anmelden:
   - **User name:** `root`
   - **Realm:** `Linux PAM standard authentication`
   - **Language:** Deutsch (wenn du magst)
4. Es erscheint **„No valid subscription“**. Klicke auf **OK**.

> 💡 **Kostet Proxmox Geld?** Nein. Proxmox ist komplett kostenlos. Die Subscription ist ein optionaler
> Support-Vertrag für Firmen. Der Hinweis erscheint bei jedem Login, du kannst ihn einfach wegklicken.

### Kurze Orientierung

```
Rechenzentrum (Datacenter)
└── pve                ← dein Server (Node)
    ├── local          ← Speicher für ISOs und Backups
    └── local-lvm      ← Speicher für VM-Festplatten
```

Klicke links auf **pve** und dann auf **Übersicht**. Dort siehst du CPU, RAM und Festplattenauslastung.

## 5. Paketquellen einstellen

Proxmox ist so voreingestellt, dass Updates aus dem **Enterprise**-Repository kommen, das nur mit Subscription
funktioniert. Wir stellen auf das kostenlose **No-Subscription**-Repository um.

1. Links **pve** → **Updates** → **Repositories**
2. Markiere den Eintrag mit `pve-enterprise` → **Disable**
3. Markiere den Eintrag mit `ceph` und `enterprise` → **Disable**
4. Klicke **Add** → wähle **No-Subscription** → **Add**

Die Warnung *„The no-subscription repository is not recommended for production use“* kannst du im Homelab ignorieren.

## 6. Updates installieren

1. Links **pve** → **Updates** → **Refresh**. Warte, bis `TASK OK` erscheint, und schließe das Fenster.
2. Klicke **Upgrade**. Es öffnet sich eine Konsole. Bestätige mit `Y` und `Enter`.
3. Wurde ein neuer Kernel installiert, starte neu: oben rechts **Neustart** (Reboot).

> 💡 **Wichtig für später:** Proxmox wird immer mit `apt full-upgrade` (bzw. dem Upgrade-Knopf) aktualisiert,
> niemals nur mit `apt upgrade`. Sonst können Pakete in einem halb aktualisierten Zustand hängen bleiben.

## 7. SSH-Zugang zu Proxmox

> 💻 **Auf deinem Rechner**

Damit du Befehle auf Proxmox auch aus deinem eigenen Terminal ausführen kannst:

```bash
ssh-copy-id root@192.168.178.10
ssh root@192.168.178.10
```

Beim ersten Mal fragt SSH, ob du dem Server vertraust. Antworte mit `yes`. Danach meldet sich Proxmox:

```
root@pve:~#
```

> 💡 Alternativ gibt es in der Weboberfläche unter **pve** → **>_ Shell** eine Konsole direkt im Browser.

## 8. Vorab-Check: Lässt sich die Grafikkarte durchreichen?

Die RTX 2070 Super soll in Kapitel 15 an die Kubernetes-VM gehen. Damit das klappt, muss **IOMMU** aktiv sein und die
Grafikkarte in einer **eigenen IOMMU-Gruppe** stecken. Wir prüfen das jetzt. Ist etwas nicht in Ordnung, erfährst du es,
bevor du Stunden investiert hast.

> 🟧 **Auf Proxmox**

### IOMMU aktiv?

```bash
dmesg | grep -i -e "AMD-Vi" -e "iommu"
```

Erwartete Ausgabe (Auszug):

```
pci 0000:00:00.2: AMD-Vi: IOMMU performance counters supported
AMD-Vi: Interrupt remapping enabled
iommu: Default domain type: Translated
```

Wichtig ist eine Zeile mit **AMD-Vi**. Fehlt sie, ist IOMMU im BIOS nicht aktiviert (siehe [Kapitel 01](01-voraussetzungen.md#5-bios-einstellen)).

### IOMMU-Gruppen anzeigen

```bash
for d in /sys/kernel/iommu_groups/*/devices/*; do
  g=${d#/sys/kernel/iommu_groups/}; g=${g%%/*}
  printf 'Gruppe %2s: %s\n' "$g" "$(lspci -nns "${d##*/}")"
done | sort -k2,2n
```

Suche in der Ausgabe nach **NVIDIA**. Bei einer RTX 2070 Super sieht eine **gute** Gruppe etwa so aus:

```
Gruppe 15: 0a:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU104 [GeForce RTX 2070 SUPER] [10de:1e84] (rev a1)
Gruppe 15: 0a:00.1 Audio device [0403]: NVIDIA Corporation TU104 HD Audio Controller [10de:10f8] (rev a1)
Gruppe 15: 0a:00.2 USB controller [0c03]: NVIDIA Corporation TU104 USB 3.1 Host Controller [10de:1ad8] (rev a1)
Gruppe 15: 0a:00.3 Serial bus controller [0c80]: NVIDIA Corporation TU104 USB Type-C UCSI Controller [10de:1ad9] (rev a1)
```

Die Grafikkarte hat vier Teile (Bild, Ton, USB, USB-C), und **in ihrer Gruppe steht nichts anderes**. 🎉

| Ergebnis | Bedeutung |
|----------|-----------|
| NVIDIA-Geräte allein in ihrer Gruppe | Perfekt, Kapitel 15 wird problemlos |
| In der Gruppe stehen zusätzlich andere Geräte (z. B. SATA, Netzwerk) | Grafikkarte in den **obersten** PCIe-Slot stecken (der hängt direkt an der CPU). Hilft das nicht, gibt es in Kapitel 15 einen Workaround |
| Die Schleife gibt gar nichts aus | IOMMU ist nicht aktiv → BIOS prüfen |

Notiere dir die Adresse der Grafikkarte (im Beispiel `0a:00`) auf dem Spickzettel.

## ✅ Checkpoint

- [ ] `https://192.168.178.10:8006` öffnet die Proxmox-Weboberfläche, und du kannst dich als `root` anmelden.
- [ ] Unter **pve → Updates → Repositories** ist nur noch `pve-no-subscription` aktiv (keine Warnung in Rot).
- [ ] Unter **pve → Updates** stehen nach **Refresh** keine offenen Updates mehr.
- [ ] `ssh root@192.168.178.10` funktioniert ohne Passwort.
- [ ] Unter **Rechenzentrum → Storage** gibt es `local` und `local-lvm`.
- [ ] Die IOMMU-Prüfung ist gemacht und das Ergebnis notiert.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| PC startet nicht vom Stick | Im Boot-Menü den Eintrag mit **UEFI:** wählen. Hilft das nicht, im BIOS **Secure Boot** deaktivieren |
| Installer bleibt mit schwarzem Bild hängen | Im Installer-Menü **Advanced Options → Install Proxmox VE (Terminal UI)** wählen |
| Weboberfläche nicht erreichbar | Richtige IP (`https://`, Port `8006`)? Netzwerkkabel steckt? Am Monitor mit `ip a` die IP prüfen |
| `Upgrade` meldet `401 Unauthorized` | Das Enterprise-Repository ist noch aktiv → Schritt 5 wiederholen |
| Falsche IP bei der Installation angegeben | In der Weboberfläche **pve → System → Netzwerk → vmbr0 → Bearbeiten**, danach **Konfiguration anwenden** |

## 🎓 Was du gelernt hast

- Proxmox ist ein Hypervisor und wird komplett über den Browser bedient.
- Die Festplatte ist aufgeteilt in `local` (System, ISOs) und `local-lvm` (VM-Festplatten).
- Im Homelab nutzt man das kostenlose **No-Subscription**-Repository.
- IOMMU-Gruppen entscheiden darüber, ob Hardware an eine VM durchgereicht werden kann.

---

⬅️ **Zurück:** [01 – Voraussetzungen](01-voraussetzungen.md) · ➡️ **Weiter:** [03 – Tailscale auf Proxmox](03-tailscale-proxmox.md)
