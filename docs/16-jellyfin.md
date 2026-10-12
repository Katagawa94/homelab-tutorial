# 16 – Jellyfin

> **Was du am Ende hast:** Jellyfin läuft im Cluster, liest deine Filme und Serien von `/data/media` und ist
> erreichbar unter `http://192.168.178.11:8096` (Heimnetz) und unter `https://jellyfin.<tailnet>.ts.net` (von überall).
>
> ⏱️ **Zeit:** ca. 1 Stunde
>
> 🧠 **Neue Begriffe:** gemeinsam genutztes [PersistentVolume](glossar.md#container--kubernetes) (`ReadWriteMany`),
> readinessProbe, `securityContext`, `emptyDir`, `readOnly`

---

> 📸 **Snapshot-Routine:** Snapshot der VM anlegen (z. B. `vor-jellyfin`).

## Überblick

Jellyfin besteht aus zwei Teilen, die in zwei Ordnern liegen:

```
kubernetes/apps/media/
├── basis/                  ← gemeinsam für ALLE Medien-Apps (Jellyfin, später Sonarr, Radarr …)
│   ├── kustomization.yaml
│   ├── namespace.yaml      ← Namespace "media"
│   ├── pv-data.yaml        ← PersistentVolume: die Platte /data der VM
│   └── pvc-data.yaml       ← PVC "media-data", den alle Medien-Apps einbinden
└── jellyfin/
    ├── kustomization.yaml
    ├── pvc-config.yaml     ← Speicher für Jellyfins Einstellungen
    ├── deployment.yaml     ← Jellyfin selbst
    ├── service.yaml        ← Heimnetz: http://<VM-IP>:8096
    ├── ingress.yaml        ← Tailnet: https://jellyfin.<tailnet>.ts.net
    └── gpu-patch.yaml      ← kommt erst in Kapitel 19 zum Einsatz
```

Das Muster kennst du von Vaultwarden (Kapitel 13), das handgemachte PersistentVolume von Nextcloud (Kapitel 14).
Neu ist, dass sich **mehrere Apps** ein PV teilen, und dass Jellyfin zusätzlich **im Heimnetz** erreichbar ist (für den Samsung-TV).

## 1. Die Medien-Platte als PersistentVolume

Wie bei Nextcloud (Kapitel 14) liegen die Daten auf der Datenplatte, hier unter `/data` selbst, also inklusive
`/data/media` und `/data/downloads`. Und wieder schreiben wir das **PV selbst**:
Deshalb schreiben wir das **PV selbst**:

```yaml
# kubernetes/apps/media/basis/pv-data.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: media-data
spec:
  capacity:
    storage: 300Gi                # nur eine Angabe; hostPath prüft die Größe nicht
  accessModes:
    - ReadWriteMany               # mehrere Pods (Jellyfin, Sonarr, qBittorrent …) teilen sich /data
  persistentVolumeReclaimPolicy: Retain   # NIEMALS automatisch löschen!
  storageClassName: ""            # kein automatischer Lieferdienst, dieses PV ist handgemacht
  claimRef:                       # reserviert dieses PV für genau einen PVC
    namespace: media
    name: media-data
  hostPath:
    path: /data                   # der Ordner auf der VM (Kapitel 04)
    type: Directory               # muss bereits existieren
```

| Feld | Bedeutung |
|------|-----------|
| `hostPath` | Das PV ist einfach ein Ordner auf dem Node, hier `/data` |
| `persistentVolumeReclaimPolicy: Retain` | Wird der PVC gelöscht, bleiben die Daten **erhalten** (im Gegensatz zu `Delete` bei `local-path`) |
| `storageClassName: ""` | Leer heißt: Hier liefert kein Automat, das PV ist handgemacht |
| `claimRef` | Dieses PV ist für den PVC `media-data` im Namespace `media` reserviert. Kein anderer PVC kann es sich schnappen |
| `ReadWriteMany` | Mehrere Pods dürfen gleichzeitig darauf zugreifen |

Der passende PVC:

```yaml
# kubernetes/apps/media/basis/pvc-data.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: media-data
  namespace: media
  annotations:
    argocd.argoproj.io/sync-options: Prune=false   # Argo CD darf diesen PVC nie löschen
spec:
  storageClassName: ""
  volumeName: media-data          # genau dieses PV verwenden
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 300Gi
```

(Die Annotation `Prune=false` kennst du aus Kapitel 13.)

> 💡 **Warum ein gemeinsamer PVC für alle Medien-Apps?** Jellyfin, Sonarr, Radarr und qBittorrent sollen dieselben
> Dateien unter demselben Pfad `/data` sehen. Nur dann funktionieren später die Hardlinks (Kapitel 20).

## 2. Zwei Ordner, zwei Applications

Warum liegen `basis/` und `jellyfin/` getrennt? Weil die Basis (Namespace `media`, PV, PVC und später eine gemeinsame
ConfigMap) **allen** Medien-Apps gehört: Jellyfin, qBittorrent, Sonarr, Radarr … Hätte jede App die Basis in ihrer
eigenen `kustomization.yaml`, würden mehrere Argo-CD-Applications um dieselben Objekte streiten. Deshalb gibt es im
Katalog zwei Einträge: `media-basis.yaml` und `jellyfin.yaml`.

Eine Neuerung in der `kustomization.yaml` von Jellyfin kommt erst in Kapitel 19 zum Einsatz: ein **Patch**, der das
Deployment um die Grafikkarte ergänzt, ohne die Originaldatei anzufassen.

## 3. Das Jellyfin-Deployment

Die wichtigsten Stellen aus [`deployment.yaml`](../kubernetes/apps/media/jellyfin/deployment.yaml):

```yaml
spec:
  strategy:
    type: Recreate                # Datenbank! Nie zwei Jellyfins gleichzeitig
  template:
    spec:
      securityContext:
        runAsUser: 1000           # als Benutzer 1000 laufen, dem gehört /data (Kapitel 04)
        runAsGroup: 1000
      containers:
        - name: jellyfin
          image: jellyfin/jellyfin:12.1
          volumeMounts:
            - name: config
              mountPath: /config
            - name: cache
              mountPath: /cache
            - name: data
              mountPath: /data
              readOnly: true      # Jellyfin liest Medien nur, verändern darf es sie nicht
      volumes:
        - name: config            # Einstellungen, Datenbank, Cover → local-path-PVC
          persistentVolumeClaim:
            claimName: jellyfin-config
        - name: cache             # Zwischenspeicher fürs Transcoding, darf verloren gehen
          emptyDir:
            sizeLimit: 10Gi
        - name: data              # die Medien → der gemeinsame PVC aus basis/
          persistentVolumeClaim:
            claimName: media-data
```

| Volume | Art | Überlebt Neustart? | Inhalt |
|--------|-----|--------------------|--------|
| `/config` | PVC (`local-path`) | ✅ | Benutzer, Einstellungen, Datenbank, Cover |
| `/cache` | `emptyDir` | ❌ | temporäre Dateien beim Umwandeln von Videos |
| `/data` | PVC (handgemachtes PV) | ✅ | deine Filme und Serien, nur lesend |

Ein **`emptyDir`** ist ein leerer Ordner, der mit dem Pod entsteht und mit ihm verschwindet. Perfekt für Dinge, die man nicht aufheben muss.

Der **`securityContext`** legt fest, unter welchem Benutzer der Container läuft. `1000` ist die Nummer, der in Kapitel 04
`/data` übergeben wurde. So darf Jellyfin die Medien lesen, und alle späteren Apps benutzen dieselbe Nummer.

### Probes: Ist Jellyfin gesund?

Die Probes kennst du von Vaultwarden (Kapitel 13). Neu ist die **readinessProbe**:

```yaml
          readinessProbe:         # Erst wenn das klappt, bekommt der Pod Anfragen
            httpGet:
              path: /health
              port: http
            periodSeconds: 10
```

Jellyfin antwortet unter `/health` mit `Healthy`. Solange das nicht klappt, etwa während Jellyfin nach dem Start die
Bibliothek lädt, schickt der Service keine Anfragen an den Pod. Dein Samsung-TV bekommt dann eine kurze Fehlermeldung
statt einer hängenden Verbindung.

### Erreichbarkeit: Service und Ingress

```yaml
# service.yaml: Heimnetz (Samsung-TV) und intern
spec:
  type: LoadBalancer
  ports:
    - name: http
      port: 8096
      targetPort: http
```

```yaml
# ingress.yaml: Tailnet mit HTTPS (Kapitel 10)
spec:
  ingressClassName: tailscale
  defaultBackend:
    service:
      name: jellyfin
      port:
        number: 8096
  tls:
    - hosts:
        - jellyfin
```

Ein Service vom Typ `LoadBalancer` ist gleichzeitig eine `ClusterIP`. Deshalb reicht ein einziger Service für
Heimnetz, Ingress und später die anderen Medien-Apps (`http://jellyfin.media:8096`).

## 4. Ausrollen

> 💻 **Auf deinem Rechner** (im Ordner `homelab-tutorial`)

Wie gewohnt per Git, Basis und Jellyfin zusammen:

```bash
cp kubernetes/katalog/{media-basis,jellyfin}.yaml kubernetes/aktiv/
git add kubernetes/aktiv/
git commit -m "Jellyfin aktivieren"
git push
```

In Argo CD **root → Refresh**. Es erscheinen die Kacheln **media-basis** und **jellyfin**. Die Basis prüfen:

```bash
kubectl get pv,pvc -n media
```

```
NAME                          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM              STORAGECLASS   ...
persistentvolume/media-data   300Gi      RWX            Retain           Bound    media/media-data                  ...

NAME                                    STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS   ...
persistentvolumeclaim/jellyfin-config   Bound    pvc-…        10Gi       RWO            local-path     ...
persistentvolumeclaim/media-data        Bound    media-data   300Gi      RWX                           ...
```

`media-data` ist sofort **`Bound`**, weil PV und PVC sich über `claimRef` und `volumeName` gegenseitig gefunden haben.

Beobachte den Start. Der erste Download des Images (ca. 1 GB) dauert etwas:

```bash
kubectl get pods -n media -w
```

```
NAME                        READY   STATUS              RESTARTS   AGE
jellyfin-5f7d8c9b6f-xk2lp   0/1     ContainerCreating   0          10s
jellyfin-5f7d8c9b6f-xk2lp   0/1     Running             0          95s
jellyfin-5f7d8c9b6f-xk2lp   1/1     Running             0          2m
```

Zwischen `0/1 Running` und `1/1 Running` hat die **startupProbe** gewartet, bis Jellyfin bereit war.

```bash
kubectl get service,ingress -n media
```

```
NAME               TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)          AGE
service/jellyfin   LoadBalancer   10.43.88.140   192.168.178.11   8096:30512/TCP   2m

NAME                                 CLASS       HOSTS   ADDRESS                      PORTS     AGE
ingress.networking.k8s.io/jellyfin   tailscale   *       jellyfin.tail1a2b3c.ts.net   80, 443   2m
```

## 5. Testfilm besorgen

Damit Jellyfin etwas anzeigen kann, laden wir einen freien Film: **Big Buck Bunny** (Blender Foundation, Creative Commons).

> 🐧 **In der VM** (`ssh homelab@k3s`)

```bash
mkdir -p "/data/media/movies/Big Buck Bunny (2008)"
wget -O "/data/media/movies/Big Buck Bunny (2008)/Big Buck Bunny (2008).mov" \
  https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_1080p_h264.mov
```

Weil du als `homelab` (Nummer 1000) arbeitest, gehören die Dateien automatisch dem richtigen Benutzer.

### So benennst du Medien für Jellyfin

Jellyfin erkennt Filme und Serien am Ordner- und Dateinamen:

```
/data/media/
├── movies/
│   └── Big Buck Bunny (2008)/
│       └── Big Buck Bunny (2008).mov
└── tv/
    └── Serienname (2020)/
        └── Season 01/
            ├── Serienname S01E01.mkv
            └── Serienname S01E02.mkv
```

### Eigene Medien übertragen

> 💻 **Auf deinem Rechner:** Mit `rsync` über Tailscale (funktioniert auch von unterwegs):

```bash
rsync -avP "Mein Film (2020).mkv" "homelab@k3s:/data/media/movies/Mein Film (2020)/"
```

`-P` zeigt den Fortschritt und kann abgebrochene Übertragungen fortsetzen.

## 6. Jellyfin einrichten

Öffne <https://jellyfin.tail1a2b3c.ts.net> (oder im Heimnetz <http://192.168.178.11:8096>). Der Einrichtungsassistent startet:

| Schritt | Eingabe |
|---------|---------|
| Sprache | Deutsch |
| Benutzer | Benutzername und Passwort für den Admin → Passwortmanager |
| Medienbibliotheken | **Hinzufügen** → Typ **Filme**, Ordner **`/data/media/movies`** · noch einmal: Typ **Serien**, Ordner **`/data/media/tv`** |
| Metadaten-Sprache | Deutsch / Deutschland |
| Fernzugriff | **Fernzugriff erlauben** ☑ · **Automatische Portzuordnung** ☐ |

> 💡 **Welche Pfade sieht Jellyfin?** Jellyfin kennt nur die Pfade *im Container*. Weil wir `/data` der VM unter `/data`
> im Container eingebunden haben, sind die Pfade zufällig identisch. Das ist Absicht, denn es macht die Fehlersuche viel einfacher.

Nach dem Login erscheint nach kurzer Zeit **Big Buck Bunny** mit Cover und Beschreibung. Klick auf ▶️, und der Film läuft im Browser. 🎬

## 7. Der Härtetest

Lösche den Pod und schau, was bleibt:

```bash
kubectl delete pod -n media -l app=jellyfin
kubectl get pods -n media -w
```

Sobald der neue Pod `1/1 Running` ist: Seite neu laden. Du bist noch angemeldet, Bibliotheken und Film sind noch da.
Einstellungen stecken im PVC `jellyfin-config`, die Filme auf `/data`.

## ✅ Checkpoint

- [ ] `kubectl get pv,pvc -n media` zeigt `media-data` und `jellyfin-config` als `Bound`.
- [ ] `kubectl get pods -n media` zeigt Jellyfin als `1/1 Running`.
- [ ] <http://192.168.178.11:8096> öffnet Jellyfin im Heimnetz.
- [ ] `https://jellyfin.<tailnet>.ts.net` öffnet Jellyfin, auch vom Handy über Mobilfunk.
- [ ] Big Buck Bunny lässt sich abspielen.
- [ ] Nach dem Löschen des Pods sind Einstellungen und Bibliothek noch da.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| PVC `media-data` bleibt `Pending` | `kubectl describe pvc media-data -n media`. Stimmen `volumeName`, `claimRef` und `storageClassName: ""` überein? |
| Pod: `hostPath type check failed: /data is not a directory` | `/data` ist in der VM nicht eingebunden → `df -h /data` in der VM, siehe Kapitel 04 |
| Pod startet immer wieder neu (`RESTARTS` steigt) | `kubectl describe pod -n media -l app=jellyfin`: Steht bei den Events `Startup probe failed`? Bei vielen Medien kann der erste Start lange dauern → `failureThreshold` erhöhen |
| `OOMKilled` | RAM-Limit erhöhen (`limits.memory` im Deployment) |
| Jellyfin findet keine Filme | Pfad richtig (`/data/media/movies`)? Dateinamen wie oben? Rechte prüfen: `ls -ln /data/media/movies` muss `1000 1000` zeigen. Dann **Dashboard → Bibliotheken → Alle Bibliotheken scannen** |
| `EXTERNAL-IP` bleibt `<pending>` | Port 8096 ist schon belegt → `kubectl get svc -A \| grep 8096` |
| Tailscale-Adresse geht nicht | Logs des Operators prüfen (Kapitel 10) |

## 🎓 Was du gelernt hast

- Ein **handgemachtes PV** mit `ReadWriteMany` kann von mehreren Apps gleichzeitig genutzt werden. Die gemeinsame Basis bekommt deshalb eine eigene Application.
- Volumes haben verschiedene Lebensdauern: PVC (bleibt), `emptyDir` (lebt mit dem Pod).
- Die **readinessProbe** hält Anfragen von einem Pod fern, solange er nicht bereit ist.
- Der **`securityContext`** legt den Benutzer fest. Die Nummer 1000 passt zu den Rechten auf `/data`.
- Eine App kann gleichzeitig im Heimnetz (`LoadBalancer`) und im Tailnet (Ingress) erreichbar sein.

---

⬅️ **Zurück:** [15 – Pi-hole](15-pihole.md) · ➡️ **Weiter:** [17 – Jellyfin auf dem Samsung-TV](17-samsung-tv.md)
