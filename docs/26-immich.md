# 26 – Immich

> **Was du am Ende hast:** Die Fotos von deinem Handy werden automatisch in dein Homelab gesichert, mit Gesichtserkennung,
> Suche („Hund am Strand“) und Karten, ähnlich wie bei Google Fotos, aber bei dir. Optional läuft die Erkennung auf der Grafikkarte.
>
> ⏱️ **Zeit:** ca. 1–1,5 Stunden
>
> 🧠 **Neue Begriffe:** [Time-Slicing](glossar.md#container--kubernetes) (StatefulSet und `secretKeyRef` kennst du
> schon aus Kapitel 14)

---

> 📸 **Snapshot-Routine:** Snapshot der VM anlegen (bei ausgeschalteter VM).

## Aufbau: vier Teile

Immich ist die bisher größte App: Sie besteht aus **vier Komponenten**, die zusammenarbeiten:

```
 Handy-App / Browser
        │  https://immich.<tailnet>.ts.net
        ▼
┌─────────────────┐   Gesichter, Suche   ┌──────────────────────────┐
│  immich-server  │ ───────────────────► │ immich-machine-learning  │ (optional auf der GPU)
│  (Deployment)   │                      │ (Deployment)             │
└─────────────────┘                      └──────────────────────────┘
   │          │
   │          └─► immich-redis     (Deployment)   Warteschlange für Hintergrundaufgaben
   └────────────► immich-postgres  (StatefulSet)  Datenbank: Alben, Personen, Metadaten
   │
   └─► /data (im Container) = /data/photos (in der VM): die Fotos selbst
```

Die Komponenten finden sich über **Service-Namen**. Die stehen in einer gemeinsamen ConfigMap
([`configmap-env.yaml`](../kubernetes/apps/immich/configmap-env.yaml)):

```yaml
data:
  DB_HOSTNAME: immich-postgres    # Service-Name der Datenbank
  DB_USERNAME: postgres
  DB_DATABASE_NAME: immich
  REDIS_HOSTNAME: immich-redis    # Service-Name von Valkey
  TZ: Europe/Berlin
```

## Bekannt aus Nextcloud: StatefulSet und `secretKeyRef`

Der Aufbau ähnelt Nextcloud aus Kapitel 14, nur mit einer Komponente mehr:

- Die Datenbank läuft als **StatefulSet** ([`postgres.yaml`](../kubernetes/apps/immich/postgres.yaml)). Der Pod heißt
  fest `immich-postgres-0`, sein PVC `data-immich-postgres-0` entsteht aus den `volumeClaimTemplates`.
- Postgres erwartet das Passwort in `POSTGRES_PASSWORD`, Immich in `DB_PASSWORD`. Es liegt **einmal** im Secret
  `immich-db`, und Postgres holt sich den Wert per **`secretKeyRef`** unter anderem Namen:

```yaml
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:     # nur EINEN Wert aus einem Secret holen
                  name: immich-db
                  key: DB_PASSWORD
```

Der Server nimmt dagegen das ganze Secret per `envFrom`, wie gewohnt.

## Wo liegen die Fotos?

Fotos brauchen viel Platz, deshalb liegen sie auf der **großen Datenplatte** unter `/data/photos`. Sie werden wie die
Nextcloud-Dateien in Kapitel 14 über ein **handgemachtes PV** mit `Retain` eingebunden
([`pv-library.yaml`](../kubernetes/apps/immich/pv-library.yaml)). Datenbank und KI-Modelle liegen dagegen auf der
Systemplatte (`local-path`).

> ⚠️ **Wichtig:** Die Datenplatte ist vom Proxmox-Backup **ausgenommen** (Kapitel 04). Das ist für Filme richtig, für
> deine Fotos aber **nicht**. Das restic-Backup aus Kapitel 29 sichert deshalb `/data/photos` zusammen mit `/data/nextcloud`. Bis dahin:
> Lösch nichts vom Handy, was nur in Immich liegt.

## 1. Vorbereiten

> 🐧 **In der VM:**

```bash
sudo mkdir -p /data/photos
```

> 💻 **Auf deinem Rechner:** Ein zufälliges Datenbank-Passwort erzeugen und versiegeln (nur Buchstaben und Ziffern,
> so verlangt es Immich):

