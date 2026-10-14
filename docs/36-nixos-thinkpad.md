# 36 – NixOS-Server auf dem ThinkPad

> **Was du am Ende hast:** Ein alter ThinkPad läuft als sparsamer Server mit **NixOS**. Darauf laufen
> **Vaultwarden**, **Linkwarden** und **Nextcloud**, erreichbar nur in deinem Tailnet und mit echtem HTTPS. Der ganze
> Rechner, von den Partitionen bis zu den Apps, ist in ein paar Dateien in `nixos/` beschrieben und wird mit **einem
> Befehl** installiert.
>
> ⏱️ **Zeit:** ca. 1–2 Stunden
>
> 🧠 **Neue Begriffe:** NixOS, deklarativ, Flake, `nixos-anywhere`, disko, sops/age, Generation, `tailscale serve`

---

> 🧪 **Noch nicht auf echter Hardware ausprobiert.** Die Konfiguration wird in der CI vollständig ausgewertet
> (`scripts/validate-nixos.sh`), aber noch nicht auf einem echten ThinkPad installiert. Wenn ein Schritt bei dir
> anders aussieht, schreib es dazu.

## Ein anderer Weg

Die Kapitel 02–05 haben viel **von Hand** gemacht: Proxmox installieren, die VM im Assistenten zusammenklicken, Ubuntu
installieren, `fstab` bearbeiten, k3s per Skript installieren. Jeder dieser Schritte ist einmalig. Wenn du ihn in einem
Jahr wiederholen musst, weißt du nicht mehr genau, was du damals eingegeben hast.

Dieses Kapitel ist ein **eigenständiger zweiter Weg** für einen zweiten (oder neuen) Rechner. Es baut nicht auf
Proxmox oder Kubernetes auf. Statt Befehle einzutippen, **beschreibst** du den Rechner:

| Bisher (imperativ) | Jetzt (deklarativ) |
|--------------------|--------------------|
| Im Installer Partitionen anklicken | `disko.nix` |
| `adduser`, SSH-Schlüssel kopieren, `sshd_config` bearbeiten | `configuration.nix` |
| `curl … \| sh` für Tailscale, dann `tailscale up` | `services.tailscale` + Auth-Key aus `secrets.yaml` |
| Stromspar-Befehle aus Kapitel 35 | `services.tlp.settings` |
| Apps per Kubernetes-Manifest + Argo CD | `services.vaultwarden`, `services.linkwarden`, `services.nextcloud` |
| Passwörter per `kubeseal` (Kapitel 12) | `sops` verschlüsselt sie ins Git |

**Was NixOS anders macht:** Jede Änderung baut ein komplett neues System, eine **Generation**. Die alte bleibt
erhalten. Geht etwas schief, wählst du beim Start im Menü einfach die vorige Generation. Das ersetzt die
VM-Snapshots aus den Proxmox-Kapiteln.

**Was du dafür aufgibst:** keine Proxmox-Oberfläche, kein Kubernetes, kein Argo-CD-Dashboard. Die Apps laufen direkt
als Dienste auf dem Rechner. Für drei Apps auf einem Laptop ist das einfacher und sparsamer.

### Warum ein ThinkPad?

| | Leerlauf | Pro Jahr (ca. 0,35 €/kWh) |
|---|---|---|
| ThinkPad ab ca. 2018 (T480, T14, X1 …), Deckel zu | ca. 4–8 W | ca. 15–25 € |
| Älteres ThinkPad (T430, X230 …) | ca. 8–12 W | ca. 25–35 € |
| Desktop mit großer Grafikkarte (Kapitel 01) | ca. 40–60 W | ca. 120–180 € |

Das sind Erfahrungswerte, keine Messungen. Miss selbst nach, wie in [Kapitel 35](35-strom-sparen.md) beschrieben.
Dazu kommt: Der Akku überbrückt kurze Stromausfälle wie eine kleine USV.

---

## 1. Was du brauchst

