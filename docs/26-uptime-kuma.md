# 26 – Uptime Kuma

> **Was du am Ende hast:** Uptime Kuma prüft jede Minute, ob deine Dienste antworten, und schickt dir eine
> Push-Nachricht aufs Handy, wenn etwas ausfällt.
>
> ⏱️ **Zeit:** ca. 30 Minuten
>
> 🧠 **Neue Begriffe:** Monitoring, Monitor, Benachrichtigung, Service-Adresse über Namespaces hinweg

---

## Probes reichen doch schon, oder?

Seit Kapitel 11 prüft Kubernetes mit **Probes**, ob Container gesund sind, und startet sie bei Bedarf neu. Warum also
noch ein Überwachungswerkzeug?

| | Kubernetes-Probes | Uptime Kuma |
|--|-------------------|-------------|
| Wer wird informiert? | niemand, Kubernetes handelt selbst | **du**, per Push-Nachricht |
| Was wird geprüft? | ein einzelner Container | der Dienst so, wie ein Nutzer ihn sieht (über den Service) |
| Hilft, wenn … | ein Container hängt | eine App dauerhaft kaputt ist, ein Pod `Pending` bleibt, die VM steht, die Platte voll ist |
| Verlauf | nein | ja: Verfügbarkeit in %, Antwortzeiten |

Die beiden ergänzen sich: Kubernetes repariert, was es reparieren kann. Uptime Kuma sagt dir Bescheid, wenn es das nicht schafft.

## 1. Aktivieren

```bash
cp kubernetes/katalog/uptime-kuma.yaml kubernetes/aktiv/
git add kubernetes/aktiv/uptime-kuma.yaml
git commit -m "Uptime Kuma aktivieren"
git push
```

Öffne <https://uptime.tail1a2b3c.ts.net>. Beim ersten Start fragt Uptime Kuma nach der Datenbank:
**SQLite** wählen (Standard, einfach) und einen Admin-Benutzer anlegen.

## 2. Monitore anlegen

**+ Neuen Monitor hinzufügen**. Uptime Kuma läuft im Cluster, also nutzen wir die **internen Service-Adressen**
im Format `http://<service>.<namespace>:<port>` (Kapitel 07). Viele Apps haben eine spezielle Adresse für Gesundheitschecks:

| Anzeigename | Monitor-Typ | URL | Zusatz |
|-------------|-------------|-----|--------|
| Jellyfin | HTTP(s) – Keyword | `http://jellyfin.media:8096/health` | Keyword: `Healthy` |
| Sonarr | HTTP(s) | `http://sonarr.media:8989/ping` | |
| Radarr | HTTP(s) | `http://radarr.media:7878/ping` | |
| Prowlarr | HTTP(s) | `http://prowlarr.media:9696/ping` | |
| qBittorrent | HTTP(s) | `http://qbittorrent.media:8080` | |
| Seerr | HTTP(s) | `http://seerr.media:5055/api/v1/settings/public` | |
| Vaultwarden | HTTP(s) | `http://vaultwarden.vaultwarden/alive` | |
| Immich | HTTP(s) | `http://immich-server.immich:2283/api/server/ping` | |
| Paperless | HTTP(s) | `http://paperless.paperless:8000` | |
| Homepage | HTTP(s) | `http://homepage.homepage:3000/api/healthcheck` | |
| Proxmox | HTTP(s) | `https://192.168.178.10:8006` | ☑ *TLS-/SSL-Fehler ignorieren* |

Das Intervall von 60 Sekunden ist gut. Unter **Erweitert** kannst du „Wiederholungen“ auf `2` setzen, damit ein
einzelner Aussetzer keinen Alarm auslöst.

> 💡 **Warum nicht die Tailscale-Adressen?** Der Uptime-Kuma-Pod ist selbst nicht im Tailnet. Die internen Adressen sind
> außerdem genauer: Fällt nur Tailscale aus, laufen die Apps ja trotzdem. Den Tailscale-Weg kannst du testen, indem du
> auf deinem **Handy** die Homepage aufrufst.

### Bonus: Läuft das VPN?

Kein qBittorrent ohne VPN, aber wie merkst du, dass Gluetun hängt? Ein **Keyword-Monitor** auf die Weboberfläche von
qBittorrent hilft nur halb. Nützlicher ist der Monitor, den du ohnehin hast: Gluetuns `livenessProbe` startet den Container
neu, und bleibt es dauerhaft kaputt, geht qBittorrent auf `0/2`. Dann meldet auch der qBittorrent-Monitor oben einen Fehler.

