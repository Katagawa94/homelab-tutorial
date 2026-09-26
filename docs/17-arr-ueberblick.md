# 17 – Wie der *arr-Stack zusammenspielt

> **Was du am Ende hast:** Du verstehst, welche App im *arr-Stack was tut, wie die Daten fließen und warum alle Apps
> dieselbe Platte unter demselben Pfad sehen müssen. Die gemeinsamen Einstellungen (Benutzer, Rechte, Zeitzone) sind im Cluster.
>
> ⏱️ **Zeit:** ca. 30 Minuten
>
> 🧠 **Neue Begriffe:** [*arr-Stack](glossar.md#medien), [Indexer](glossar.md#medien), [Hardlink](glossar.md#medien),
> [PUID/PGID](glossar.md#medien), umask, `envFrom`

---

> ⚖️ **Rechtlicher Hinweis:** Die Programme in diesem Teil sind Werkzeuge. Sie sind nicht verboten, das Herunterladen
> und Verbreiten urheberrechtlich geschützter Inhalte ohne Erlaubnis aber schon. In Deutschland drohen dafür Abmahnungen
> und Schadensersatzforderungen, **auch mit VPN**. Nutze den *arr-Stack nur für Inhalte, die du legal beziehen darfst:
> gemeinfreie Filme, Creative-Commons-Werke, Linux-Distributionen oder deine eigenen Medien. Das Tutorial verwendet in allen
> Beispielen ausschließlich solche Inhalte.

## Wer macht was?

| App | Aufgabe | Vergleich | Adresse im Tailnet |
|-----|---------|-----------|--------------------|
| **Seerr** | Wunschliste: „Ich möchte Film X sehen“ | der Bestellzettel | `https://seerr.<tailnet>.ts.net` |
| **Radarr** | verwaltet **Filme**: sucht, lädt, benennt, sortiert | der Film-Bibliothekar | `https://radarr.<tailnet>.ts.net` |
| **Sonarr** | dasselbe für **Serien**, Folge für Folge | der Serien-Bibliothekar | `https://sonarr.<tailnet>.ts.net` |
| **Prowlarr** | verwaltet die **Indexer** (Suchquellen) für Sonarr und Radarr | das Telefonbuch | `https://prowlarr.<tailnet>.ts.net` |
| **qBittorrent** | lädt herunter, **ausschließlich durch Proton VPN** | der Lieferwagen | `https://qbittorrent.<tailnet>.ts.net` |
| **Bazarr** | sucht passende **Untertitel** | der Übersetzer | `https://bazarr.<tailnet>.ts.net` |
| **Jellyfin** | spielt alles ab (Kapitel 11) | das Kino | kennst du schon |

## Der Weg eines Films

```
 1. Wunsch          2. Suche               3. Download                4. Einsortieren          5. Anschauen
┌───────┐        ┌────────┐  fragt    ┌──────────┐              ┌──────────────────┐     ┌──────────┐
│ Seerr │ ─────► │ Radarr │ ────────► │ Prowlarr │              │ /data/media/     │     │ Jellyfin │
└───────┘        └────────┘           └──────────┘              │  movies/Film/    │ ◄── │  zeigt   │
                     │  schickt Download   (Indexer)            └──────────────────┘     │  ihn an  │
                     ▼                                                   ▲               └──────────┘
               ┌─────────────┐   Proton VPN    ┌──────────────────┐     │ Hardlink
               │ qBittorrent │ ══════════════► │ /data/downloads/ │ ────┘ (Radarr)
               │ + Gluetun   │                 │  radarr/Film…    │
               └─────────────┘                 └──────────────────┘
                     │
                  Bazarr lädt Untertitel dazu, Jellyfin bekommt Bescheid und scannt neu
```

1. Du (oder jemand aus der Familie) wünschst dir in **Seerr** einen Film.
2. Seerr gibt den Wunsch an **Radarr** weiter. Radarr fragt über **Prowlarr** alle Indexer, wo es den Film gibt.
3. Radarr schickt das beste Ergebnis an **qBittorrent**. qBittorrent lädt nach `/data/downloads/`, und zwar **nur durch das VPN**.
4. Ist der Download fertig, legt Radarr den Film ordentlich benannt nach `/data/media/movies/` und sagt Jellyfin Bescheid.
5. **Bazarr** lädt passende Untertitel, und du schaust den Film in **Jellyfin**, auch auf dem Samsung-TV.

Die Apps reden dabei über **Service-Namen** miteinander (Kapitel 07): Radarr erreicht qBittorrent unter
`http://qbittorrent:8080`, denn beide liegen im Namespace `media`.

## Warum alle `/data` sehen müssen: Hardlinks

Nach dem Download liegt ein Film zweimal im Dateibaum:

- in `/data/downloads/radarr/…`: dort muss er bleiben, damit qBittorrent ihn weiter mit anderen teilen kann (*Seeding*)
- in `/data/media/movies/…`: dort findet ihn Jellyfin, sauber benannt

Würde Radarr die Datei **kopieren**, wäre sie doppelt auf der Platte. Bei 300 GB wäre das schnell ein Problem.
Stattdessen legt Radarr einen **Hardlink** an: einen zweiten Namen für **dieselben Daten**.

### Selbst ausprobieren

> 🐧 **In der VM** (`ssh homelab@k3s`)

```bash
cd /data/downloads
fallocate -l 1G test-original.bin          # eine 1-GB-Datei erzeugen
df -h /data | tail -1                      # Belegung merken
ln test-original.bin ../media/test-link.bin
df -h /data | tail -1                      # Belegung: unverändert!
ls -li test-original.bin ../media/test-link.bin
```

```
1310722 -rw-rw-r-- 2 homelab homelab 1073741824 Sep 27 10:12 test-original.bin
1310722 -rw-rw-r-- 2 homelab homelab 1073741824 Sep 27 10:12 ../media/test-link.bin
```

- Die erste Spalte (**Inode**) ist gleich: Beide Namen zeigen auf dieselben Daten.
- Die **2** nach den Rechten heißt: Die Daten haben zwei Namen.
- Löschst du einen Namen, bleiben die Daten unter dem anderen erhalten. Erst wenn beide weg sind, ist der Platz frei.

```bash
rm test-original.bin ../media/test-link.bin
```

**Hardlinks funktionieren nur innerhalb eines Dateisystems.** Deshalb:

- liegen Downloads und Medien auf **derselben** Platte (Kapitel 04),
- binden **alle** Apps denselben PVC `media-data` ein, und zwar **unter demselben Pfad `/data`** (Kapitel 11).

Hätte qBittorrent die Platte unter `/downloads` und Radarr unter `/movies` eingebunden, müsste Radarr kopieren,
weil es nicht erkennen könnte, dass beides auf derselben Platte liegt. Diese Regel aus den bekannten
[TRaSH Guides](https://trash-guides.info/) ist der häufigste Stolperstein beim *arr-Stack.

## Gemeinsame Einstellungen: eine ConfigMap für alle

Fast alle Apps in diesem Teil kommen als Images von **[LinuxServer.io](https://www.linuxserver.io/)**. Die sind im
Homelab-Bereich sehr verbreitet, weil sie alle gleich funktionieren:

| Variable | Wert | Bedeutung |
|----------|------|-----------|
| `PUID` / `PGID` | `1000` | Unter dieser Benutzer-/Gruppennummer arbeitet die App. Sie muss zu den Rechten auf `/data` passen (Kapitel 04) |
| `UMASK` | `002` | Neue Dateien sind für Besitzer **und Gruppe** schreibbar |
| `TZ` | `Europe/Berlin` | Zeitzone für Logs und Zeitpläne |

Statt diese vier Werte in jedes Deployment zu schreiben, stehen sie **einmal** in einer ConfigMap
([`kubernetes/apps/media/basis/configmap-env.yaml`](../kubernetes/apps/media/basis/configmap-env.yaml)):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: media-env
  namespace: media
data:
  PUID: "1000"
  PGID: "1000"
  UMASK: "002"
  TZ: Europe/Berlin
```

Jede App holt sie sich mit `envFrom`, wie das Secret in Kapitel 08:

```yaml
          envFrom:
            - configMapRef:
                name: media-env
```

> 💡 **Warum `"1000"` in Anführungszeichen?** In einer ConfigMap müssen alle Werte Text sein. Ohne Anführungszeichen
> würde YAML `1000` als Zahl lesen, und Kubernetes würde die ConfigMap ablehnen.

Die ConfigMap gehört zur Basis. Weil `media-basis` schon aktiv ist, rollt Argo CD sie mit dem nächsten Sync automatisch aus.
Prüfen:

```bash
kubectl get configmap media-env -n media -o yaml
```

(Falls sie fehlt: `git pull` und in Argo CD bei **media-basis** auf **Refresh** klicken.)

> 💡 **Warum laufen LinuxServer-Images nicht mit `runAsUser: 1000` wie Jellyfin?** Sie starten kurz als `root`, richten
> Rechte in `/config` ein und wechseln dann selbst zum Benutzer `PUID`. Das Ergebnis ist dasselbe, nur der Weg ist anders.

## Die Manifeste: überall dasselbe Muster

Jede App hat einen eigenen Ordner mit denselben vier Dateien, das Muster kennst du von Jellyfin:

```
kubernetes/apps/media/
├── basis/          ← Namespace, PV/PVC /data, ConfigMap media-env
├── jellyfin/
├── qbittorrent/    ← mit Gluetun (Kapitel 18)
├── prowlarr/
├── sonarr/
├── radarr/
├── bazarr/
└── seerr/
    ├── kustomization.yaml
    ├── pvc-config.yaml   ← Einstellungen/Datenbank der App (local-path)
    ├── deployment.yaml   ← die App, bindet config + /data ein
    ├── service.yaml      ← http://<app>:<port> im Cluster
    └── ingress.yaml      ← https://<app>.<tailnet>.ts.net
```

Anders als Jellyfin bekommen diese Apps **keinen** `LoadBalancer`: Sie sind nur im Tailnet erreichbar. Der Samsung-TV braucht sie nicht.

| App | Port | Liest/schreibt `/data`? |
|-----|------|-------------------------|
| qBittorrent | 8080 | ✅ schreibt nach `/data/downloads` |
| Prowlarr | 9696 | ❌ braucht keine Dateien |
| Sonarr | 8989 | ✅ `/data/downloads` → `/data/media/tv` |
| Radarr | 7878 | ✅ `/data/downloads` → `/data/media/movies` |
| Bazarr | 6767 | ✅ legt Untertitel neben die Videos |
| Seerr | 5055 | ❌ redet nur mit den anderen Apps |

## Platz im Blick behalten

300 GB sind schnell voll. Drei Gewohnheiten helfen:

1. **Belegung prüfen:** `ssh homelab@k3s df -h /data`
2. **Qualität bewusst wählen:** In Kapitel 20 stellst du Radarr und Sonarr auf 1080p statt 4K ein.
3. **Mindest-Freiplatz:** Radarr und Sonarr lassen sich so einstellen, dass sie bei weniger als z. B. 20 GB freiem Platz nichts mehr importieren.

Und wenn es eng wird: Kapitel 30 (SSD nachrüsten) macht die ganze HDD für Medien frei.

## Reihenfolge der nächsten Kapitel

Die Apps hängen voneinander ab, deshalb richten wir sie in dieser Reihenfolge ein:

```
18 qBittorrent + VPN  →  19 Prowlarr  →  20 Sonarr & Radarr  →  21 Bazarr & Seerr
   (Lieferwagen)         (Telefonbuch)     (Bibliothekare)         (Extras)
```

## ✅ Checkpoint

- [ ] Du kannst erklären, was Seerr, Radarr, Sonarr, Prowlarr, qBittorrent und Bazarr tun.
- [ ] Du hast einen Hardlink angelegt und gesehen, dass er keinen zusätzlichen Platz belegt.
- [ ] `kubectl get configmap media-env -n media` existiert.

## 🎓 Was du gelernt hast

- Der *arr-Stack ist eine Kette spezialisierter Apps, die über Service-Namen im Cluster miteinander reden.
- **Hardlinks** sparen Platz, funktionieren aber nur innerhalb eines Dateisystems. Deshalb sehen alle Apps `/data` unter demselben Pfad.
- **PUID/PGID/UMASK** sorgen dafür, dass alle Apps dieselben Dateien lesen und schreiben dürfen.
- Mit **`envFrom` + ConfigMap** lassen sich gemeinsame Einstellungen an einer Stelle pflegen.

---

⬅️ **Zurück:** [16 – GPU in Kubernetes](16-gpu-kubernetes.md) · ➡️ **Weiter:** [18 – qBittorrent + Proton VPN](18-qbittorrent-vpn.md)