- Ein **ThinkPad** mit LAN-Anschluss (oder USB-LAN-Adapter). WLAN geht auch, ist hier aber nicht eingerichtet.
- Einen **USB-Stick** (mind. 2 GB) für den Installer.
- Auf deinem Rechner **Nix** und `nix develop` im Repository ([Kapitel 01](01-voraussetzungen.md)). Darin sind
  `nixos-anywhere`, `sops` und `age` schon enthalten.
- Dein **Tailnet** mit aktiviertem **HTTPS** (Admin-Konsole → **DNS** → **HTTPS Certificates**, Kapitel 01).

> ⚠️ Die Festplatte des ThinkPads wird **komplett gelöscht**.

### BIOS

`F1` (bei manchen Modellen `Enter` → `F1`) beim Start:

| Einstellung | Wo (je nach Modell leicht anders) | Wert |
|-------------|-----------------------------------|------|
| Secure Boot | Security → Secure Boot | `Disabled` |
| Start nach Stromausfall | Config → Power → **Power On with AC Attach** | `Enabled` (wenn vorhanden) |
| Booten von USB | Startup → Boot | USB erlaubt |

## 2. Den Server beschreiben: `settings.nix`

Die Konfiguration liegt im Repository:

```text
nixos/
├── flake.nix                       # Einstieg: welche Bausteine, welche NixOS-Version
└── thinkpad/
    ├── settings.nix                # ← nur diese Datei passt du an
    ├── configuration.nix           # Benutzer, SSH, Tailscale, Strom sparen, Updates
    ├── apps.nix                    # Vaultwarden, Linkwarden, Nextcloud, tailscale serve
    ├── disko.nix                   # Partitionen
    ├── hardware-configuration.nix  # wird bei der Installation erzeugt
    └── secrets.yaml                # legst du in Schritt 3 an (verschlüsselt)
```

> 💻 **Auf deinem Rechner** (im Ordner `homelab-tutorial`)

Öffne `nixos/thinkpad/settings.nix` und trag ein:

| Feld | Was | Woher |
|------|-----|-------|
| `tailnet` | z. B. `tail1a2b3c.ts.net` | Tailscale-Admin-Konsole → **DNS** → *Tailnet name* |
| `hardwareModule` | z. B. `lenovo-thinkpad-t480` | Liste in [nixos-hardware](https://github.com/NixOS/nixos-hardware/blob/master/flake.nix); unsicher → `lenovo-thinkpad` lassen |
| `disk` | `/dev/nvme0n1` oder `/dev/sda` | prüfst du in Schritt 4 mit `lsblk` |
| `sshKeys` | Inhalt von `~/.ssh/id_ed25519.pub` | `cat ~/.ssh/id_ed25519.pub` |

Solange der Platzhalter-Schlüssel drinsteht, bricht die Installation absichtlich mit einer Meldung ab. Ohne deinen
Schlüssel kämst du nicht mehr auf den Server, denn es gibt dort kein Passwort.

## 3. Secrets anlegen

Drei Dinge dürfen nicht im Klartext ins Git: der Tailscale-Auth-Key, das Nextcloud-Admin-Passwort und ein geheimer
Schlüssel für Linkwarden. **sops** verschlüsselt sie mit einem **age**-Schlüssel, ähnlich wie Sealed Secrets in
[Kapitel 12](12-sealed-secrets.md). Der Unterschied: Den privaten Schlüssel erzeugst du selbst und gibst ihn dem
Server bei der Installation mit.

> 💻 **Auf deinem Rechner** (in `nix develop`)

```bash
# 1. Schlüsselpaar erzeugen (einmalig)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
# → Public key: age1…   (diese Zeile brauchst du gleich)
```

> 🔐 `~/.config/sops/age/keys.txt` ist der **Generalschlüssel** für alle Secrets dieses Servers. Leg eine Kopie in
> deinen Passwortmanager, genau wie den Sealed-Secrets-Schlüssel.

Trag den öffentlichen Schlüssel (`age1…`) in `.sops.yaml` im Hauptordner des Repositorys ein, anstelle des
Platzhalters.

Jetzt den Auth-Key für Tailscale holen: Admin-Konsole → **Settings** → **Keys** → **Generate auth key**. Lass
*Reusable* aus, schalte *Pre-approved* ein (falls angezeigt) und kopiere den Schlüssel (`tskey-auth-…`). Er wird nur
bei der allerersten Anmeldung gebraucht.

```bash
# 2. Zufälligen Schlüssel für Linkwarden erzeugen und anzeigen
openssl rand -base64 32

# 3. Secrets-Datei anlegen. sops öffnet einen Editor, gespeichert wird verschlüsselt.
sops nixos/thinkpad/secrets.yaml
```

Im Editor genau diese drei Zeilen eintragen und speichern:

```yaml
tailscale-authkey: tskey-auth-…
nextcloud-admin-password: ein-langes-passwort-aus-dem-passwortmanager
linkwarden-nextauth-secret: die-ausgabe-von-openssl-rand
```

Prüf das Ergebnis: `cat nixos/thinkpad/secrets.yaml` zeigt nur noch `ENC[…]`-Werte. So darf die Datei ins Git.

```bash
# 4. Wichtig: Nix sieht nur Dateien, die Git kennt
git add .sops.yaml nixos/
```

## 4. Den Installer starten

Das ist der einzige Teil am ThinkPad selbst.

1. Lade das **Minimal ISO** von <https://nixos.org/download/#nixos-iso> und schreib es auf den USB-Stick (z. B. mit
   balenaEtcher wie in [Kapitel 02](02-proxmox-installieren.md)).
