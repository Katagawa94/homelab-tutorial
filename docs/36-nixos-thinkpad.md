# 36 – NixOS-Server auf dem ThinkPad

> **Was du am Ende hast:** Ein alter ThinkPad läuft als sparsamer Server mit **NixOS**. Darauf laufen
> **Vaultwarden**, **Linkwarden** und **Nextcloud**, jede unter ihrem eigenen Namen wie
> `https://nextcloud.<tailnet>.ts.net`, erreichbar nur in deinem Tailnet und mit echtem HTTPS. Der ganze
> Rechner, von den Partitionen bis zu den Apps, ist in ein paar Dateien in `nixos/` beschrieben und wird mit **einem
> Befehl** installiert.
>
> ⏱️ **Zeit:** ca. 1–2 Stunden
>
> 🧠 **Neue Begriffe:** NixOS, deklarativ, Flake, `nixos-anywhere`, disko, sops/age, Generation, Tailscale Services, Tags

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
  `nixos-anywhere`, `sops`, `age` und `openssl` schon enthalten.
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

## 3. Secrets und Tailscale vorbereiten

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

### Tailscale vorbereiten: Tag und Services

Jede App soll ihren eigenen Namen bekommen, z. B. `https://vaultwarden.<tailnet>.ts.net`. Das machen
**Tailscale Services** möglich: Ein Service ist ein Name mit eigener Adresse im Tailnet, und der ThinkPad meldet sich
als der Rechner, der ihn bereitstellt. Kein Reverse-Proxy, kein eigenes Zertifikat, keine eigene Domain.

Dafür sind zwei Dinge in der Tailscale-Admin-Konsole nötig, beide einmalig:

**1. Ein Tag für den Server.** Nur Geräte mit einem **Tag** dürfen Services anbieten. Ein Tag ist ein Etikett wie
`tag:server`, das zum Gerät gehört statt zu deinem Konto. Öffne **Access controls** und ergänze in der Policy-Datei
(neben den Einträgen, die schon da sind):

```json
"tagOwners": {
  "tag:server": ["autogroup:admin"]
},
"autoApprovers": {
  "services": {
    "svc:nextcloud":   ["tag:server"],
    "svc:vaultwarden": ["tag:server"],
    "svc:linkwarden":  ["tag:server"]
  }
},
```

`autoApprovers` sorgt dafür, dass du den ThinkPad nicht für jeden Service einzeln freigeben musst. Ohne den Eintrag
klickst du später unter **Services** bei jedem Service auf *Approve*.

**2. Die drei Services anlegen.** Admin-Konsole → **Services** → **Define a service**, dreimal:

| Name | Port |
|------|------|
| `nextcloud` | `tcp:443` |
| `vaultwarden` | `tcp:443` |
| `linkwarden` | `tcp:443` |

Die Namen müssen genau so heißen wie in `nixos/thinkpad/apps.nix`. Willst du später eine vierte App, legst du dort
einen Eintrag an und hier einen Service.

> 💡 Hast du die Standard-Policy nie geändert, dürfen alle deine Geräte auf alles zugreifen, also auch auf die
> Services. Hast du eigene Regeln, brauchst du einen Eintrag, der `svc:nextcloud` usw. als Ziel erlaubt.

### Auth-Key

Jetzt den Auth-Key holen: Admin-Konsole → **Settings** → **Keys** → **Generate auth key**. Lass *Reusable* aus,
schalte *Pre-approved* ein (falls angezeigt), wähle bei **Tags** `tag:server` und kopiere den Schlüssel
(`tskey-auth-…`). Er wird nur bei der allerersten Anmeldung gebraucht.

### Secrets-Datei

```bash
# 2. Zufälligen Schlüssel für Linkwarden erzeugen und anzeigen
#    (openssl kommt mit nix develop; ohne: head -c 32 /dev/urandom | base64)
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
systemctl status tailscale-serve-apps   # "active (exited)"
tailscale serve status --json     # unter "Services": svc:nextcloud, svc:vaultwarden, svc:linkwarden
                                  # (ohne --json zeigt es Services nicht an, dort steht "No serve config")
cat /sys/class/power_supply/BAT0/charge_control_end_threshold   # 80
```

## 7. Die Apps einrichten

Alle drei laufen nur auf `127.0.0.1`. Ins Tailnet bringt sie `tailscale serve` als Tailscale Service, jede mit
eigenem Namen und echtem Zertifikat. Der erste Aufruf kann eine Minute dauern, weil das Zertifikat erst geholt wird.

| App | Adresse | Erste Anmeldung |
|-----|---------|-----------------|
| **Nextcloud** | `https://nextcloud.<tailnet>.ts.net` | Benutzer `admin`, Passwort aus `secrets.yaml` |
| **Vaultwarden** | `https://vaultwarden.<tailnet>.ts.net` | **Create account**, Master-Passwort wie in [Kapitel 13](13-vaultwarden.md) |
| **Linkwarden** | `https://linkwarden.<tailnet>.ts.net` | **Sign Up**, dein Konto anlegen |

In den Bitwarden-Apps trägst du die Vaultwarden-Adresse als Server-URL ein, in der Linkwarden-Browser-Erweiterung die
Linkwarden-Adresse.

Das ist dasselbe Ergebnis wie mit dem Tailscale Operator in [Kapitel 10](10-tailscale-operator.md), nur ohne
Kubernetes: Dort legt der Operator für jede App ein eigenes Gerät an, hier stellt der ThinkPad alle Services bereit.

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