```bash
DBPW=$(openssl rand -hex 16)
mkdir -p kubernetes/secrets/immich
kubectl create secret generic immich-db -n immich \
  --from-literal=DB_PASSWORD="$DBPW" \
  --dry-run=client -o yaml \
| kubeseal --format yaml > kubernetes/secrets/immich/immich-db.yaml
unset DBPW
```

> 💡 Dieses Passwort musst du dir nicht merken. Es verbindet nur Immich mit seiner Datenbank. **Aber:** Postgres
> übernimmt es nur beim **allerersten Start**. Wenn du es später änderst, lehnt die bestehende Datenbank das neue
> Passwort ab. Also: einmal erzeugen, dann in Ruhe lassen.

## 2. Aktivieren

```bash
cp kubernetes/katalog/immich.yaml kubernetes/aktiv/
git add kubernetes/aktiv/immich.yaml kubernetes/secrets/immich/
git commit -m "Immich aktivieren"
git push
```

Die Images sind groß, der erste Start dauert einige Minuten:

```bash
kubectl get pods,statefulset,pvc -n immich
```

```
NAME                                           READY   STATUS    RESTARTS   AGE
pod/immich-machine-learning-6d9f8b7c5d-k2x9m   1/1     Running   0          4m
pod/immich-postgres-0                          1/1     Running   0          4m
pod/immich-redis-7c8d9f6b5d-q2m4x              1/1     Running   0          4m
pod/immich-server-5b7d9c8f6-9mzq7              1/1     Running   2          4m

NAME                               READY   AGE
statefulset.apps/immich-postgres   1/1     4m

NAME                                           STATUS   VOLUME           CAPACITY   ...
persistentvolumeclaim/data-immich-postgres-0   Bound    pvc-…            10Gi       ...
persistentvolumeclaim/immich-library           Bound    immich-library   100Gi      ...
persistentvolumeclaim/immich-ml-cache          Bound    pvc-…            10Gi       ...
```

Beachte: `immich-postgres-0` mit fester Nummer, und der PVC `data-immich-postgres-0` wurde vom StatefulSet angelegt.
Ein paar `RESTARTS` beim Server sind normal: Er startet schneller als die Datenbank und versucht es dann erneut.

## 3. Einrichten

1. Öffne <https://immich.tail1a2b3c.ts.net> → **Getting Started**.
2. Admin-Konto anlegen (E-Mail, Passwort → Passwortmanager).
3. Die Einrichtung durchklicken. Unter **Sprache** kannst du Deutsch wählen.

### Handy-App

1. App **Immich** installieren (iOS/Android).
2. **Server-URL:** `https://immich.tail1a2b3c.ts.net`
3. Anmelden → oben rechts auf das Wolken-Symbol → **Alben für die Sicherung auswählen** (z. B. „Kamera“) → **Sicherung aktivieren**.
4. Optional: **Hintergrundsicherung** einschalten.

> 💡 Die Sicherung läuft, wenn Tailscale auf dem Handy aktiv ist. Am einfachsten lässt du Tailscale dauerhaft an.
> Es braucht kaum Akku.

Nach dem ersten Upload:

> 🐧 **In der VM:**

```bash
sudo du -sh /data/photos
sudo ls /data/photos
```

```
1.2G    /data/photos
backups  encoded-video  library  profile  thumbs  upload
```

Im Web unter **Erkunden** tauchen nach einer Weile **Personen** und **Orte** auf. Das ist das Machine Learning bei der Arbeit.
Es lädt beim ersten Mal seine KI-Modelle herunter, die dann im PVC `immich-ml-cache` liegen bleiben.

## 4. Optional: Gesichtserkennung auf der GPU

Machine Learning auf der CPU funktioniert, ist bei Tausenden Fotos aber langsam. Die RTX 2070 Super kann das viel
schneller. Problem: Die Karte ist bereits an Jellyfin vergeben (`nvidia.com/gpu: 1`, und es gibt nur eine).

### Time-Slicing: eine GPU, mehrere Nutzer

