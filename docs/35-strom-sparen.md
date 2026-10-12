# 35 – Strom sparen

> **Was du am Ende hast:** Du kennst den Stromverbrauch deines Homelabs in Watt und Euro. BIOS, Proxmox, Grafikkarte und
> HDD sind auf Sparen eingestellt, und du weißt, ob sich eine Nachtabschaltung für dich lohnt.
>
> ⏱️ **Zeit:** ca. 1–2 Stunden, verteilt auf ein paar Tage (Messen braucht Geduld)
>
> 🧠 **Neue Begriffe:** [C-States](glossar.md#homelab--infrastruktur), [CPU-Governor](glossar.md#homelab--infrastruktur),
> [ASPM](glossar.md#homelab--infrastruktur), Idle-Verbrauch, Spin-down, `rtcwake`

---

> 🧪 **Noch nicht auf echter Hardware ausprobiert.** Die Befehle sind sorgfältig zusammengestellt, aber die Ersparnis
> hängt stark von Mainboard, Netzteil und BIOS ab. Miss deshalb **vor und nach jedem Schritt** (Abschnitt 1) und
> mach nur weiter, was bei dir wirklich etwas bringt.

## Warum das Ganze?

Ein Homelab läuft rund um die Uhr. Deshalb zählt fast nur der **Idle-Verbrauch**, also was der PC zieht, wenn gerade
niemand einen Film schaut oder Fotos hochlädt. Das ist bei uns der allergrößte Teil des Tages.

Eine Faustregel, die du dir merken kannst:

> **1 Watt rund um die Uhr ≈ 8,8 kWh im Jahr ≈ 3 € im Jahr** (bei ca. 0,35 €/kWh)

Ein alter Desktop-PC mit großer Grafikkarte liegt im Leerlauf grob bei 40–80 W. Schon 15 W weniger sind also rund
45 € im Jahr.

Wo lohnt es sich anzusetzen? Von unten nach oben:

| Ebene | Was | Lohnt sich |
|-------|-----|------------|
| **Hardware & BIOS** | Stromsparzustände der CPU, PCIe-Stromsparen, Unbenutztes abschalten | ⭐⭐⭐ meist am meisten |
| **Proxmox** | CPU-Takt nach Bedarf, `powertop`, HDD schlafen legen | ⭐⭐ |
| **Grafikkarte** | Im Leerlauf wirklich in den Sparmodus | ⭐⭐ |
| **Ganzer PC nachts aus** | `rtcwake` | ⭐⭐⭐ wenn du nachts nichts brauchst |
| **Kubernetes & Apps** | Weniger Hintergrundarbeit | ⭐ eher wenig |

Die Reihenfolge ist kein Zufall: Kubernetes kann nur verteilen, was die Hardware hergibt. Ein Pod, der nichts tut,
verbraucht praktisch keinen Strom. Ein Mainboard, das seine Stromsparzustände nicht nutzt, dagegen schon.

## 1. Messen: ohne Zahl kein Sparen

### Ein Messgerät besorgen

Am einfachsten ist ein **Zwischenstecker-Messgerät** (gibt es für ca. 10–20 €) oder eine **smarte Steckdose**. Hast du
eine FRITZ!Box, passt eine **FRITZ!DECT 200/210**: Sie zeigt den Verbrauch direkt in der FRITZ!Box-Oberfläche unter
**Smart Home** an, inklusive Verlauf.

Steck den Homelab-PC (und nur ihn) daran.

### Den Ausgangswert notieren

Warte, bis alle Apps hochgefahren sind und niemand etwas tut (z. B. abends, kein Film läuft). Lies dann einige Minuten
lang ab und notiere den typischen Wert. Leg dir eine kleine Tabelle an, z. B. als Notiz:

| Datum | Änderung | Idle-Verbrauch |
|-------|----------|----------------|
| … | Ausgangswert | … W |
| … | BIOS: C-States, ASPM | … W |
| … | Proxmox: Governor | … W |

> 💡 Ändere immer nur **eine** Sache auf einmal und miss danach. Sonst weißt du nicht, was geholfen hat und was nicht.

### Was die Software selbst verrät

> 🟧 **Auf Proxmox** (`ssh root@pve`)

```bash
apt install -y powertop
powertop
```

`powertop` zeigt im Reiter **Idle stats**, wie viel Zeit die CPU-Kerne in den tiefen Schlafzuständen (**C-States**,
z. B. `C6`) verbringen. Je höher dort der Prozentwert, desto besser. Mit `Tab` wechselst du die Reiter, mit `q`
beendest du. Den Gesamtverbrauch in Watt kann `powertop` auf einem Desktop meist nicht messen, dafür brauchst du das
Messgerät.

> 🐧 **In der VM** (`ssh homelab@k3s`)

```bash
nvidia-smi --query-gpu=pstate,power.draw,persistence_mode --format=csv
```

```
pstate, power.draw [W], persistence_mode
P8, 9.12 W, Enabled
```

`P8` ist der tiefste Sparmodus der Grafikkarte. Mehr dazu in Abschnitt 4.

## 2. BIOS: die größten Hebel

> 🧪 Noch nicht auf echter Hardware ausprobiert. Die Namen unterscheiden sich je nach Mainboard-Hersteller.

Ins BIOS kommst du wie in [Kapitel 01](01-voraussetzungen.md#5-bios-einstellen). Such nach diesen Einstellungen:

| Einstellung | Wert | Wofür | Typischer Ort |
|-------------|------|-------|---------------|
| **Global C-State Control** | `Enabled` | Kerne dürfen in tiefe Schlafzustände | Advanced → AMD CBS → CPU Common Options |
| **Power Supply Idle Control** | `Low Current Idle` | erlaubt die tiefsten Zustände (`Typical Current Idle` ist ein Notnagel für alte Netzteile) | Advanced → AMD CBS → CPU Common Options |
| **PCIe ASPM** | `Enabled` bzw. `L1` / `L0sL1` | PCIe-Geräte (Grafikkarte, Netzwerk, NVMe) sparen im Leerlauf | Advanced → Onboard Devices bzw. PCI Subsystem |
| **Onboard-Audio, RGB-Beleuchtung, WLAN/Bluetooth, unbenutzte SATA-Controller** | `Disabled` | Was ausgeschaltet ist, verbraucht nichts | Advanced → Onboard Devices |
| **Precision Boost Overdrive (PBO)** | `Disabled` | Übertaktung braucht ein Server nicht | Advanced → AMD Overclocking |
| **Lüfterkurven** | leise Kurve | Lüfter laufen im Leerlauf langsamer | Hardware Monitor / Q-Fan / Smart Fan |

### Beispiel: MSI B450M PRO-VDH PLUS

> 🧪 Die Menüpfade sind nicht am echten Board geprüft und können sich je nach BIOS-Version etwas unterscheiden.

Erst mit `F7` in den **Advanced Mode** wechseln. Findest du etwas nicht, hilft die **Suche** oben im BIOS (Lupe bzw.
`Strg` + `F`): einfach den Namen der Einstellung eintippen.

| Einstellung | Pfad im MSI-BIOS | Wert |
|-------------|------------------|------|
| Global C-State Control | **OC → Advanced CPU Configuration → Global C-state Control** | `Enabled` |
| Cool'n'Quiet | **OC → Advanced CPU Configuration → AMD Cool'n'Quiet** | `Enabled` |
| Power Supply Idle Control | **Settings → Advanced → AMD CBS → Zen Common Options → Power Supply Idle Control** | `Low Current Idle` |
| PCIe ASPM | Suche nach `ASPM`. Meist unter **Settings → Advanced → PCI Subsystem Settings** oder in **AMD CBS → NBIO Common Options** | `Enabled` / `L1` |
| Onboard-Audio | **Settings → Advanced → Integrated Peripherals → HD Audio Controller** | `Disabled` |
| PBO / ECO Mode | **OC → AMD Overclocking** (mit Warnhinweis bestätigen) **→ Precision Boost Overdrive** bzw. **ECO Mode** | `Disabled` bzw. optional `45W` |
| Lüfter | **Hardware Monitor** → Lüfter wählen → **Smart Fan Mode** | leise Kurve |
| ErP (für die Nachtruhe, Abschnitt 6) | **Settings → Advanced → Power Management Setup → ErP Ready** | `Disabled` |
| Wecken per Uhr / Netzwerk (Abschnitt 6) | **Settings → Advanced → Wake Up Event Setup → Resume By RTC Alarm** bzw. **Resume By PCI-E Device** | PCI-E: `Enabled`. RTC: erst `Disabled` lassen, `rtcwake` stellt den Wecker selbst. Nur wenn der PC nicht aufwacht, `Enabled` probieren |

`SVM Mode` liegt übrigens ebenfalls unter **OC → Advanced CPU Configuration**, `IOMMU` unter **AMD CBS → NBIO Common
Options**. Beide bleiben auf `Enabled`.

Optional, für Fortgeschrittene: Viele Ryzen-Mainboards haben einen **ECO Mode** (unter *AMD Overclocking*), der die CPU
z. B. auf 45 W statt 65 W begrenzt. Das senkt vor allem die **Spitzen** (beim Transkodieren ohne GPU oder beim
Immich-Import), kaum den Leerlauf. Für ein Homelab ist der Leistungsverlust meist nicht spürbar.

> ⚠️ **Nicht anfassen:** `SVM`, `IOMMU` und `Restore on AC Power Loss` aus Kapitel 01 bleiben, wie sie sind. Ohne sie
> laufen keine VMs mehr bzw. die Grafikkarte lässt sich nicht mehr durchreichen.

Nach dem Speichern (`F10`): Startet alles wie gewohnt? (`kubectl get pods -A`) Dann den Verbrauch neu messen.

### Prüfen, ob ASPM wirklich aktiv ist

> 🟧 **Auf Proxmox**

```bash
lspci -vv 2>/dev/null | grep -E "^[0-9a-f]{2}:|LnkCtl:"
```

Unter jedem Gerät steht in der Zeile `LnkCtl:` `ASPM L1 Enabled` (gut) oder `ASPM Disabled`. Manche Geräte können es nicht, das ist
normal. Steht überall `Disabled`, ist ASPM im BIOS noch aus.

## 3. Proxmox: Takt nach Bedarf

> 🧪 Noch nicht auf echter Hardware ausprobiert.

### Der CPU-Governor

Der **Governor** entscheidet, wie hoch die CPU taktet. Proxmox stellt ihn ab Werk auf `performance`: immer volle Kraft,
auch wenn nichts zu tun ist. Für einen Server, der meistens wartet, ist das verschenkter Strom.

> 🟧 **Auf Proxmox**

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
```

Was du wählst, hängt vom Treiber in der ersten Zeile ab:

| Treiber | Governor | Bedeutung |
|---------|----------|-----------|
| `acpi-cpufreq` oder `amd-pstate` | `schedutil` | Der Linux-Kernel regelt den Takt nach der aktuellen Last |
| `amd-pstate-epp` | `powersave` | Die CPU regelt selbst. Der Name täuscht: Bei Last taktet sie trotzdem hoch |

Ausprobieren (gilt bis zum nächsten Neustart, `schedutil` ggf. durch `powersave` ersetzen):

```bash
apt install -y linux-cpupower
cpupower frequency-set -g schedutil
```

Bringt es etwas? Dann dauerhaft machen, mit einem kleinen systemd-Dienst:

```bash
cat > /etc/systemd/system/cpu-governor.service <<'EOF'
[Unit]
Description=CPU-Governor auf Strom sparen stellen (Kapitel 35)

[Service]
Type=oneshot
ExecStart=/usr/bin/cpupower frequency-set -g schedutil

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now cpu-governor.service
```

> 💡 Jellyfin transkodiert auf der Grafikkarte (Kapitel 19), die CPU hat dabei wenig zu tun. Du solltest beim Schauen
> also keinen Unterschied merken.

### powertop --auto-tune

`powertop` kann viele kleine Stromspar-Schalter auf einmal umlegen (USB, SATA, Audio …):

```bash
powertop --auto-tune
```

Danach eine Weile beobachten: Funktioniert die Netzwerkverbindung stabil? Reagiert eine angeschlossene USB-Tastatur noch?
Wenn ja und der Verbrauch sinkt, dauerhaft machen:

```bash
cat > /etc/systemd/system/powertop.service <<'EOF'
[Unit]
Description=powertop --auto-tune (Kapitel 35)

[Service]
Type=oneshot
ExecStart=/usr/sbin/powertop --auto-tune

[Install]
WantedBy=multi-user.target
EOF
systemctl enable powertop.service
```

> ⚠️ Gibt es Probleme (z. B. Netzwerk bricht ab, USB-Backup-Platte aus Kapitel 29 wird nicht erkannt): Dienst wieder
> abschalten mit `systemctl disable powertop.service` und neu starten.

## 4. Die Grafikkarte im Leerlauf

> 🧪 Noch nicht auf echter Hardware ausprobiert.

Die RTX 2070 Super kann im Leerlauf mit unter 10 W auskommen (Zustand `P8`), oder dauerhaft deutlich mehr ziehen.
Entscheidend ist, dass der **NVIDIA-Treiber in der VM** sie verwaltet.

### Persistence Mode einschalten

Ohne **Persistence Mode** gibt der Treiber die Karte frei, sobald kein Programm sie benutzt, und muss sie beim nächsten
Mal neu einrichten. Mit ihm bleibt der Treiber dran und hält die Karte im Sparmodus.

> 🐧 **In der VM**

```bash
nvidia-smi --query-gpu=persistence_mode --format=csv,noheader
```

Steht dort `Disabled`:

```bash
sudo systemctl enable --now nvidia-persistenced
sudo nvidia-smi -pm 1
```

Danach ein paar Minuten warten und erneut prüfen. Erwartet: `Enabled`, `P8`, eine einstellige oder niedrige zweistellige
Wattzahl.

### Die Falle: VM aus, Grafikkarte an

Solange die VM `k3s` läuft, kümmert sich ihr Treiber um die Karte. **Ist die VM aus, gehört die Karte dem
Platzhalter-Treiber VFIO** (Kapitel 18), und der kann sie nicht schlafen legen. Sie läuft dann oft mit deutlich mehr
Verbrauch, manchmal auch mit hörbaren Lüftern.

Für dich heißt das: Fährst du die VM für Wartung herunter (Kapitel 30), dann nicht tagelang. Und falls du die Karte gar
nicht mehr brauchst, spart Ausbauen am meisten.

## 5. Die HDD schlafen legen (Experiment)

> 🧪 Noch nicht auf echter Hardware ausprobiert, und gut möglich, dass es in diesem Setup nicht klappt.

Eine laufende 3,5"-HDD braucht grob 3–6 W, schlafend unter 1 W. Proxmox kann sie nach einer Wartezeit anhalten
(**Spin-down**). Der Haken: Jeder Zugriff weckt sie wieder, und die Datenplatte `/data` (Kapitel 32) wird von mehreren
Apps genutzt. Nextcloud prüft z. B. regelmäßig seinen Datenordner, Jellyfin und Immich schauen nach neuen Dateien.

Probier es aus und schau, ob sie überhaupt zur Ruhe kommt:

> 🟧 **Auf Proxmox**

```bash
apt install -y hdparm
ls -l /dev/disk/by-id/ | grep -v part | grep ata-
```

Merk dir den Namen der HDD (z. B. `ata-WDC_WD10EZEX-…`). Dann:

```bash
hdparm -S 241 /dev/disk/by-id/ata-<DEINE-HDD>   # 241 = nach 30 Minuten Ruhe anhalten
```

Am nächsten Tag ein paarmal nachsehen:

```bash
hdparm -C /dev/disk/by-id/ata-<DEINE-HDD>
```

| Ausgabe | Bedeutung |
|---------|-----------|
| `drive state is: standby` | Sie schläft ✅ |
| `drive state is: active/idle` | Sie läuft gerade |

Schläft sie nie (oder wacht sie ständig auf), lass es: Ständiges Anlaufen verschleißt die Platte schneller als
Durchlaufen. Klappt es, mach die Einstellung dauerhaft, indem du in `/etc/hdparm.conf` am Ende ergänzt:

```
/dev/disk/by-id/ata-<DEINE-HDD> {
    spindown_time = 241
}
```

> 💡 Nach dem Aufwachen dauert der erste Zugriff einige Sekunden. Startet ein Film in Jellyfin also mal etwas langsamer,
> ist das der Grund.

## 6. Nachts den ganzen PC ausschalten

> 🧪 Noch nicht auf echter Hardware ausprobiert.

Der größte Hebel überhaupt: Was aus ist, verbraucht (fast) nichts. Sind es 8 Stunden pro Nacht, spart das ein Drittel
des Verbrauchs. Aber vorher ehrlich überlegen, **was dann nicht geht**:

| Dienst | Was nachts passiert |
|--------|---------------------|
| **Pi-hole** (Kapitel 15) | ⚠️ Hast du Weg **C** (Router) gewählt, hat dein **ganzes Heimnetz kein Internet**. Dann nicht abschalten oder in der FRITZ!Box einen zweiten DNS-Server eintragen |
| **Vaultwarden** | Die Apps haben eine Offline-Kopie, Passwörter ansehen geht weiter. Neue speichern erst morgens |
| **Nextcloud, Immich** | synchronisieren erst, wenn der Server wieder da ist |
| **qBittorrent & *arr** | Downloads pausieren |
| **Backup** (Kapitel 29) | Der CronJob `daten-backup` läuft um **03:30**. Verschieb ihn in `kubernetes/apps/backup/cronjob.yaml` (`schedule`) in die Wachzeit, z. B. `"30 22 * * *"`. Gleiches gilt für den Proxmox-Backup-Zeitplan |
| **Uptime Kuma** | ist selbst aus. Einen Alarm gibt es nicht, aber auch keinen Fehlalarm |

### Ausschalten und Wecken mit rtcwake

Fast jedes Mainboard hat eine eingebaute Uhr (**RTC**), die den PC zu einer bestimmten Zeit wieder einschalten kann.
`rtcwake` stellt diesen Wecker und fährt den PC herunter.

> ⚠️ Im BIOS darf **ErP** (bzw. *EuP 2013*, *Deep Sleep*) nicht aktiv sein, sonst ist das Mainboard im ausgeschalteten
> Zustand komplett stromlos und kann sich nicht selbst wecken.

Erst einmal von Hand testen, tagsüber und mit einem kurzen Wecker:

> 🟧 **Auf Proxmox**

```bash
rtcwake -m no -s 300 && shutdown -h now   # Wecker in 5 Minuten stellen, dann herunterfahren
```

`-m no` stellt nur den Wecker, `shutdown` fährt Proxmox sauber herunter (inklusive der VM, wie bei einem Neustart in
Kapitel 30). Startet der PC nach 5 Minuten von selbst und laufen danach alle Pods? Dann den Zeitplan einrichten:

```bash
cat > /etc/cron.d/nachtruhe <<'EOF'
# Kapitel 35: Um 01:00 ausschalten, um 07:00 wieder einschalten
0 1 * * * root /usr/sbin/rtcwake -m no -t "$(date +\%s -d 'today 07:00')" && /sbin/shutdown -h now
EOF
```

> 💡 In Cron-Dateien muss `%` als `\%` geschrieben werden, sonst schneidet Cron den Befehl dort ab.

**Doch mal nachts gebraucht?** Die FRITZ!Box kann den PC per **Wake on LAN** wecken: **Heimnetz → Netzwerk** → den PC
bearbeiten → **Computer starten**. Über die FRITZ!Box-App klappt das auch von unterwegs. Dafür muss im BIOS
*Wake on LAN* (oft *Power On By PCI-E*) eingeschaltet sein.

Zum Abschalten der Nachtruhe einfach `rm /etc/cron.d/nachtruhe`.

## 7. Und Kubernetes?

Ehrliche Antwort: Auf **einem** Node, der sowieso läuft, spart Kubernetes wenig. Ein Pod, der wartet, braucht praktisch
keine CPU. Apps nachts per `kubectl scale --replicas=0` schlafen zu legen bringt kaum etwas messbar. Außerdem würde
Argo CD sie mit `selfHeal` (Kapitel 11) sofort wieder auf den Stand im Git zurückdrehen.

Was hilft, ist **weniger Hintergrundarbeit**, die CPU, Grafikkarte und HDD ständig weckt:

| Wo | Was |
|----|-----|
| **Jellyfin** | **Dashboard → Geplante Aufgaben**: Bibliotheks-Scan und Trickplay/Kapitelbilder in die Nacht- bzw. Abendstunden legen statt alle paar Stunden. Bei Bibliotheken **Echtzeitüberwachung** ausschalten, die *arr-Apps melden neue Dateien ohnehin |
| **Immich** | Das Machine Learning entlädt seine Modelle nach 5 Minuten Ruhe von selbst (`MACHINE_LEARNING_MODEL_TTL`, Standard `300`). Nichts zu tun |
| **Sonarr/Radarr/Prowlarr** | RSS-Abfrage (**Settings → Indexers → RSS Sync Interval**) nicht kürzer als nötig, z. B. 60 statt 15 Minuten |
| **qBittorrent** | Seeding-Grenzen setzen (Verhältnis oder Zeit), damit fertige Torrents nicht ewig laufen |
| **Uptime Kuma** | Prüfintervall 60 Sekunden reicht für ein Homelab |
| **Prometheus** (Kapitel 33) | Läuft es nur zum Lernen, kannst du die Application wieder abschalten. Das spart RAM und ein paar Watt |

Der wichtigste Kubernetes-Beitrag zum Stromsparen ist eigentlich, dass er die Grundlage für die anderen Ebenen
geschaffen hat: Weil alles im Git beschrieben ist, startet der Cluster nach der Nachtruhe (Abschnitt 6) von selbst
wieder in genau denselben Zustand.

## ✅ Checkpoint

- [ ] Du kennst deinen Idle-Verbrauch vorher und nachher (in Watt und grob in Euro pro Jahr).
- [ ] Im BIOS sind C-States und ASPM eingeschaltet, alle Apps laufen danach (`kubectl get pods -A`).
- [ ] Der CPU-Governor ist nicht mehr `performance`, auch nach einem Neustart.
- [ ] `nvidia-smi` zeigt im Leerlauf `P8` und Persistence Mode `Enabled`.
- [ ] Du hast entschieden, ob HDD-Spin-down und Nachtruhe für dich passen, und den Backup-Zeitplan ggf. angepasst.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Nach BIOS-Änderungen startet die VM nicht mehr | `SVM`/`IOMMU` versehentlich verstellt? Kapitel 01 und 18 prüfen |
| System friert im Leerlauf ein oder startet neu | `Power Supply Idle Control` zurück auf `Typical Current Idle`. Ältere Netzteile vertragen die tiefen Zustände nicht |
| Netzwerk bricht nach `powertop --auto-tune` ab | `systemctl disable powertop.service`, neu starten |
| `cpupower: command not found` | `apt install -y linux-cpupower` |
| Grafikkarte bleibt bei `P0`/`P2` | Läuft gerade ein Transkodiervorgang? `nvidia-smi` zeigt unten die Prozesse. Sonst Persistence Mode prüfen |
| PC wacht nach `rtcwake` nicht auf | ErP/EuP im BIOS aus? Manche Mainboards brauchen zusätzlich *Wake on RTC* bzw. *Resume by Alarm* = `Enabled` |
| Nach der Nachtruhe fehlt Internet im Heimnetz | Pi-hole über den Router (Weg C)? Siehe Tabelle in Abschnitt 6 |

## 🎉 Geschafft!

Du hast in 36 Kapiteln

- einen alten PC in einen **Proxmox-Hypervisor** verwandelt,
- **Kubernetes** von Pod bis Operator verstanden und selbst betrieben,
- **Passwörter** (Vaultwarden), **Dateien** (Nextcloud) und den **DNS** deines Netzes (Pi-hole) in eigene Hände genommen,
- **Jellyfin** mit GPU-Transcoding auf den Samsung-TV gebracht,
- den ***arr-Stack** sicher hinter Proton VPN aufgebaut,
- **Fotos und Dokumente** mit Immich und Paperless dazugeholt,
- alles per **GitOps** in einem Repository beschrieben, **verschlüsselt**, **überwacht**, **gesichert** und **wartbar** gemacht,
- und zum Schluss dafür gesorgt, dass es dabei möglichst **wenig Strom** braucht.

Das ist eine Menge. Viel Spaß mit deinem Homelab! 🏠

## 🎓 Was du gelernt hast

- Bei einem Server, der rund um die Uhr läuft, zählt der **Idle-Verbrauch**. 1 W Dauerlast ≈ 3 € im Jahr.
- Erst **messen**, dann eine Sache ändern, dann wieder messen.
- Die großen Hebel liegen unten: **BIOS** (C-States, ASPM), **Proxmox** (Governor, powertop) und eine **Grafikkarte**,
  die vom Treiber in der VM schlafen gelegt wird.
- Ganz ausschalten spart am meisten, kostet aber Erreichbarkeit. Pi-hole und Backups brauchen dann eine Lösung.
- Kubernetes selbst spart auf einem Node wenig, hilft aber durch weniger Hintergrundarbeit der Apps.

---

⬅️ **Zurück:** [34 – Mehr Nodes](34-mehr-nodes.md) · 🏠 **Zum Anfang:** [00 – Einführung](00-einfuehrung.md)
