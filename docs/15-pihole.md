# 15 – Pi-hole

> **Was du am Ende hast:** Pi-hole filtert Werbung und Tracker für deine Geräte, zu Hause über das Heimnetz und
> unterwegs über Tailscale. Die Weboberfläche zeigt, welches Gerät wohin telefoniert.
>
> ⏱️ **Zeit:** ca. 45 Minuten
>
> 🧠 **Neue Begriffe:** [DNS](glossar.md#netzwerk), DNS-Werbeblocker, UDP/TCP, `externalTrafficPolicy`,
> Tailscale-DNS (Nameserver)

---

> 📸 **Snapshot-Routine:** Snapshot der VM anlegen (z. B. `vor-pihole`).

## Wie Pi-hole Werbung blockt

Jedes Gerät fragt vor jeder Verbindung einen **DNS-Server**: *„Welche IP hat `werbung.example.com`?“* (Kapitel 01).
Pi-hole ist so ein DNS-Server, mit einer langen Liste bekannter Werbe- und Tracking-Adressen:

```
 Handy: "Wo ist nachrichten.de?"          ──► Pi-hole ──► "93.184.x.x" ✅ (weitergereicht an Quad9)
 Handy: "Wo ist werbung.tracker.com?"     ──► Pi-hole ──► "0.0.0.0"   🚫 (gibt es nicht)
```

Die Werbung wird also gar nicht erst geladen, auf **allen** Geräten, die Pi-hole als DNS-Server nutzen, auch auf dem
Samsung-TV und in Apps, in denen kein Browser-Werbeblocker hilft.

> 💡 Pi-hole blockt nicht alles. Werbung, die von derselben Adresse kommt wie der eigentliche Inhalt (z. B. YouTube-Werbung),
> kann ein DNS-Filter nicht unterscheiden.

## Der Aufbau

| Was | Wie erreichbar | Datei |
|-----|----------------|-------|
| **DNS** (Port 53, UDP und TCP) | `192.168.178.11:53` im Heimnetz **und** `<Tailscale-IP der VM>:53` im Tailnet | [`service-dns.yaml`](../kubernetes/apps/pihole/service-dns.yaml) |
| **Weboberfläche** | `https://pihole.<tailnet>.ts.net/admin` | [`service-web.yaml`](../kubernetes/apps/pihole/service-web.yaml) + [`ingress.yaml`](../kubernetes/apps/pihole/ingress.yaml) |
| Einstellungen, Listen, Statistik | PVC `pihole-config` (Systemplatte) | [`pvc-config.yaml`](../kubernetes/apps/pihole/pvc-config.yaml) |

Neu ist der DNS-Service:

```yaml
spec:
  type: LoadBalancer              # k3s ServiceLB öffnet Port 53 auf der VM
  externalTrafficPolicy: Local    # damit Pi-hole die echten Geräte-Adressen sieht
  ports:
    - name: dns-udp
      port: 53
      protocol: UDP               # normale DNS-Anfragen
    - name: dns-tcp
      port: 53
      protocol: TCP               # große Antworten
```

- DNS benutzt meistens **UDP** (schnelle, kleine Pakete ohne Verbindungsaufbau), für große Antworten **TCP**. Bisher
  hatten alle Services nur TCP. Hier braucht es beide.
- **`externalTrafficPolicy: Local`**: Normalerweise schreibt Kubernetes beim Weiterleiten seine eigene Adresse als
  Absender in die Pakete. Pi-hole sähe dann alle Anfragen von einem einzigen Gerät kommen. Mit `Local` bleibt die
  Absenderadresse erhalten, und die Statistik zeigt deine echten Geräte.

Die wichtigsten Einstellungen im [`deployment.yaml`](../kubernetes/apps/pihole/deployment.yaml):

```yaml
            - name: FTLCONF_webserver_api_password   # Passwort der Weboberfläche
              valueFrom:
                secretKeyRef:
                  name: pihole-secrets
                  key: WEB_PASSWORD
            - name: FTLCONF_dns_listeningMode
              value: ALL
            - name: FTLCONF_dns_upstreams
              value: 9.9.9.9;149.112.112.112
```

- **`listeningMode: ALL`**: Pi-hole beantwortet Anfragen aus allen Netzen (Heimnetz, Tailnet, Cluster). Von außen kommt
  trotzdem niemand heran, denn dein Router lässt keine Anfragen aus dem Internet herein.
- **`upstreams`**: Erlaubte Anfragen reicht Pi-hole an **Quad9** weiter, einen datenschutzfreundlichen DNS-Dienst aus der
  Schweiz. Du kannst auch deinen Router eintragen (`192.168.178.1`).

## 1. Die VM unabhängig von Pi-hole halten

Wichtig, bevor Pi-hole läuft: Die VM selbst und Proxmox dürfen **nicht** Pi-hole als DNS benutzen. Sonst beißt sich die
Katze in den Schwanz: Startet die VM neu, ist Pi-hole noch nicht da, k3s kann keine Images laden, also startet Pi-hole
nicht …

> 🐧 **In der VM** (`ssh homelab@k3s`)

Erstens: Tailscale soll der VM keinen DNS-Server vorgeben (das wird in Schritt 5 wichtig):

```bash
sudo tailscale set --accept-dns=false
```

Zweitens: Ubuntu betreibt einen kleinen eigenen DNS-Zwischenspeicher auf Port 53 (`127.0.0.53`). Den schalten wir ab,
damit es auf Port 53 der VM keine Überschneidung mit Pi-hole gibt. Die VM fragt danach direkt deinen Router:

```bash
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nDNSStubListener=no\n' | sudo tee /etc/systemd/resolved.conf.d/kein-stub.conf
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved
```

Test, ob die VM noch Namen auflösen kann:

```bash
cat /etc/resolv.conf | grep nameserver     # → nameserver 192.168.178.1 (dein Router)
getent hosts github.com                     # → eine IP-Adresse
```

> 🟧 **Auf Proxmox** genauso: `tailscale set --accept-dns=false`

## 2. Passwort versiegeln

> 💻 **Auf deinem Rechner.** Passwort für die Weboberfläche ausdenken → Passwortmanager:

```bash
mkdir -p kubernetes/secrets/pihole
kubectl create secret generic pihole-secrets -n pihole \
  --from-literal=WEB_PASSWORD='<PASSWORT>' \
  --dry-run=client -o yaml \
| kubeseal --format yaml > kubernetes/secrets/pihole/pihole-secrets.yaml
```

## 3. Aktivieren

```bash
cp kubernetes/katalog/pihole.yaml kubernetes/aktiv/
git add kubernetes/aktiv/pihole.yaml kubernetes/secrets/pihole/
git commit -m "Pi-hole aktivieren"
git push
```

```bash
kubectl get pods,svc -n pihole
```

```
NAME                          READY   STATUS    RESTARTS   AGE
pod/pihole-7c8d9f6b5d-q2m4x   1/1     Running   0          1m

NAME                 TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)                     AGE
service/pihole-dns   LoadBalancer   10.43.17.201   192.168.178.11   53:31553/UDP,53:31553/TCP   1m
service/pihole-web   ClusterIP      10.43.96.12    <none>           80/TCP                      1m
```

### Testen, bevor es jemand benutzt

> 💻 **Auf deinem Rechner**, direkt bei Pi-hole nachfragen:

```bash
nslookup github.com 192.168.178.11            # → eine echte IP
nslookup doubleclick.net 192.168.178.11       # → 0.0.0.0, geblockt 🎉
```

(`nslookup` gehört unter NixOS zum Paket `dnsutils` bzw. `bind`. Alternativ: `dig @192.168.178.11 doubleclick.net`.)

Öffne <https://pihole.tail1a2b3c.ts.net/admin> und melde dich mit dem Passwort aus Schritt 2 an. Unter **Query Log**
siehst du deine Testanfragen.

## 4. Pi-hole benutzen: drei Wege

Bis jetzt fragt noch kein Gerät Pi-hole. Es gibt drei Wege, das zu ändern. Fang klein an:

| Weg | Wirkt für | Rückgängig machen |
|-----|-----------|-------------------|
| **A: Einzelnes Gerät** | nur dieses Gerät, im Heimnetz | DNS-Einstellung zurücksetzen |
| **B: Tailscale-DNS** | alle deine Geräte im Tailnet, **auch unterwegs** | ein Schalter in der Admin-Konsole |
| **C: Router** | alle Geräte im Heimnetz, auch Gäste und der Samsung-TV | Einstellung im Router zurücksetzen |

### A: Ein Gerät zum Ausprobieren

Trag am Handy oder Laptop im WLAN als DNS-Server `192.168.178.11` ein (bei Android unter *Privates DNS* geht das nicht,
dort muss die WLAN-Einstellung auf *Statisch* stehen). Surf ein paar Minuten und schau ins **Query Log**.

### B: Alle Tailnet-Geräte, auch unterwegs (empfohlen)

1. Tailscale-IP der VM nachsehen: `tailscale ip -4 k3s` (z. B. `100.101.102.104`).
2. [Admin-Konsole → DNS](https://login.tailscale.com/admin/dns) → **Nameservers → Add nameserver → Custom…**
   → die Tailscale-IP der VM eintragen → **Save**.
3. Den Schalter **Override local DNS** einschalten.

Jetzt fragen alle Geräte mit aktivem Tailscale (Laptop, Handy …) Pi-hole, egal ob im WLAN zu Hause, im Café oder im
Mobilfunk. MagicDNS-Namen wie `k3s` funktionieren weiterhin, die beantwortet Tailscale selbst.

### C: Das ganze Heimnetz über den Router

Der Router teilt den Geräten per DHCP mit, welchen DNS-Server sie benutzen sollen. Bei der FRITZ!Box:
**Heimnetz → Netzwerk → Netzwerkeinstellungen → IPv4-Einstellungen → Lokaler DNS-Server:** `192.168.178.11`.
Danach Geräte neu verbinden (WLAN aus/an), damit sie die neue Einstellung übernehmen.

> ⚠️ **Bedenke bei B und C:** Fällt Pi-hole aus (Server aus, Update, Fehler), funktioniert für die betroffenen Geräte
> **kein Internet mehr**, weil keine Namen mehr aufgelöst werden. Kurzfristige Abhilfe: bei B den Schalter *Override local DNS*
> ausschalten, bei C im Router den DNS-Eintrag leeren. Uptime Kuma (Kapitel 28) warnt dich, wenn Pi-hole ausfällt.

## 5. Feinschliff

- **Weitere Blocklisten:** **Lists** in der Weboberfläche. Die Standardliste ist ein guter Anfang. Mehr Listen blocken
  mehr, machen aber auch häufiger etwas kaputt.
- **Eine Seite funktioniert nicht mehr?** Im **Query Log** die geblockte Adresse suchen → **Allow**. Typische Kandidaten
  sind Links in Newslettern (Tracking-Weiterleitungen) und manche Shopping-Seiten.
- **Gerätenamen statt IPs:** Unter **Settings → DNS → Conditional forwarding** den Router eintragen (`192.168.178.0/24`,
  `192.168.178.1`, Domain `fritz.box`). Dann zeigt Pi-hole die Namen, die dein Router kennt.

## ✅ Checkpoint

- [ ] In der VM zeigt `cat /etc/resolv.conf` den Router als Nameserver, nicht `127.0.0.53` und nicht Pi-hole.
- [ ] `nslookup doubleclick.net 192.168.178.11` liefert `0.0.0.0`.
- [ ] `https://pihole.<tailnet>.ts.net/admin` ist erreichbar.
- [ ] Mindestens ein Gerät benutzt Pi-hole (Weg A, B oder C), seine Anfragen erscheinen im Query Log.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| `EXTERNAL-IP` von `pihole-dns` bleibt `<pending>` | Port 53 ist auf der VM belegt. Schritt 1 (Stub-Listener) erledigt? In der VM: `sudo ss -lunp \| grep :53` |
| `nslookup` → `connection timed out` | Läuft der Pod? `kubectl get pods -n pihole`. Logs: `kubectl logs -n pihole deploy/pihole` |
| Alle Anfragen kommen scheinbar von einer `10.42.x.x`-Adresse | `externalTrafficPolicy: Local` greift nicht. Für die Funktion egal, nur die Statistik ist weniger aussagekräftig |
| Nach Weg B geht unterwegs kein Internet mehr | Ist die VM erreichbar (`tailscale ping k3s`)? Notfalls in der Admin-Konsole *Override local DNS* ausschalten |
| Die VM kann nach einem Neustart keine Images laden | Die VM benutzt doch Pi-hole als DNS. Schritt 1 prüfen: `tailscale set --accept-dns=false`, `/etc/resolv.conf` |
| Login in die Weboberfläche klappt nicht | Secret `pihole-secrets` vorhanden? `kubectl get secret -n pihole` |

## 🎓 Was du gelernt hast

- Pi-hole blockt Werbung, indem es als **DNS-Server** für Werbe-Adressen keine Antwort liefert.
- Ein Service kann mehrere Protokolle bedienen: DNS braucht **UDP und TCP** auf Port 53.
- **`externalTrafficPolicy: Local`** erhält die Absenderadresse der Clients.
- Mit einem **Tailscale-Nameserver** wirkt Pi-hole auf allen deinen Geräten, auch unterwegs.
- Infrastruktur, von der alles abhängt (die VM selbst), darf **nicht** von einer App im Cluster abhängen.

---

## 🎉 Teil D geschafft!

Die drei wichtigsten Dienste laufen: **Passwörter** (Vaultwarden), **Dateien, Kalender, Kontakte** (Nextcloud) und
**Werbeblocker** (Pi-hole). In **Teil E** kommt das Heimkino dazu: Jellyfin, der Samsung-TV, die Grafikkarte und der
*arr-Stack.

---

⬅️ **Zurück:** [14 – Nextcloud](14-nextcloud.md) · ➡️ **Weiter:** [16 – Jellyfin](16-jellyfin.md)