## 3. Benachrichtigungen aufs Handy

Uptime Kuma kennt Dutzende Wege (E-Mail, Telegram, Signal, Discord …). Einfach und kostenlos ist **ntfy**:

1. App **ntfy** auf dem Handy installieren (Android/iOS).
2. Ein **Thema** (Topic) mit einem schwer zu erratenden Namen abonnieren, z. B. `homelab-k3s-7g2k9h4b`. Jeder, der den
   Namen kennt, kann mitlesen, deshalb der Zufallsteil.
3. In Uptime Kuma: **Einstellungen → Benachrichtigungen → Benachrichtigung einrichten**:
   - Typ: **ntfy**
   - Server-URL: `https://ntfy.sh`
   - Thema: dein Thema
   - ☑ **Standardmäßig aktiviert**, ☑ **Auf alle existierenden Monitore anwenden**
4. **Testen**. Das Handy piept.

## 4. Test: ein Ausfall

Wir simulieren einen Ausfall von Jellyfin, und zwar per `kubectl`. Argo CD wird ihn rückgängig machen (Self-Heal),
aber für ein paar Sekunden ist Jellyfin weg:

```bash
kubectl scale deployment jellyfin -n media --replicas=0
```

Je nach Timing meldet Uptime Kuma nach 1–2 Minuten **Jellyfin: Down**. Kurz darauf hat Argo CD wieder 1 Replica hergestellt,
und es kommt **Jellyfin: Up**. Gerade hast du zwei Selbstheilungs-Ebenen gleichzeitig beobachtet. 🎉

> 💡 Ist Argo CD schneller als die Prüfung, merkt Uptime Kuma nichts. Auch das ist ein gutes Zeichen. Wiederhole den
> Test sonst mit einem Dienst, dessen Pod du löschst, z. B. `kubectl delete pod -n vaultwarden -l app=vaultwarden`.

## 5. Optional: Statusseite

Unter **Statusseiten** kannst du eine Übersichtsseite bauen, z. B. „Heimkino“ mit Jellyfin und Seerr, und den Link mit der
Familie teilen (Tailscale-Sharing aus Kapitel 21 auf das Gerät `uptime`).

## 🎉 Teil E geschafft!

Dein Homelab ist jetzt ein richtiges Zuhause für deine Daten:

| Bereich | Apps |
|---------|------|
| Medien | Jellyfin (GPU), *arr-Stack, Seerr |
| Persönliches | Vaultwarden, Immich, Paperless-ngx |
| Überblick | Homepage, Uptime Kuma, Argo CD |

Wie voll ist die VM?

```bash
kubectl top node
```

```
NAME   CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k3s    420m         5%       5890Mi          49%
```

Etwa die Hälfte des RAMs ist belegt. Beim Transkodieren oder beim ersten Gesichter-Scan in Immich steigt das zeitweise.

**Jetzt kommt der wichtigste Teil:** In **Teil F** sicherst du alles. Vaultwarden, Immich und Paperless enthalten
Daten, die nicht verloren gehen dürfen.

## ✅ Checkpoint

- [ ] `https://uptime.<tailnet>.ts.net` ist erreichbar.
- [ ] Alle Dienste haben einen Monitor und sind **Up**.
- [ ] Eine Test-Benachrichtigung kam auf dem Handy an.
- [ ] Du hast einen Ausfall und die automatische Wiederherstellung beobachtet.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Monitor sofort rot: `getaddrinfo ENOTFOUND` | Tippfehler im Service- oder Namespace-Namen → `kubectl get svc -A` |
| `ECONNREFUSED` bei qBittorrent | Gluetun-Firewall: `FIREWALL_INPUT_PORTS` muss `8080` enthalten (Kapitel 18) |
| Proxmox-Monitor rot | *TLS-Fehler ignorieren* angehakt? Proxmox-IP richtig? |
| Keine Push-Nachricht | ntfy-Thema in App und Uptime Kuma exakt gleich geschrieben? |

## 🎓 Was du gelernt hast

- **Probes** heilen, **Monitoring** informiert. Beides zusammen macht ein Homelab zuverlässig.
- Im Cluster erreicht man jeden Dienst über `http://<service>.<namespace>:<port>`.
- Viele Apps haben eigene Health-Adressen (`/health`, `/ping`, `/alive`).
- Mit ntfy bekommst du ohne eigenes Konto Push-Nachrichten aufs Handy.

---

⬅️ **Zurück:** [25 – Paperless-ngx](25-paperless.md) · ➡️ **Weiter:** [27 – Backup & Restore](27-backup-restore.md)