2. ThinkPad per LAN-Kabel anschließen, vom Stick starten (`F12` beim Start → USB).
3. Nach ein paar Sekunden bist du als `nixos` angemeldet.

> 🟩 **Am ThinkPad**

```bash
sudo passwd root   # vorübergehendes Passwort, nur für die Installation
ip -4 addr         # die Adresse bei "enp…" notieren, z. B. 192.168.178.50
lsblk              # die interne Platte: nvme0n1 oder sda? Muss zu "disk" in settings.nix passen
```

## 5. Installieren: ein Befehl

`nixos-anywhere` verbindet sich per SSH mit dem Installer, legt die Partitionen aus `disko.nix` an, erkennt die
Hardware und installiert das System aus `nixos/`. Dabei kopiert es deinen age-Schlüssel auf den Server, damit er die
Secrets entschlüsseln kann.

> 💻 **Auf deinem Rechner** (im Ordner `homelab-tutorial`, in `nix develop`)

```bash
# Den age-Schlüssel für den Server bereitlegen
extra=$(mktemp -d)
install -D -m 600 ~/.config/sops/age/keys.txt "$extra/var/lib/sops-nix/key.txt"

nixos-anywhere \
  --flake ./nixos#thinkpad \
  --generate-hardware-config nixos-generate-config ./nixos/thinkpad/hardware-configuration.nix \
  --extra-files "$extra" \
  --build-on remote \
  root@192.168.178.50

rm -rf "$extra"
```

Das dauert je nach Internet 10–30 Minuten. `--build-on remote` lässt den ThinkPad die Pakete selbst herunterladen, so
klappt es auch von einem Mac aus. Am Ende startet der ThinkPad neu. **USB-Stick abziehen**, dann den Deckel zuklappen.

Jetzt die Dateien sichern, die bei der Installation entstanden sind:

```bash
git add nixos/ .sops.yaml
git commit -m "ThinkPad mit NixOS installiert"
git push
```

`nixos/flake.lock` hält fest, welche Versionen genau installiert wurden, und
`nixos/thinkpad/hardware-configuration.nix` beschreibt jetzt deinen echten ThinkPad.

## 6. Der erste Blick

Nach dem Neustart meldet sich der ThinkPad mit dem Auth-Key **von selbst** im Tailnet an.

```bash
ssh homelab@thinkpad
```

> 🟩 **Auf dem ThinkPad** (per SSH)

```bash
tailscale status                  # thinkpad ist online
systemctl --failed                # sollte "0 loaded units" zeigen
tailscale serve status            # die drei Apps mit ihren Adressen
cat /sys/class/power_supply/BAT0/charge_control_end_threshold   # 80
```

## 7. Die Apps einrichten

