# 01 – Voraussetzungen

> **Was du am Ende hast:** Alle Konten, Werkzeuge und BIOS-Einstellungen sind vorbereitet, und du hast einen
> Spickzettel mit deinen Netzwerk-Werten.
>
> ⏱️ **Zeit:** ca. 45 Minuten
>
> 🧠 **Neue Begriffe:** [BIOS/UEFI](glossar.md#homelab--infrastruktur), [SVM](glossar.md#homelab--infrastruktur),
> [IOMMU](glossar.md#homelab--infrastruktur), [SSH-Key](glossar.md#netzwerk), [Statische IP](glossar.md#netzwerk), [DHCP](glossar.md#netzwerk)

---

## 1. Hardware-Checkliste

| ✔ | Was | Wofür |
|---|-----|-------|
| ☐ | **Desktop-PC** (Ryzen 5, 16 GB RAM, RTX 2070 Super, 500-GB-HDD) | wird der Server |
| ☐ | **Netzwerkkabel** zum Router | Proxmox braucht kabelgebundenes Netzwerk, WLAN wird nicht unterstützt |
| ☐ | **Monitor + Tastatur** | nur für die Installation, danach läuft alles über den Browser |
| ☐ | **USB-Stick** (mind. 4 GB) | Installationsmedium für Proxmox, **wird komplett gelöscht** |
| ☐ | *(später)* **USB-Festplatte** | Ziel für Backups ([Kapitel 27](27-backup-restore.md)) |

> ⚠️ **Achtung: Die 500-GB-Festplatte wird komplett gelöscht.** Sichere vorher alles, was du davon noch brauchst.
> Sind noch weitere Festplatten eingebaut, notiere dir ihre Größe, damit du bei der Installation nicht die falsche erwischst.

## 2. Konten anlegen

### Tailscale

1. Öffne <https://login.tailscale.com/start> und melde dich an, z. B. mit deinem GitHub-Konto.
2. Der kostenlose **Personal**-Tarif reicht völlig aus.
3. Nach dem Login landest du in der **Admin-Konsole**. Die brauchst du später noch oft: <https://login.tailscale.com/admin>
4. Öffne in der Admin-Konsole den Reiter **DNS**:
   - Prüfe, dass **MagicDNS** aktiviert ist (bei neuen Konten Standard).
   - Klicke weiter unten bei **HTTPS Certificates** auf **Enable HTTPS**.
   - Notiere dir oben den **Tailnet-Namen**, er sieht aus wie `tail1a2b3c.ts.net`.

> 💡 **Was ist Tailscale?** Tailscale verbindet all deine Geräte zu einem privaten Netz, dem *Tailnet*, egal ob
> sie zu Hause oder unterwegs sind. Dein Laptop im Café kann dann den Server zu Hause erreichen, als stünde er
> daneben. Und das, ohne dass du am Router irgendetwas öffnen musst.

### GitHub

Hast du bereits. Du brauchst es gleich für deinen SSH-Key und später für GitOps (Kapitel 13).

### Proton VPN

Brauchst du erst in Kapitel 18 (qBittorrent). Du musst jetzt noch nichts abschließen.

## 3. Werkzeuge auf deinem Rechner

> 💻 **Auf deinem Rechner**

Du brauchst: `git`, `ssh`, `tailscale`, `kubectl`, `helm` und `k9s`. Später kommen `kubeseal` und `argocd` dazu.

### Variante A: Nix (empfohlen für NixOS)

Dieses Repository enthält eine [`flake.nix`](../flake.nix), die alle Kubernetes-Werkzeuge bereitstellt.

Flakes müssen in deiner NixOS-Konfiguration aktiviert sein:

```nix
# /etc/nixos/configuration.nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

Repository klonen und die Werkzeuge laden:

```bash
git clone https://github.com/Katagawa94/homelab-tutorial.git
cd homelab-tutorial
nix develop
```

Erwartete Ausgabe (nach dem ersten Download):

```
🏠 Homelab-Werkzeuge geladen: kubectl, helm, k9s, kubeseal, argocd, …
```

> 💡 Die Werkzeuge sind nur in *diesem* Terminal verfügbar. Öffnest du ein neues Terminal, führe im Repository-Ordner
> wieder `nix develop` aus. Wer [direnv](https://direnv.net/) nutzt, kann das mit `echo "use flake" > .envrc` automatisieren.

### Tailscale auf NixOS

Tailscale läuft als Systemdienst und gehört deshalb in die NixOS-Konfiguration, nicht in die `flake.nix`:

```nix
# /etc/nixos/configuration.nix
services.tailscale.enable = true;
```

Danach `sudo nixos-rebuild switch` und einmalig anmelden:

```bash
sudo tailscale up
```

Öffne den angezeigten Link und bestätige. Dein Rechner erscheint jetzt in der Admin-Konsole unter **Machines**.

### Variante B: anderes Betriebssystem

Installiere die Werkzeuge nach den offiziellen Anleitungen:
[kubectl](https://kubernetes.io/docs/tasks/tools/) ·
[helm](https://helm.sh/docs/intro/install/) ·
[k9s](https://k9scli.io/topics/install/) ·
[Tailscale](https://tailscale.com/download)

## 4. SSH-Key prüfen

> 💻 **Auf deinem Rechner**

Ein SSH-Key ersetzt das Passwort beim Anmelden auf dem Server und ist deutlich sicherer.

```bash
ls ~/.ssh/id_ed25519.pub
```

- **Datei existiert** → alles gut.
- **„No such file or directory“** → neuen Key erstellen (Passphrase empfohlen):

  ```bash
  ssh-keygen -t ed25519 -C "homelab"
  ```

Der Ubuntu-Installer kann deinen Key später direkt von GitHub holen. Dafür muss er dort hinterlegt sein:

1. Inhalt anzeigen: `cat ~/.ssh/id_ed25519.pub`
2. Auf GitHub unter **Settings → SSH and GPG keys → New SSH key** einfügen.
3. Prüfen: Öffne `https://github.com/<DEIN-GITHUB-NAME>.keys` im Browser. Dort muss dein Key stehen.

## 5. BIOS einstellen

Jetzt geht es an den Desktop-PC. Wir schalten drei Dinge ein:

| Einstellung | Wofür | Typischer Name |
|-------------|-------|----------------|
| **SVM** | Ohne sie laufen keine VMs | `SVM Mode`, `AMD-V`, `Virtualization` |
| **IOMMU** | Grafikkarte später an die VM durchreichen (Kapitel 15) | `IOMMU`, `AMD-Vi` |
| **Nach Stromausfall einschalten** | Server startet von selbst wieder | `Restore on AC Power Loss` → `Power On` |

**So kommst du ins BIOS:** PC einschalten und sofort mehrmals `Entf` (`Del`) oder `F2` drücken.

Wo die Optionen genau liegen, hängt vom Mainboard-Hersteller ab. Typische Orte:

| Hersteller | SVM | IOMMU |
|------------|-----|-------|
| ASUS | Advanced → CPU Configuration → SVM Mode | Advanced → AMD CBS → NBIO Common Options → IOMMU |
| MSI | OC → Advanced CPU Configuration → SVM Mode | Settings → Advanced → AMD CBS → NBIO Common Options → IOMMU |
| Gigabyte | M.I.T. bzw. Tweaker → Advanced CPU Settings → SVM Mode | Chipset bzw. Settings → IOMMU |
| ASRock | Advanced → CPU Configuration → SVM Mode | Advanced → AMD CBS → NBIO Common Options → IOMMU |

Setze beide auf **Enabled** (nicht „Auto“). Speichere mit `F10` und starte neu.

> 💡 **Option nicht gefunden?** Viele BIOS haben eine „Easy Mode“-Ansicht. Wechsle mit `F7` in den „Advanced Mode“.
> Fehlt IOMMU komplett, hilft oft ein BIOS-Update von der Hersteller-Seite.

## 6. Netzwerk planen: dein Spickzettel

Server brauchen **feste IP-Adressen**, damit du (und der Samsung-TV) sie immer unter derselben Adresse findest.

### Heimnetz herausfinden

> 💻 **Auf deinem Rechner**

```bash
ip route | grep default
```

Beispielausgabe:

```
default via 192.168.178.1 dev wlp3s0 proto dhcp src 192.168.178.42 metric 600
```

Hier ist `192.168.178.1` dein **Router** (Gateway), und dein Netz ist `192.168.178.x`.

### Zwei freie Adressen wählen

Dein Router verteilt Adressen automatisch aus einem Bereich (DHCP-Bereich). Wir wählen zwei Adressen **außerhalb**
dieses Bereichs, damit es nie zu Doppelbelegungen kommt.

- **FRITZ!Box:** Heimnetz → Netzwerk → Netzwerkeinstellungen → IPv4-Einstellungen. Standardmäßig vergibt sie
  `.20` bis `.200`, also sind z. B. `.10` und `.11` frei.
- **Andere Router:** Suche in der Weboberfläche nach „DHCP“.

### Spickzettel ausfüllen

Kopiere diese Tabelle in eine Notiz. Das Tutorial nutzt die Beispielwerte. Wo sie auftauchen, setzt du deine eigenen ein.

| Was | Beispielwert | Dein Wert |
|-----|--------------|-----------|
| Router / Gateway | `192.168.178.1` | |
| Netzmaske | `/24` | |
| Proxmox-Host: Name / IP | `pve` / `192.168.178.10` | |
| Kubernetes-VM: Name / IP | `k3s` / `192.168.178.11` | |
| VM-Benutzername | `homelab` | |
| Tailnet-Name | `tail1a2b3c.ts.net` | |
| GitHub-Benutzername | `<DEIN-GITHUB-NAME>` | |

> 🔐 **Passwörter** (Proxmox-root, VM-Benutzer) gehören in einen Passwortmanager, nicht auf den Spickzettel.

## ✅ Checkpoint

- [ ] Tailscale-Konto existiert, MagicDNS und HTTPS sind aktiviert, der Tailnet-Name ist notiert.
- [ ] Dein Rechner taucht in der Tailscale-Admin-Konsole unter **Machines** auf.
- [ ] `kubectl version --client` und `helm version` funktionieren (ggf. nach `nix develop`).
- [ ] `https://github.com/<DEIN-GITHUB-NAME>.keys` zeigt deinen SSH-Key.
- [ ] Im BIOS sind SVM und IOMMU auf **Enabled**.
- [ ] Der Spickzettel ist ausgefüllt.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| `nix develop` meldet `experimental Nix feature 'flakes' is disabled` | Flakes wie oben beschrieben aktivieren und `sudo nixos-rebuild switch` ausführen |
| `tailscale up` meldet `failed to connect to local tailscaled` | Der Dienst läuft nicht, prüfe `services.tailscale.enable = true;` und baue neu |
| BIOS zeigt keine SVM-Option | Nach `Virtualization`, `CPU Virtualization` oder `Secure Virtual Machine` suchen, ggf. BIOS aktualisieren |

## 🎓 Was du gelernt hast

- Tailscale verbindet deine Geräte zu einem privaten Netz, dem Tailnet.
- SSH-Keys sind sicherer als Passwörter, und GitHub dient als bequeme Ablage für deinen öffentlichen Key.
- SVM erlaubt VMs, IOMMU erlaubt das Durchreichen von Hardware an VMs.
- Server bekommen feste IP-Adressen außerhalb des DHCP-Bereichs des Routers.

---

⬅️ **Zurück:** [00 – Einführung](00-einfuehrung.md) · ➡️ **Weiter:** [02 – Proxmox installieren](02-proxmox-installieren.md)
