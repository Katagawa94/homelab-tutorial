# 11 – Jellyfin

> **Was du am Ende hast:** Jellyfin läuft im Cluster, liest deine Filme und Serien von `/data/media` und ist
> erreichbar unter `http://192.168.178.11:8096` (Heimnetz) und unter `https://jellyfin.<tailnet>.ts.net` (von überall).
>
> ⏱️ **Zeit:** ca. 1 Stunde
>
> 🧠 **Neue Begriffe:** statisches [PersistentVolume](glossar.md#container--kubernetes), [hostPath](glossar.md#container--kubernetes),
> Reclaim Policy, [Kustomize](glossar.md#container--kubernetes), [Probes](glossar.md#container--kubernetes), `securityContext`, `emptyDir`

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
    └── gpu-patch.yaml      ← kommt erst in Kapitel 16 zum Einsatz
```

Fast alles davon kennst du aus Teil B. Neu sind drei Dinge: ein **handgemachtes PersistentVolume**, **Kustomize** und **Probes**.

## 1. Die Medien-Platte als PersistentVolume

In Kapitel 08 hat die StorageClass `local-path` automatisch einen Ordner angelegt. Für unsere Medien wollen wir das
nicht: Die Filme liegen bereits auf der 300-GB-Platte unter `/data` (Kapitel 04), und dort sollen sie auch bleiben.
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

(Die Annotation `argocd.argoproj.io/…` spielt erst ab Kapitel 13 eine Rolle.)

> 💡 **Warum ein gemeinsamer PVC für alle Medien-Apps?** Jellyfin, Sonarr, Radarr und qBittorrent sollen dieselben
> Dateien unter demselben Pfad `/data` sehen. Nur dann funktionieren später die Hardlinks (Kapitel 17).

## 2. Kustomize: mehrere Dateien als Einheit

In jedem Ordner liegt eine `kustomization.yaml`. Sie zählt auf, welche Dateien zusammengehören:

```yaml
# kubernetes/apps/media/basis/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - pv-data.yaml
  - pvc-data.yaml
```

**Kustomize** ist in `kubectl` eingebaut. Statt `-f` (Datei/Ordner) schreibst du `-k` (Kustomization):

```bash
kubectl kustomize kubernetes/apps/media/basis     # nur anzeigen, was herauskommt
kubectl apply -k kubernetes/apps/media/basis      # anwenden
```

Kustomize kann aber mehr als nur auflisten: In der `kustomization.yaml` von Jellyfin steht `namespace: media`. Damit
landen automatisch alle Objekte in diesem Namespace, ohne dass es in jeder Datei stehen muss. Und in Kapitel 16 nutzen
wir Kustomize, um das Deployment um die Grafikkarte zu **ergänzen** (ein *Patch*), ohne die Originaldatei anzufassen.

> 💡 **Kustomize oder Helm?** Beide erzeugen am Ende normale Manifeste. **Helm** nutzen wir für fertige Pakete anderer
> Leute (Tailscale Operator, Argo CD), **Kustomize** für unsere eigenen Manifeste. So bleibt alles lesbar.

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

```yaml
          startupProbe:           # Wartet, bis Jellyfin hochgefahren ist (bis zu 5 Minuten)
            httpGet:
              path: /health
              port: http
            periodSeconds: 10
            failureThreshold: 30
          readinessProbe:         # Erst wenn das klappt, bekommt der Pod Anfragen
            httpGet:
              path: /health
              port: http
            periodSeconds: 10
          livenessProbe:          # Klappt das 3x hintereinander nicht, wird Jellyfin neu gestartet
            httpGet:
              path: /health
              port: http
            periodSeconds: 30
            failureThreshold: 3
```

Jellyfin antwortet unter `/health` mit `Healthy`. Kubernetes fragt dort regelmäßig nach:

| Probe | Frage | Bei „Nein“ |
|-------|-------|------------|
| **startupProbe** | „Bist du schon hochgefahren?“ | weiter warten (hier bis zu 30 × 10 s) |
| **readinessProbe** | „Kannst du gerade Anfragen annehmen?“ | Service schickt keine Anfragen an diesen Pod |
| **livenessProbe** | „Lebst du noch?“ | Container wird neu gestartet |

So erkennt Kubernetes auch eine App, die zwar läuft, aber hängt. Gegen solche Fälle hilft die Selbstheilung aus Kapitel 07 allein nicht.

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

Erst die Basis:

```bash
kubectl apply -k kubernetes/apps/media/basis
kubectl get pv,pvc -n media
```

```
NAME                          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM              STORAGECLASS   ...
persistentvolume/media-data   300Gi      RWX            Retain           Bound    media/media-data                  ...

NAME                               STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS   ...
persistentvolumeclaim/media-data   Bound    media-data   300Gi      RWX                           ...
```

Beide sind sofort **`Bound`**, weil PV und PVC sich über `claimRef` und `volumeName` gegenseitig gefunden haben.

Dann Jellyfin. Schau dir vorher an, was Kustomize erzeugt:

```bash
kubectl kustomize kubernetes/apps/media/jellyfin | less
kubectl apply -k kubernetes/apps/media/jellyfin
```

```
service/jellyfin created
persistentvolumeclaim/jellyfin-config created
deployment.apps/jellyfin created
ingress.networking.k8s.io/jellyfin created
```

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
| Pod startet immer wieder neu (`RESTARTS` steigt) | `kubectl describe pod -n media -l app=jellyfin`: Steht bei den Events `Startup probe failed`? Auf der HDD kann der erste Start lange dauern → `failureThreshold` erhöhen |
| `OOMKilled` | RAM-Limit erhöhen (`limits.memory` im Deployment) |
| Jellyfin findet keine Filme | Pfad richtig (`/data/media/movies`)? Dateinamen wie oben? Rechte prüfen: `ls -ln /data/media/movies` muss `1000 1000` zeigen. Dann **Dashboard → Bibliotheken → Alle Bibliotheken scannen** |
| `EXTERNAL-IP` bleibt `<pending>` | Port 8096 ist schon belegt → `kubectl get svc -A \| grep 8096` |
| Tailscale-Adresse geht nicht | Logs des Operators prüfen (Kapitel 10) |

## 🎓 Was du gelernt hast

- Ein **handgemachtes PV** mit `hostPath` bindet einen vorhandenen Ordner ein. `Retain` schützt die Daten, `claimRef` reserviert das PV.
- **Kustomize** fasst Manifeste zusammen (`kubectl apply -k`) und kann z. B. den Namespace für alle setzen.
- Volumes haben verschiedene Lebensdauern: PVC (bleibt), `emptyDir` (lebt mit dem Pod).
- **Probes** lassen Kubernetes erkennen, ob eine App bereit und gesund ist.
- Der **`securityContext`** legt den Benutzer fest. Die Nummer 1000 passt zu den Rechten auf `/data`.
- Eine App kann gleichzeitig im Heimnetz (`LoadBalancer`) und im Tailnet (Ingress) erreichbar sein.

---

⬅️ **Zurück:** [10 – Tailscale Operator](10-tailscale-operator.md) · ➡️ **Weiter:** [12 – Jellyfin auf dem Samsung-TV](12-samsung-tv.md)
