# 18 – qBittorrent + Proton VPN

> **Was du am Ende hast:** qBittorrent läuft im Cluster, und sein **gesamter** Internetverkehr geht durch Proton VPN.
> Fällt das VPN aus, lädt qBittorrent nichts mehr (Kill-Switch). Der von Proton freigegebene Port wird automatisch eingetragen.
>
> ⏱️ **Zeit:** ca. 1 Stunde
>
> 🧠 **Neue Begriffe:** [Sidecar](glossar.md#container--kubernetes), [nativer Sidecar](glossar.md#container--kubernetes),
> Netzwerk-Namespace, `capabilities`, [Kill-Switch](glossar.md#netzwerk), [Port-Forwarding (VPN)](glossar.md#netzwerk)

---

> 📸 **Snapshot-Routine:** Snapshot der VM anlegen (bei ausgeschalteter VM, siehe Kapitel 15).

## Die Idee: zwei Container, ein Netzwerk

In Kapitel 06 hast du gelernt: Ein Pod kann **mehrere Container** enthalten. Sie teilen sich dann **ein Netzwerk**:
dieselbe IP und dieselben Netzwerkkarten. Genau das nutzen wir:

```
┌────────────────────── Pod qbittorrent ──────────────────────┐
│                                                             │
│  ┌──────────────┐                     ┌──────────────────┐  │
│  │   gluetun    │  baut VPN auf       │   qbittorrent    │  │
│  │  (Sidecar)   │  setzt Firewall     │   (die App)      │  │
│  └──────────────┘                     └──────────────────┘  │
│                                                             │
│  gemeinsames Netzwerk:                                      │
│    tun0  ══ WireGuard ══► Proton VPN ══► Internet   ✅      │
│    eth0  ──────────────► Internet                   ❌ gesperrt
│    eth0  ──────────────► Cluster (10.42.x/10.43.x)  ✅ für Sonarr, Radarr, Tailscale
└─────────────────────────────────────────────────────────────┘
```

**Gluetun** ist ein VPN-Client, der speziell für Container gebaut ist:

- Er baut die WireGuard-Verbindung zu Proton VPN auf.
- Er stellt die **Firewall** des Pods so ein, dass ins Internet **nur** der Weg durchs VPN offen ist. Das ist der **Kill-Switch**:
  Bricht das VPN zusammen, gibt es keinen anderen Weg nach draußen.
- Er holt bei Proton einen **weitergeleiteten Port**, über den andere Teilnehmer dich erreichen können. Das macht
  Downloads deutlich schneller.

qBittorrent merkt davon nichts. Es sieht einfach ein Netzwerk, das nur durchs VPN ins Internet führt.

## 1. Proton VPN vorbereiten

### Abo

Du brauchst **Proton VPN Plus** (oder ein Proton-Paket, das VPN Plus enthält). Der kostenlose Tarif erlaubt **kein P2P**
und kein Port-Forwarding.

### WireGuard-Schlüssel erzeugen

1. Melde dich auf <https://account.proton.me> an → **VPN** → **WireGuard configuration** (unter „Downloads“).
2. **Name:** `homelab-k3s`
3. **Platform:** GNU/Linux
4. **VPN options:** ☑ **NAT-PMP (Port Forwarding)** ← wichtig! ☐ NetShield-Werbeblocker kannst du nach Wunsch setzen
5. Wähle einen beliebigen Server mit **P2P**-Symbol und klick **Create**.
6. Es erscheint eine Konfiguration. Kopiere **nur** den Wert hinter `PrivateKey =` in deinen Passwortmanager.
   (Der Rest wird nicht gebraucht, denn Gluetun kennt die Proton-Server selbst.)

> 💡 Dieser Schlüssel funktioniert für **alle** Proton-Server. Welcher Server genommen wird, bestimmt Gluetun über
> `SERVER_COUNTRIES` im Deployment.

## 2. Den Schlüssel versiegeln

Wie in Kapitel 14: Das Secret wird verschlüsselt ins Git gelegt.

> 💻 **Auf deinem Rechner** (im Ordner `homelab-tutorial`)

```bash
mkdir -p kubernetes/secrets/media
kubectl create secret generic gluetun-protonvpn -n media \
  --from-literal=WIREGUARD_PRIVATE_KEY='<DEIN-PRIVATE-KEY>' \
  --dry-run=client -o yaml \
| kubeseal --format yaml > kubernetes/secrets/media/gluetun-protonvpn.yaml
```

Die Application `secrets` rollt alles in `kubernetes/secrets/` aus, also auch diesen neuen Unterordner.

## 3. Das Deployment verstehen

[`kubernetes/apps/media/qbittorrent/deployment.yaml`](../kubernetes/apps/media/qbittorrent/deployment.yaml) ist das
bisher längste Manifest. Hier die wichtigen Stellen.

### Gluetun als nativer Sidecar

```yaml
    spec:
      initContainers:
        - name: gluetun
          image: qmcgaw/gluetun:v3.41.3
          restartPolicy: Always
          ...
          startupProbe:
            exec:
              command: ["/gluetun-entrypoint", "healthcheck"]
      containers:
        - name: qbittorrent
          image: lscr.io/linuxserver/qbittorrent:5.2.3
```

Gluetun steht unter **`initContainers`** und hat **`restartPolicy: Always`**. Das ist ein **nativer Sidecar**:

| | normaler zweiter Container | nativer Sidecar |
|--|----------------------------|-----------------|
| Startreihenfolge | beide gleichzeitig, also könnte qBittorrent loslegen, **bevor** das VPN steht ⚠️ | Gluetun zuerst. qBittorrent startet erst, wenn Gluetuns `startupProbe` erfolgreich ist |
| Läuft mit | ✅ | ✅ |

Die `startupProbe` führt Gluetuns eingebauten Gesundheitscheck aus (`exec` statt `httpGet`: ein Befehl im Container).
Erst wenn das VPN nachweislich funktioniert, darf qBittorrent starten.

### Rechte: `NET_ADMIN`

```yaml
          securityContext:
            capabilities:
              add: ["NET_ADMIN"]
```

Container dürfen normalerweise nicht an Netzwerk und Firewall herumschrauben. **Capabilities** sind einzelne
Sonderrechte. `NET_ADMIN` erlaubt genau das, was Gluetun braucht: VPN-Verbindung anlegen und Firewall setzen. Mehr nicht.

### Die VPN-Einstellungen

```yaml
          envFrom:
            - secretRef:
                name: gluetun-protonvpn   # WIREGUARD_PRIVATE_KEY
          env:
            - name: VPN_SERVICE_PROVIDER
              value: protonvpn
            - name: VPN_TYPE
              value: wireguard
            - name: SERVER_COUNTRIES
              value: Netherlands,Switzerland
            - name: PORT_FORWARD_ONLY     # nur Server, die P2P und Port-Forwarding erlauben
              value: "on"
            - name: VPN_PORT_FORWARDING   # Proton gibt uns einen Port für eingehende Verbindungen
              value: "on"
```

`SERVER_COUNTRIES` darfst du ändern, z. B. auf `Germany` oder `Sweden`. Nahe Länder sind meist schneller.

### Port automatisch an qBittorrent melden

Proton teilt bei jeder Verbindung einen **zufälligen** Port zu. Damit qBittorrent ihn benutzt, ruft Gluetun nach dem
Verbindungsaufbau die Schnittstelle von qBittorrent auf. Beide teilen sich das Netzwerk, also geht das über `127.0.0.1`:

```yaml
            - name: VPN_PORT_FORWARDING_UP_COMMAND
              value: >-
                /bin/sh -c 'wget -O- -nv --retry-connrefused --post-data
                "json={\"listen_port\":{{PORT}},\"current_network_interface\":\"{{VPN_INTERFACE}}\",\"random_port\":false,\"upnp\":false}"
                http://127.0.0.1:8080/api/v2/app/setPreferences'
```

Gluetun ersetzt `{{PORT}}` durch den Port und `{{VPN_INTERFACE}}` durch den Namen der VPN-Netzwerkkarte. Nebenbei wird
qBittorrent so an die VPN-Karte **gebunden**: eine zweite Sicherung zusätzlich zur Firewall.

> 💡 `>-` in YAML heißt: *„Die folgenden Zeilen zu einer Zeile zusammenfügen.“* So bleibt der lange Befehl lesbar.

### Die Firewall für Kubernetes öffnen

```yaml
            - name: FIREWALL_OUTBOUND_SUBNETS
              value: 10.42.0.0/16,10.43.0.0/16
            - name: FIREWALL_INPUT_PORTS
              value: "8080"
```

Gluetuns Firewall sperrt alles, was nicht durchs VPN geht, auch das Cluster-Netz. Wir machen zwei Ausnahmen:

- **`FIREWALL_INPUT_PORTS=8080`**: Die Weboberfläche darf von außerhalb des Pods angesprochen werden (Sonarr, Radarr, Tailscale-Proxy).
- **`FIREWALL_OUTBOUND_SUBNETS`**: Antworten und Anfragen ins Cluster-Netz (Pods `10.42.x.x`, Services `10.43.x.x`) gehen nicht ins VPN.

> 💡 **Kleiner Schönheitsfehler:** Namensauflösungen (DNS) von qBittorrent laufen über das Cluster-DNS und damit am VPN
> vorbei. Dein Internetanbieter könnte also sehen, *welche* Tracker-Namen abgefragt werden, aber nicht, was übertragen wird.
> Für ein Einsteiger-Setup ist das ein vertretbarer Kompromiss.

## 4. Aktivieren

```bash
cp kubernetes/katalog/qbittorrent.yaml kubernetes/aktiv/
git add kubernetes/aktiv/qbittorrent.yaml kubernetes/secrets/media/
git commit -m "qBittorrent mit Proton VPN"
git push
```

Nach dem Sync beobachten:

```bash
kubectl get pods -n media -l app=qbittorrent -w
```

```
NAME                           READY   STATUS            RESTARTS   AGE
qbittorrent-6d9f8b7c5d-k2x9m   0/2     Init:0/1          0          5s
qbittorrent-6d9f8b7c5d-k2x9m   0/2     PodInitializing   0          25s
qbittorrent-6d9f8b7c5d-k2x9m   2/2     Running           0          40s
```

`Init:0/1` heißt: Gluetun baut gerade das VPN auf. `2/2`: beide Container laufen.

Was hat Gluetun gemacht? Mit `-c` wählst du den Container im Pod:

```bash
kubectl logs -n media deploy/qbittorrent -c gluetun | grep -iE "public ip|port forward|healthy"
```

```
INFO [ip getter] Public IP address is 185.xx.xx.xx (Netherlands, North Holland, Amsterdam)
INFO [port forwarding] port forwarded is 51234
INFO [healthcheck] healthy!
```

## 5. qBittorrent einrichten

### Erster Login

qBittorrent erzeugt beim ersten Start ein **zufälliges Passwort** und schreibt es ins Log:

```bash
kubectl logs -n media deploy/qbittorrent -c qbittorrent | grep -i password
```

```
The WebUI administrator password was not set. A temporary password is provided for this session: Xk2p9Qm4a
```

Für die erste Einrichtung verbinden wir uns per `port-forward` (Kapitel 06), denn manche Einstellungen gelten nur für „lokale“ Zugriffe:

```bash
kubectl port-forward -n media deploy/qbittorrent 8080:8080
```

Öffne <http://localhost:8080>. **Benutzer:** `admin`, **Passwort:** das aus dem Log.

### Einstellungen (Zahnrad-Symbol)

**Downloads**

| Einstellung | Wert |
|-------------|------|
| Standard-Speicherpfad | `/data/downloads` |
| Unvollständige Torrents speichern in | ☐ (aus: alles bleibt auf einer Platte, keine Kopiervorgänge) |

**Verbindung**

| Einstellung | Wert |
|-------------|------|
| Port für eingehende Verbindungen | wird von Gluetun gesetzt (z. B. `51234`), **nicht ändern** |
| UPnP / NAT-PMP-Portweiterleitung | ☐ aus |

**BitTorrent**

| Einstellung | Wert |
|-------------|------|
| Seeding-Grenzen | z. B. „Wenn Verhältnis 2 erreicht ist → Torrent pausieren“ (spart Platz und Upload) |

**WebUI**

| Einstellung | Wert | Warum |
|-------------|------|-------|
| Authentifizierung: Benutzername/Passwort | eigenes Passwort → Passwortmanager | das Zufallspasswort gilt nur bis zum Neustart |
| **Authentifizierung für Clients auf localhost umgehen** | ☑ | damit Gluetun den Port ohne Passwort setzen kann |
| **Reverse-Proxy-Unterstützung aktivieren** | ☑ | Zugriff über den Tailscale-Proxy |
| Vertrauenswürdige Proxys | `10.42.0.0/16` | das Pod-Netz, in dem der Tailscale-Proxy läuft |

**Speichern**, `port-forward` mit `Strg+C` beenden.

Ab jetzt erreichst du qBittorrent über <https://qbittorrent.tail1a2b3c.ts.net>.

## 6. Die wichtigsten Tests

### Welche IP sieht das Internet?

```bash
kubectl exec -n media deploy/qbittorrent -c qbittorrent -- curl -s https://ipinfo.io/ip; echo
curl -s https://ipinfo.io/ip; echo       # zum Vergleich: deine eigene IP
```

Die erste Adresse muss eine **andere** sein als deine eigene: die des Proton-Servers.

### Ist der Kill-Switch dicht?

Wir versuchen, am VPN vorbei direkt über die normale Netzwerkkarte `eth0` ins Internet zu kommen:

```bash
kubectl exec -n media deploy/qbittorrent -c qbittorrent -- \
  sh -c 'curl -s --max-time 5 --interface eth0 https://ipinfo.io/ip || echo "blockiert ✅"'
```

```
blockiert ✅
```

Gluetuns Firewall lässt nichts am VPN vorbei ins Internet.

### Stimmt der Port?

In qBittorrent unter **Einstellungen → Verbindung** steht derselbe Port wie in Gluetuns Log (`port forwarded is …`).
Unten in der Statusleiste zeigt ein **grünes** Verbindungssymbol, dass eingehende Verbindungen möglich sind.

### Ein erster Download

Teste mit einem legalen Torrent, z. B. einer Linux-Distribution: Auf <https://releases.ubuntu.com> gibt es für jede
Version eine `.torrent`-Datei. Kopiere den Link, klicke in qBittorrent auf **Torrent-Links hinzufügen** und füge ihn ein.

```bash
ssh homelab@k3s ls -l /data/downloads
```

Die Datei erscheint in `/data/downloads`, mit Besitzer `homelab` (1000). Danach den Torrent in qBittorrent samt Datei wieder löschen.

## ✅ Checkpoint

- [ ] `kubectl get pods -n media -l app=qbittorrent` zeigt `2/2 Running`.
- [ ] Gluetuns Log zeigt eine Proton-IP und einen weitergeleiteten Port.
- [ ] Die IP aus qBittorrent heraus ist **nicht** deine eigene.
- [ ] Der Test über `eth0` ergibt `blockiert ✅`.
- [ ] qBittorrent ist über `https://qbittorrent.<tailnet>.ts.net` mit eigenem Passwort erreichbar.
- [ ] Ein Test-Download landete in `/data/downloads`.

## 🔧 Wenn etwas schiefgeht

Zuerst die Gluetun-Logs: `kubectl logs -n media deploy/qbittorrent -c gluetun`

| Problem | Lösung |
|---------|--------|
| Pod hängt in `Init:0/1` | Gluetun kommt nicht ins VPN. Logs lesen. Häufig: falscher `WIREGUARD_PRIVATE_KEY` (neu versiegeln) oder kein Plus-Abo |
| `CreateContainerConfigError` | Secret `gluetun-protonvpn` fehlt → `kubectl get sealedsecret -n media`, ist die Application `secrets` synchron? |
| Kein `port forwarded` im Log | Beim Erzeugen der WireGuard-Konfiguration **NAT-PMP** vergessen → neue Konfiguration mit NAT-PMP erzeugen, Schlüssel neu versiegeln |
| Port wird nicht in qBittorrent eingetragen | „Authentifizierung für Clients auf localhost umgehen“ ist nicht aktiv. Danach Pod neu starten: `kubectl rollout restart deploy/qbittorrent -n media` |
| Login über die Tailscale-Adresse klappt nicht (`Unauthorized`) | Reverse-Proxy-Unterstützung und vertrauenswürdige Proxys (Schritt 5) prüfen, notfalls wieder per `port-forward` einloggen |
| `adding IPv6 rule: file exists` | Siehe `postStart` im Deployment. Hilft das nicht: `kubectl delete pod -n media -l app=qbittorrent` |
| Sehr langsame Downloads | Port-Forwarding aktiv? Anderes Land in `SERVER_COUNTRIES` probieren |

## 🎓 Was du gelernt hast

- Container in einem Pod teilen sich das **Netzwerk**. Ein **Sidecar** kann es für die Haupt-App einrichten.
- **Native Sidecars** (`initContainers` mit `restartPolicy: Always`) starten zuerst und laufen mit, zusammen mit einer
  `startupProbe` garantiert das die Reihenfolge.
- **Capabilities** geben einem Container gezielt einzelne Sonderrechte (`NET_ADMIN`).
- Gluetun sorgt mit seiner Firewall für einen **Kill-Switch** und trägt den **weitergeleiteten Port** automatisch ein.
- Mit `-c <container>` wählst du bei `logs` und `exec` den Container in einem Pod mit mehreren Containern.

---

⬅️ **Zurück:** [17 – Wie der *arr-Stack zusammenspielt](17-arr-ueberblick.md) · ➡️ **Weiter:** [19 – Prowlarr](19-prowlarr.md)