Alle drei laufen nur auf `127.0.0.1`. Ins Tailnet bringt sie `tailscale serve`, mit einem echten Zertifikat für
`thinkpad.<tailnet>.ts.net`. Der erste Aufruf kann eine Minute dauern, weil das Zertifikat erst geholt wird.

| App | Adresse | Erste Anmeldung |
|-----|---------|-----------------|
| **Nextcloud** | `https://thinkpad.<tailnet>.ts.net` | Benutzer `admin`, Passwort aus `secrets.yaml` |
| **Vaultwarden** | `https://thinkpad.<tailnet>.ts.net:8443` | **Create account**, Master-Passwort wie in [Kapitel 13](13-vaultwarden.md) |
| **Linkwarden** | `https://thinkpad.<tailnet>.ts.net:8444` | **Sign Up**, dein Konto anlegen |

In den Bitwarden-Apps trägst du als Server-URL die Vaultwarden-Adresse **mit** `:8443` ein. Linkwarden hat eine
Browser-Erweiterung, die du ebenso auf die Adresse mit `:8444` stellst.

Warum Ports statt eigener Namen wie in Kapitel 10? Der ThinkPad ist **ein** Gerät im Tailnet und hat damit einen
Namen. Nextcloud mag es nicht, in einem Unterordner (`/nextcloud`) zu laufen, deshalb trennen wir die Apps über Ports.

## 8. Registrierung schließen: deine erste Änderung

Sobald deine Konten existieren, soll sich niemand mehr registrieren können. Das ist jetzt kein Klick in einer
Oberfläche, sondern eine Zeile in Git.

> 💻 **Auf deinem Rechner**

In `nixos/thinkpad/settings.nix`:

```nix
  allowSignups = false;
```

Ausrollen:

```bash
nixos-rebuild switch --flake ./nixos#thinkpad \
  --target-host homelab@thinkpad --build-host homelab@thinkpad --sudo
```

Auf dem Mac gibt es `nixos-rebuild` nicht. Dort klonst du das Repository einmal auf den ThinkPad und rollst von dort
aus:

```bash
ssh homelab@thinkpad
git clone https://github.com/DEIN-NAME/homelab-tutorial && cd homelab-tutorial   # nur beim ersten Mal
git pull
sudo nixos-rebuild switch --flake ./nixos#thinkpad
```

Danach committen und pushen. So läuft ab jetzt **jede** Änderung: Datei ändern → ausrollen → committen.

## 9. Rückgängig machen

Hat eine Änderung etwas kaputt gemacht?

```bash
sudo nixos-rebuild switch --rollback   # zurück zur vorigen Generation
```

Startet der ThinkPad gar nicht mehr richtig: Deckel auf, beim Start im Menü eine ältere Generation wählen. Die letzten
zehn bleiben erhalten (`configurationLimit` in `configuration.nix`).

> ⚠️ Ein Rollback setzt **Programme und Einstellungen** zurück, nicht die **Daten** der Apps. Die liegen in
> `/var/lib/` (`nextcloud`, `vaultwarden`, `linkwarden`, `postgresql`). Für sie brauchst du ein Backup wie in
> [Kapitel 29](29-backup-restore.md). Vaultwarden legt zusätzlich jede Nacht eine Kopie nach
> `/var/backup/vaultwarden`.

## 10. Optional: GitOps für den ganzen Rechner

Argo CD holt sich in Kapitel 11 den Stand der Apps aus Git. NixOS kann das für den **ganzen Rechner**: Jede Nacht um
04:00 Uhr holt der ThinkPad den Stand aus deinem Repository und baut sich danach neu.

In `settings.nix`:

```nix
  gitopsFlake = "github:DEIN-NAME/homelab-tutorial?dir=nixos";
```

Einmal ausrollen (Schritt 8), danach reicht `git push`. Damit das klappt, muss das Repository **öffentlich** sein und
`nixos/flake.lock` committet sein. Keine Sorge wegen der Secrets: In `secrets.yaml` steht nur Verschlüsseltes.

Updates der Pakete holst du so, dann wie gewohnt ausrollen oder pushen:

```bash
nix flake update --flake ./nixos
```

## Was bleibt Handarbeit?

