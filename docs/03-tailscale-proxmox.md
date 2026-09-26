# 03 – Tailscale auf Proxmox

> **Was du am Ende hast:** Die Proxmox-Weboberfläche ist von überall erreichbar, unter
> `https://pve.<tailnet>.ts.net` mit echtem HTTPS-Zertifikat und ohne offenen Port am Router.
>
> ⏱️ **Zeit:** ca. 20 Minuten
>
> 🧠 **Neue Begriffe:** [Tailscale](glossar.md#netzwerk), [Tailnet](glossar.md#netzwerk),
> [MagicDNS](glossar.md#netzwerk), [WireGuard](glossar.md#netzwerk)

---

## Wie funktioniert das?

Normalerweise müsste man für den Zugriff von unterwegs am Router eine **Portweiterleitung** einrichten. Dann steht der
Server aber offen im Internet, und jeder kann an die Tür klopfen.

Tailscale geht einen anderen Weg: Jedes Gerät baut selbst eine verschlüsselte **WireGuard**-Verbindung zu deinen anderen
Geräten auf. Von außen ist nichts erreichbar. Nur Geräte, die in deinem **Tailnet** angemeldet sind, sehen sich gegenseitig.

```
   Handy (Mobilfunk) ──┐
                       │  verschlüsselt, direkt
   Laptop (Café) ──────┼──────────────────────────►  pve (zu Hause)
                       │
   Router zu Hause: alle Ports bleiben zu ✅
```

## 1. Tailscale installieren

> 🟧 **Auf Proxmox** (`ssh root@192.168.178.10` oder **pve → >_ Shell**)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

> 💡 **Was macht dieser Befehl?** `curl` lädt das offizielle Installationsskript von Tailscale herunter, und `sh` führt
> es aus. Das Skript fügt die Tailscale-Paketquelle hinzu und installiert das Paket. Wer vorher nachlesen möchte,
> öffnet <https://tailscale.com/install.sh> im Browser.

## 2. Proxmox im Tailnet anmelden

```bash
tailscale up
```

Ausgabe:

```
To authenticate, visit:

        https://login.tailscale.com/a/1a2b3c4d5e6f
```

Öffne den Link auf deinem Rechner, melde dich an und klicke **Connect**. Im Terminal erscheint `Success.`

Prüfe die neue Tailscale-Adresse:

```bash
tailscale ip -4
```

```
100.101.102.103
```

Jedes Gerät im Tailnet bekommt eine Adresse aus dem Bereich `100.x.y.z`.

## 3. Schlüssel-Ablauf abschalten

Aus Sicherheitsgründen müssen sich Geräte bei Tailscale standardmäßig alle 180 Tage neu anmelden. Für einen Server,
an dem niemand sitzt, ist das unpraktisch: Er wäre plötzlich nicht mehr erreichbar.

1. Öffne die [Admin-Konsole → Machines](https://login.tailscale.com/admin/machines).
2. Klicke beim Gerät **pve** auf **⋯** → **Disable key expiry**.

## 4. Erster Test von deinem Rechner

> 💻 **Auf deinem Rechner**

```bash
tailscale status
```

```
100.64.10.20     laptop     dein-name@   linux   -
100.101.102.103  pve        dein-name@   linux   -
```

Dank **MagicDNS** funktioniert jetzt der Name `pve`:

```bash
ping -c 3 pve
ssh root@pve
```

Auch `https://pve:8006` funktioniert im Browser, allerdings noch mit der Zertifikatswarnung.

## 5. Echtes HTTPS mit `tailscale serve`

Tailscale kann für Geräte im Tailnet echte, vertrauenswürdige HTTPS-Zertifikate besorgen. Mit `tailscale serve`
leiten wir Anfragen auf die Proxmox-Weboberfläche weiter.

> 🟧 **Auf Proxmox**

```bash
tailscale serve --bg https+insecure://localhost:8006
```

Ausgabe (ungefähr so, mit deinem Tailnet-Namen):

```
Available within your tailnet:

https://pve.tail1a2b3c.ts.net/
|-- proxy https+insecure://localhost:8006

Serve started and running in the background.
```

> 💡 **Was bedeutet das?**
> - `--bg`: läuft dauerhaft im Hintergrund, auch nach einem Neustart
> - `https+insecure://localhost:8006`: Tailscale leitet an Proxmox auf demselben Rechner weiter. „insecure“ heißt nur,
>   dass Tailscale das selbst ausgestellte Proxmox-Zertifikat akzeptiert. Die Verbindung verlässt den Rechner dabei nicht.
>
> Fragt der Befehl stattdessen nach einer Freigabe (*„Serve is not enabled on your tailnet“*), öffne den angezeigten
> Link, bestätige und führe den Befehl erneut aus.

> 💻 **Auf deinem Rechner:** Öffne `https://pve.tail1a2b3c.ts.net` (mit deinem Tailnet-Namen).
> Die Proxmox-Anmeldung erscheint, diesmal **ohne Zertifikatswarnung**. 🔒

Beim allerersten Aufruf kann es ein paar Sekunden dauern, weil das Zertifikat erst ausgestellt wird.

## 6. Test von unterwegs

Das ist der eigentliche Beweis:

1. Installiere die **Tailscale-App** auf deinem Handy (Android/iOS) und melde dich mit demselben Konto an.
2. Schalte am Handy das **WLAN aus**, damit du wirklich über das Mobilfunknetz gehst.
3. Öffne im Handy-Browser `https://pve.tail1a2b3c.ts.net`.

Die Proxmox-Anmeldung erscheint. Du greifst jetzt von „außen“ auf deinen Server zu, und am Router ist kein einziger Port offen.

## ✅ Checkpoint

- [ ] In der Admin-Konsole steht **pve** mit dem Vermerk **Expiry disabled**.
- [ ] `ssh root@pve` funktioniert von deinem Rechner.
- [ ] `https://pve.<tailnet>.ts.net` öffnet Proxmox ohne Zertifikatswarnung.
- [ ] Der Zugriff klappt auch vom Handy über Mobilfunk.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| `ping pve` → `Name or service not known` | Ist MagicDNS aktiviert (Admin-Konsole → DNS)? Läuft Tailscale auf deinem Rechner (`tailscale status`)? |
| Gerät heißt `pve-1` statt `pve` | Es gibt schon ein Gerät namens `pve`, z. B. von einem früheren Versuch. Altes Gerät in der Admin-Konsole löschen, dann **⋯ → Edit machine name** |
| `tailscale serve` meldet, dass HTTPS nicht aktiviert ist | Admin-Konsole → **DNS** → **HTTPS Certificates** → **Enable HTTPS** |
| Seite lädt lange und bricht ab | Einmal `tailscale serve reset` und den `serve`-Befehl erneut ausführen |

## 🎓 Was du gelernt hast

- Tailscale verbindet Geräte direkt und verschlüsselt, ohne offene Ports am Router.
- MagicDNS macht Geräte über ihren Namen erreichbar (`pve`).
- Server brauchen **Disable key expiry**.
- `tailscale serve` stellt einen lokalen Dienst mit echtem HTTPS-Zertifikat im Tailnet bereit.

Genau dieses Prinzip nutzen wir später für jede App im Cluster, dann automatisch über den Tailscale Operator.

---

⬅️ **Zurück:** [02 – Proxmox installieren](02-proxmox-installieren.md) · ➡️ **Weiter:** [04 – Die Kubernetes-VM](04-kubernetes-vm.md)