## 11. Eine weitere App hinzufügen

Jede neue App braucht drei Dinge. Als Beispiel **Uptime Kuma** ([Kapitel 28](28-uptime-kuma.md)), später erreichbar
unter `https://uptime.<tailnet>.ts.net`.

**1. In der Tailscale-Admin-Konsole** (einmalig pro App):

- **Services** → **Define a service**: Name `uptime`, Port `tcp:443`
- In der Policy unter `autoApprovers` → `services` ergänzen: `"svc:uptime": ["tag:server"],`

**2. In `nixos/thinkpad/apps.nix`** den Port eintragen. Der Name links ist zugleich der Name des Tailscale Service:

```nix
  ports = {
    nextcloud = 8080;
    vaultwarden = 8222;
    linkwarden = 3000;
    uptime = 3001; # neu
  };
```

Und die App selbst einschalten, z. B. direkt vor dem Tailscale-Block:

```nix
  services.uptime-kuma.enable = true; # lauscht von sich aus auf 127.0.0.1:3001
```

**3. Ausrollen und committen** wie in Schritt 8. `tailscale-serve-apps` startet dabei von selbst neu und
veröffentlicht den neuen Service.

Worauf du bei anderen Apps achten musst:

- Welche Einstellungen es gibt, zeigt <https://search.nixos.org/options> (nach `services.<app>` suchen).
- Die App muss auf `127.0.0.1` lauschen, und ihr Port muss zu dem in `ports` passen.
- Braucht sie ein Passwort oder einen geheimen Schlüssel, trägst du ihn mit `sops nixos/thinkpad/secrets.yaml` ein
  und bindest ihn in `apps.nix` unter `sops.secrets` ein, genau wie `nextcloud-admin-password`.

## Was bleibt Handarbeit?

Ganz ohne geht es nicht. Diese Schritte machst du einmal:

| Schritt | Warum nicht als Code |
|---------|----------------------|
| BIOS einstellen | Liegt außerhalb jedes Betriebssystems |
| USB-Stick, `passwd`, IP ablesen | Der Installer muss erst per SSH erreichbar sein |
| Tailscale: HTTPS, Tag, Services, Auth-Key | Gehört zu deinem Tailscale-Konto, nicht zum Server |
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
| ThinkPad taucht nicht im Tailnet auf | Per LAN-IP anmelden (`ssh homelab@192.168.178.50`) und `journalctl -u tailscaled-autoconnect -b` lesen. Auth-Key abgelaufen oder schon benutzt: neuen erzeugen, mit `sops nixos/thinkpad/secrets.yaml` ersetzen, ausrollen |
| `requested tags [tag:server] are invalid or not permitted` | `tagOwners` mit `tag:server` fehlt in der Tailscale-Policy (Schritt 3). Ergänzen, dann `sudo systemctl restart tailscaled-autoconnect` |
| `tailscale-serve-apps` schlägt fehl | `journalctl -u tailscale-serve-apps` zeigt den Grund. HTTPS in der Admin-Konsole aktiviert? |
| `service hosts must be tagged nodes` | Der ThinkPad hat kein Tag: Auth-Key ohne `tag:server` erzeugt oder `tagOwners` fehlt. In der Admin-Konsole beim Gerät **Edit ACL tags** → `tag:server`, dann `sudo systemctl restart tailscale-serve-apps` |
| Service-Name lädt nicht | Unter **Services** angelegt? Steht der ThinkPad dort als *approved*? Sonst `autoApprovers` prüfen oder von Hand freigeben |
| Zertifikatsfehler im Browser | Beim ersten Aufruf eine Minute warten |
| Nextcloud: "Zugriff über nicht vertrauenswürdige Domain" | Rufst du `nextcloud.<tailnet>.ts.net` auf, nicht die IP? Stimmt `tailnet` in `settings.nix`? |
| Ein Dienst startet nicht | `journalctl -u vaultwarden` (bzw. `linkwarden`, `phpfpm-nextcloud`, `nextcloud-setup`) |
| Netzwerk weg, wenn der Deckel zu ist | `journalctl -b \| grep -i lid` prüfen, `HandleLidSwitch` in `configuration.nix` |

## 🎓 Was du gelernt hast

- **Deklarativ** heißt: Du beschreibst das Ergebnis, nicht die Schritte. Der Rechner lässt sich jederzeit aus dem
  Repository neu aufbauen.
- `nixos-anywhere` + **disko** ersetzen den Installer: Partitionen, System und Apps in einem Befehl.
- **sops** verschlüsselt Secrets mit einem **age**-Schlüssel, damit sie gefahrlos im Git liegen.
- Jede Änderung ist eine **Generation**. Rollback geht per Befehl oder im Startmenü, aber die App-Daten brauchen
  trotzdem ein Backup.
- **Tailscale Services** geben jeder App einen eigenen Namen mit HTTPS im Tailnet, ohne Reverse-Proxy und ohne dass ein
  Port im Heimnetz offen ist. Nur getaggte Geräte dürfen Services anbieten.
- Ein ThinkPad braucht im Leerlauf nur einen Bruchteil eines Desktop-PCs und hat seine USV schon eingebaut.

---

⬅️ **Zurück:** [35 – Strom sparen](35-strom-sparen.md) · 🏠 **Zum Anfang:** [00 – Einführung](00-einfuehrung.md)