Das NVIDIA Device Plugin kann eine Karte als **mehrere** melden. Die Pods teilen sich die Rechenzeit, ähnlich wie sich
Programme eine CPU teilen. Öffne `kubernetes/infrastructure/nvidia-device-plugin/values.yaml` und entferne die `#` vor dem `config`-Block:

```yaml
config:
  map:
    default: |-
      version: v1
      sharing:
        timeSlicing:
          resources:
            - name: nvidia.com/gpu
              replicas: 2
```

```bash
git commit -am "GPU: Time-Slicing mit 2 Anteilen"
git push
```

Nach dem Sync (das Device Plugin startet neu):

```bash
kubectl describe node k3s | grep "nvidia.com/gpu"
```

```
  nvidia.com/gpu:     2
  nvidia.com/gpu:     2
  nvidia.com/gpu     1           1         ← einer ist an Jellyfin vergeben
```

> 💡 **Einschränkung:** Beim Time-Slicing teilen sich die Pods auch die 8 GB Grafikspeicher, ohne feste Aufteilung.
> Für Jellyfin plus Immich reicht das gut.

### Immich auf die GPU umstellen

In [`kubernetes/apps/immich/kustomization.yaml`](../kubernetes/apps/immich/kustomization.yaml) die beiden letzten Zeilen
einkommentieren. Der Patch [`gpu-patch.yaml`](../kubernetes/apps/immich/gpu-patch.yaml) tauscht das Image gegen die
**CUDA-Variante** und fordert einen GPU-Anteil an:

```yaml
      runtimeClassName: nvidia
      containers:
        - name: machine-learning
          image: ghcr.io/immich-app/immich-machine-learning:v3.2.0-cuda   # CUDA-Variante
          resources:
            limits:
              nvidia.com/gpu: 1
```

```bash
git commit -am "Immich: Machine Learning auf der GPU"
git push
```

Das CUDA-Image ist mehrere GB groß, der Download dauert. Dann in Immich: **Administration → Aufgaben → Gesichtserkennung → Alle**.
In der VM zeigt `nvidia-smi` jetzt neben Jellyfins FFmpeg (falls gerade transkodiert wird) auch einen Python-Prozess von Immich.

## ✅ Checkpoint

- [ ] `kubectl get pods -n immich` zeigt vier laufende Pods, darunter `immich-postgres-0`.
- [ ] `https://immich.<tailnet>.ts.net` ist erreichbar, das Admin-Konto existiert.
- [ ] Die Handy-App sichert Fotos, sie liegen in `/data/photos`.
- [ ] Unter **Erkunden** erscheinen Personen/Orte.
- [ ] *(Optional)* `nvidia.com/gpu: 2` am Node, Immich-ML läuft auf der GPU.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Server-Log: `connect ECONNREFUSED` zu `immich-postgres` | Die Datenbank startet noch, abwarten. Bleibt es so: `kubectl logs -n immich immich-postgres-0` |
| `password authentication failed for user "postgres"` | Secret wurde nach dem ersten Start geändert (siehe Hinweis in Schritt 1). Einfachste Lösung bei einer neuen Installation: App deaktivieren, PVC `data-immich-postgres-0` löschen, wieder aktivieren |
| PV-Fehler: `/data/photos is not a directory` | Schritt 1 in der VM vergessen |
| Upload bricht bei großen Videos ab | Tailscale-Verbindung prüfen, notfalls im Heimnetz-WLAN sichern |
| ML-Pod `OOMKilled` | `limits.memory` in `machine-learning.yaml` erhöhen |
| ML-Pod mit GPU bleibt `Pending` | Time-Slicing aktiv? `kubectl describe node k3s \| grep nvidia.com/gpu` muss 2 zeigen |

## 🎓 Was du gelernt hast

- Große Apps bestehen aus mehreren **Komponenten**, die sich über Service-Namen finden.
- Das Muster aus Kapitel 14 (StatefulSet für die Datenbank, `secretKeyRef`, statisches PV) trägt auch eine größere App.
- **Time-Slicing** teilt eine GPU zwischen mehreren Pods.
- Nicht alle Daten sind gleich: Fotos sind unersetzlich und brauchen ein eigenes Backup.

---

⬅️ **Zurück:** [25 – Homepage](25-homepage.md) · ➡️ **Weiter:** [27 – Paperless-ngx](27-paperless.md)