Ganz ohne geht es nicht. Diese Schritte machst du einmal:

| Schritt | Warum nicht als Code |
|---------|----------------------|
| BIOS einstellen | Liegt außerhalb jedes Betriebssystems |
| USB-Stick, `passwd`, IP ablesen | Der Installer muss erst per SSH erreichbar sein |
| Tailscale-Auth-Key und HTTPS in der Admin-Konsole | Gehört zu deinem Tailscale-Konto, nicht zum Server |
| age-Schlüssel erzeugen und sichern | Das Geheimnis, mit dem alles andere verschlüsselt ist |
| Erste Konten in den Apps | Master-Passwörter gehören nur in deinen Kopf |

## ✅ Checkpoint

- [ ] `ssh homelab@thinkpad` funktioniert, ein Passwort wird nie gefragt.
- [ ] `systemctl --failed` zeigt keine Fehler.
- [ ] Nextcloud, Vaultwarden und Linkwarden sind per HTTPS im Tailnet erreichbar, im Heimnetz unter der LAN-IP nicht.
- [ ] `allowSignups = false` ist ausgerollt, eine neue Registrierung in Vaultwarden wird abgelehnt.
- [ ] `nixos/flake.lock`, `hardware-configuration.nix` und `secrets.yaml` sind committet.
- [ ] Der age-Schlüssel liegt in deinem Passwortmanager.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| `Trag in nixos/thinkpad/settings.nix deinen echten SSH-Schlüssel ein` | Genau das: `sshKeys` in Schritt 2 |
| `path '…/secrets.yaml' does not exist` | `git add nixos/thinkpad/secrets.yaml`. Nix sieht nur Dateien, die Git kennt |
| `nixos-anywhere`: Permission denied | `sudo passwd root` am ThinkPad vergessen? Oder falsche IP |
| ThinkPad startet nach der Installation nicht | Secure Boot im BIOS aus? `disk` in `settings.nix` = die interne Platte aus `lsblk`? |
| ThinkPad taucht nicht im Tailnet auf | Auth-Key abgelaufen oder schon benutzt: neuen erzeugen, mit `sops nixos/thinkpad/secrets.yaml` ersetzen, ausrollen |
| `tailscale-serve-apps` schlägt fehl | HTTPS in der Admin-Konsole aktiviert? `journalctl -u tailscale-serve-apps` zeigt den Grund |
| Zertifikatsfehler im Browser | Beim ersten Aufruf eine Minute warten |
| Nextcloud: "Zugriff über nicht vertrauenswürdige Domain" | Rufst du `thinkpad.<tailnet>.ts.net` auf, nicht die IP? Stimmt `tailnet` in `settings.nix`? |
| Ein Dienst startet nicht | `journalctl -u vaultwarden` (bzw. `linkwarden`, `phpfpm-nextcloud`, `nextcloud-setup`) |
| Netzwerk weg, wenn der Deckel zu ist | `journalctl -b \| grep -i lid` prüfen, `HandleLidSwitch` in `configuration.nix` |

## 🎓 Was du gelernt hast

- **Deklarativ** heißt: Du beschreibst das Ergebnis, nicht die Schritte. Der Rechner lässt sich jederzeit aus dem
  Repository neu aufbauen.
- `nixos-anywhere` + **disko** ersetzen den Installer: Partitionen, System und Apps in einem Befehl.
- **sops** verschlüsselt Secrets mit einem **age**-Schlüssel, damit sie gefahrlos im Git liegen.
- Jede Änderung ist eine **Generation**. Rollback geht per Befehl oder im Startmenü, aber die App-Daten brauchen
  trotzdem ein Backup.
- `tailscale serve` bringt lokale Dienste mit HTTPS ins Tailnet, ohne dass ein Port im Heimnetz offen ist.
- Ein ThinkPad braucht im Leerlauf nur einen Bruchteil eines Desktop-PCs und hat seine USV schon eingebaut.

---

⬅️ **Zurück:** [35 – Strom sparen](35-strom-sparen.md) · 🏠 **Zum Anfang:** [00 – Einführung](00-einfuehrung.md)
