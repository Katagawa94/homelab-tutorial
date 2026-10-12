# 14 – Nextcloud

> **Was du am Ende hast:** Deine eigene Cloud unter `https://nextcloud.<tailnet>.ts.net`, für Dateien (wie Dropbox),
> Kalender und Kontakte. Synchronisiert mit Laptop und Handy, und die Dateien liegen auf deiner Platte.
>
> ⏱️ **Zeit:** ca. 1 Stunde
>
> 🧠 **Neue Begriffe:** statisches [PersistentVolume](glossar.md#container--kubernetes), [hostPath](glossar.md#container--kubernetes),
> [Reclaim Policy](glossar.md#container--kubernetes), [StatefulSet](glossar.md#container--kubernetes), `secretKeyRef`,
> zweiter Container im Pod

---

> 📸 **Snapshot-Routine:** Snapshot der VM anlegen (z. B. `vor-nextcloud`).

## Was ist Nextcloud?

**Nextcloud** ist eine selbst betriebene Cloud:

| Funktion | Ersetzt z. B. | Zugriff |
|----------|---------------|---------|
| **Dateien** mit Sync-Ordner auf allen Geräten | Dropbox, OneDrive, Google Drive | Desktop-Client, Handy-App, Browser |
| **Kalender** (CalDAV) | Google Kalender, iCloud | Handy-Kalender, Thunderbird |
| **Kontakte** (CardDAV) | Google Kontakte, iCloud | Handy-Adressbuch |
| viele weitere Apps (Notizen, Aufgaben …) | | im Browser |

Wie Vaultwarden ist Nextcloud **nur im Tailnet** erreichbar. Unterwegs brauchen deine Geräte also Tailscale.

## Aufbau: drei Teile

```
 Desktop-Client / Handy-App / Browser
        │  https://nextcloud.<tailnet>.ts.net
        ▼
┌──────────────────── Pod nextcloud ────────────────────┐
│  nextcloud (Apache + PHP)      cron (alle 5 Minuten)  │──► /data/nextcloud  (deine Dateien, Datenplatte)
│  Weboberfläche, Sync           Hintergrundaufgaben    │──► nextcloud-html   (Programm + Einstellungen)
└───────────────────────────────────────────────────────┘
        │                         │
        ▼                         ▼
 nextcloud-postgres         nextcloud-redis
 (StatefulSet)              (Valkey)
 Datenbank                  Sitzungen, Datei-Sperren
```

Die Manifeste liegen in [`kubernetes/apps/nextcloud/`](../kubernetes/apps/nextcloud/). Drei Dinge darin sind neu.

## Neu 1: Ein PersistentVolume von Hand

In Kapitel 08 hat die StorageClass `local-path` automatisch einen Ordner auf der **Systemplatte** angelegt. Für deine
Dateien wollen wir das nicht. Sie sollen auf die große **Datenplatte** (`/data`, Kapitel 04) und dort auch bleiben.
Deshalb schreiben wir das **PV selbst**:

```yaml
# kubernetes/apps/nextcloud/pv-data.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nextcloud-data
spec:
  capacity:
    storage: 200Gi                # nur eine Angabe; hostPath prüft die Größe nicht
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain   # deine Dateien NIEMALS automatisch löschen
  storageClassName: ""            # kein automatischer Lieferdienst, dieses PV ist handgemacht
  claimRef:                       # reserviert dieses PV für genau diesen PVC
    namespace: nextcloud
    name: nextcloud-data
  hostPath:
    path: /data/nextcloud         # vorher in der VM anlegen (Kapitel 14)
    type: Directory
```

| Feld | Bedeutung |
|------|-----------|
| `hostPath` | Das PV ist einfach ein Ordner auf dem Node, hier `/data/nextcloud` |
| `persistentVolumeReclaimPolicy: Retain` | Wird der PVC gelöscht, bleiben die Daten **erhalten** (im Gegensatz zu `Delete` bei `local-path`) |
| `storageClassName: ""` | Leer heißt: Hier liefert kein Automat, das PV ist handgemacht |
| `claimRef` | Dieses PV ist für den PVC `nextcloud-data` im Namespace `nextcloud` reserviert. Kein anderer PVC kann es sich schnappen |

Der passende PVC ([`pvc-data.yaml`](../kubernetes/apps/nextcloud/pvc-data.yaml)) nennt das PV mit `volumeName: nextcloud-data`
beim Namen. So finden sich die beiden garantiert.

> 💡 PersistentVolumes gehören keinem Namespace, sie gelten für den ganzen Cluster. Deshalb steht in `pv-data.yaml` kein
> `namespace:`, wohl aber im `claimRef`.

Programm und Einstellungen von Nextcloud (`/var/www/html`, ca. 1 GB) liegen dagegen ganz normal in einem
`local-path`-PVC auf der schnellen Systemplatte.

## Neu 2: Die Datenbank als StatefulSet

Die Datenbank ([`postgres.yaml`](../kubernetes/apps/nextcloud/postgres.yaml)) läuft nicht als Deployment, sondern als **StatefulSet**:

| | Deployment | StatefulSet |
|--|------------|-------------|
| Pod-Name | zufällig: `nextcloud-7f4b8d6c9a-kq5xz` | fest: **`nextcloud-postgres-0`** |
| Speicher | ein PVC, den du selbst anlegst | wird pro Pod über **`volumeClaimTemplates`** erzeugt |
| Start/Stopp | alle gleichzeitig | der Reihe nach: `-0`, dann `-1` … |
| typisch für | Apps | **Datenbanken** und alles mit fester Identität |

```yaml
  volumeClaimTemplates:           # erzeugt den PVC "data-nextcloud-postgres-0"
    - metadata:
        name: data
      spec:
        storageClassName: local-path
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
```

Bei nur einer Kopie ist der Unterschied klein. Du wirst StatefulSets aber in fast jedem Helm-Chart mit Datenbank
wiedersehen (Immich, Prometheus …), und jetzt weißt du, was sie sind.

### Einzelne Werte aus einem Secret: `secretKeyRef`

Postgres und Nextcloud brauchen dasselbe Datenbank-Passwort. Es liegt **einmal** im Secret `nextcloud-secrets`, und beide
holen sich mit **`secretKeyRef`** genau diesen einen Wert:

```yaml
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:     # nur EINEN Wert aus einem Secret holen
                  name: nextcloud-secrets
                  key: POSTGRES_PASSWORD
```

(Bei Vaultwarden gab es kein Secret. Mit `envFrom` würdest du dagegen **alle** Einträge eines Secrets übernehmen, Kapitel 08.)

## Neu 3: Zwei Container in einem Pod

Nextcloud muss regelmäßig Hintergrundaufgaben erledigen: aufräumen, Vorschaubilder erzeugen, Benachrichtigungen
verschicken. Dafür läuft im selben Pod ein **zweiter Container** mit demselben Image, der nur `/cron.sh` ausführt:

```yaml
      containers:
        - name: nextcloud
          image: nextcloud:34.0.4-apache
          ...
        - name: cron
          image: nextcloud:34.0.4-apache
          command: ["/cron.sh"]
          volumeMounts:            # dieselben Volumes wie der Hauptcontainer
            - name: html
              mountPath: /var/www/html
            - name: data
              mountPath: /var/www/html/data
```

Container in einem Pod teilen sich Volumes und Netzwerk. Deshalb sieht `cron` dieselben Dateien wie die Weboberfläche.
Das Prinzip begegnet dir in Kapitel 21 wieder, dort als VPN für qBittorrent.

### Die Adresse muss stimmen

```yaml
            - name: NEXTCLOUD_TRUSTED_DOMAINS
              value: nextcloud.tail9x8y7z.ts.net
            - name: OVERWRITEHOST
              value: nextcloud.tail9x8y7z.ts.net
            - name: OVERWRITEPROTOCOL
              value: https
```

Nextcloud antwortet nur unter Adressen, die es kennt (*trusted domains*). Und weil das HTTPS vom Tailscale-Proxy kommt,
sagen wir Nextcloud mit `OVERWRITE…`, dass es nach außen unter `https://…` erreichbar ist. Den Tailnet-Namen hast du in
Kapitel 13 (Schritt 1) schon eingetragen.

## 1. Den Ordner für die Dateien anlegen

> 🐧 **In der VM** (`ssh homelab@k3s`)

```bash
sudo mkdir /data/nextcloud
sudo chown 33:33 /data/nextcloud
sudo chmod 750 /data/nextcloud
ls -ldn /data/nextcloud
```

```
drwxr-x--- 2 33 33 4096 Okt 12 10:00 /data/nextcloud
```

> 💡 **Warum 33 und nicht 1000?** Im Nextcloud-Image läuft der Webserver als Benutzer `www-data`, und der hat die Nummer
> **33**. Nextcloud prüft außerdem, dass niemand sonst seine Dateien lesen kann. Deshalb `750` (Besitzer alles, Gruppe
> lesen, alle anderen nichts).

## 2. Zugangsdaten versiegeln

> 💻 **Auf deinem Rechner** (im Ordner `homelab-tutorial`). Admin-Name und -Passwort ausdenken → **Passwortmanager**:

```bash
mkdir -p kubernetes/secrets/nextcloud
kubectl create secret generic nextcloud-secrets -n nextcloud \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 16)" \
  --from-literal=NEXTCLOUD_ADMIN_USER='<ADMIN-NAME>' \
  --from-literal=NEXTCLOUD_ADMIN_PASSWORD='<ADMIN-PASSWORT>' \
  --dry-run=client -o yaml \
| kubeseal --format yaml > kubernetes/secrets/nextcloud/nextcloud-secrets.yaml
```

> 💡 `$(openssl rand -hex 16)` erzeugt ein zufälliges Datenbank-Passwort. Das musst du dir nicht merken, es verbindet nur
> Nextcloud mit seiner Datenbank. **Aber:** Postgres übernimmt es nur beim allerersten Start, und auch das Admin-Konto wird
> nur bei der ersten Installation angelegt. Also einmal erzeugen und dann in Ruhe lassen.

## 3. Aktivieren

```bash
cp kubernetes/katalog/nextcloud.yaml kubernetes/aktiv/
git add kubernetes/aktiv/nextcloud.yaml kubernetes/secrets/nextcloud/
git commit -m "Nextcloud aktivieren"
git push
```

Die App `secrets` aus Kapitel 12 rollt das neue SealedSecret automatisch mit aus. Beim ersten Start **installiert sich
Nextcloud**, das dauert ein paar Minuten:

```bash
kubectl get pods,statefulset,pvc -n nextcloud
```

```
NAME                                   READY   STATUS    RESTARTS   AGE
pod/nextcloud-6d9f8b7c5d-k2x9m         2/2     Running   0          4m
pod/nextcloud-postgres-0               1/1     Running   0          4m
pod/nextcloud-redis-7c8d9f6b5d-q2m4x   1/1     Running   0          4m

NAME                                  READY   AGE
statefulset.apps/nextcloud-postgres   1/1     4m

NAME                                              STATUS   VOLUME           CAPACITY   ...
persistentvolumeclaim/data-nextcloud-postgres-0   Bound    pvc-…            5Gi        ...
persistentvolumeclaim/nextcloud-data              Bound    nextcloud-data   200Gi      ...
persistentvolumeclaim/nextcloud-html              Bound    pvc-…            5Gi        ...
```

Beachte: `2/2` beim Nextcloud-Pod (Weboberfläche + cron), `nextcloud-postgres-0` mit fester Nummer, und der PVC
`data-nextcloud-postgres-0` wurde vom StatefulSet angelegt.

Die Installation mitlesen (mit `-c` wählst du den Container im Pod):

```bash
kubectl logs -n nextcloud deploy/nextcloud -c nextcloud -f
```

Sie ist fertig, wenn `Nextcloud was successfully installed` erscheint. Beenden mit `Strg+C`.

## 4. Einrichten

Öffne <https://nextcloud.tail1a2b3c.ts.net> und melde dich mit dem Admin-Konto aus Schritt 2 an.

### Feinschliff per `occ`

Nextcloud hat ein eigenes Kommandozeilen-Werkzeug, **`occ`**. Es muss als Benutzer `www-data` laufen:

```bash
occ() { kubectl exec -n nextcloud deploy/nextcloud -c nextcloud -- su -s /bin/sh www-data -c "php occ $*"; }

occ status
occ background:cron                                                     # Hintergrundaufgaben über den cron-Container
occ config:system:set default_phone_region --value=DE                   # Telefonnummern ohne +49 erkennen
occ config:system:set maintenance_window_start --type=integer --value=1 # Wartung nachts um 1 Uhr (UTC)
```

(Die erste Zeile definiert eine kleine Abkürzung `occ` für dein aktuelles Terminal.)

Unter **Verwaltungseinstellungen → Übersicht** prüft Nextcloud seine Einrichtung. Einige Hinweise sind im Homelab normal,
z. B. ein fehlender E-Mail-Server. Echte Fehler sind rot markiert.

### Eigenes Benutzerkonto

Arbeite im Alltag nicht als Admin: **Konten → Neues Konto** anlegen (auch für Familienmitglieder) und damit anmelden.

## 5. Geräte verbinden

| Gerät | So geht's |
|-------|-----------|
| **Laptop/PC** | Nextcloud-Desktop-Client (unter NixOS: Paket `nextcloud-client`) → Server-Adresse `https://nextcloud.tail1a2b3c.ts.net` → anmelden → Sync-Ordner wählen |
| **Handy** | App **Nextcloud** (iOS/Android) → gleiche Adresse. Tailscale muss auf dem Handy laufen |
| **Kalender & Kontakte** | Android: App **DAVx⁵** mit der Adresse `https://nextcloud.tail1a2b3c.ts.net/remote.php/dav`. iOS: Einstellungen → Kalender/Kontakte → Account hinzufügen → CalDAV/CardDAV mit derselben Adresse |

> 💡 **App-Passwörter:** Für jedes Gerät unter **Persönliche Einstellungen → Sicherheit → Geräte & Sitzungen** ein eigenes
> App-Passwort erzeugen und dieses statt deines echten Passworts verwenden. Verlierst du ein Handy, sperrst du nur dieses eine.

### Wo landen die Dateien?

Lade im Browser eine Datei hoch. Dann:

> 🐧 **In der VM:**

```bash
sudo ls -l /data/nextcloud/<BENUTZERNAME>/files/
```

Da ist sie, als ganz normale Datei auf der Datenplatte.

> ⚠️ **Backup:** Die Datenplatte ist vom Proxmox-Backup ausgenommen (Kapitel 04). Kapitel 29 richtet deshalb ein eigenes
> Backup für `/data/nextcloud` ein. Bis dahin: Lege nichts in Nextcloud ab, wovon es keine zweite Kopie gibt.

## ✅ Checkpoint

- [ ] `kubectl get pods -n nextcloud` zeigt drei laufende Pods, Nextcloud mit `2/2`.
- [ ] `https://nextcloud.<tailnet>.ts.net` ist erreichbar, Login funktioniert.
- [ ] `occ status` zeigt `installed: true`.
- [ ] Desktop-Client oder Handy-App synchronisieren eine Datei.
- [ ] Die Datei liegt in der VM unter `/data/nextcloud/<benutzer>/files/`.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| „Zugriff über eine nicht vertrauenswürdige Domain“ | Tailnet-Name in `deployment.yaml` falsch oder noch der Platzhalter (Kapitel 13, Schritt 1). Bei bestehender Installation zusätzlich: `occ config:system:set trusted_domains 1 --value=nextcloud.<tailnet>.ts.net` |
| Pod hängt bei `ContainerCreating`: `/data/nextcloud is not a directory` | Schritt 1 in der VM vergessen |
| „Dein Datenverzeichnis ist für andere lesbar“ / `Permission denied` | Besitzer und Rechte prüfen: `ls -ldn /data/nextcloud` muss `33 33` und `drwxr-x---` zeigen (Schritt 1) |
| Installation bricht ab: `password authentication failed` | Das Secret wurde nach dem ersten Start geändert. Bei einer neuen Installation: App deaktivieren, PVCs `data-nextcloud-postgres-0` und `nextcloud-html` löschen, `/data/nextcloud` leeren, wieder aktivieren |
| Große Dateien lassen sich nicht hochladen | `PHP_UPLOAD_LIMIT` in `deployment.yaml` erhöhen. Der Desktop-Client lädt große Dateien ohnehin in Stücken hoch |
| Seite lädt sehr langsam | `kubectl top pod -n nextcloud`: Ist das RAM-Limit erreicht? Läuft `nextcloud-redis`? |

## 🎓 Was du gelernt hast

- Ein **handgemachtes PV** mit `hostPath` bindet einen vorhandenen Ordner ein. `Retain` schützt die Daten, `claimRef` reserviert das PV.
- Ein **StatefulSet** gibt Pods eine feste Identität und eigenen Speicher über `volumeClaimTemplates`. Das ist der Standard für Datenbanken.
- **`secretKeyRef`** holt einen einzelnen Wert aus einem Secret.
- Mehrere **Container in einem Pod** teilen sich Volumes und Netzwerk, hier für die Hintergrundaufgaben.
- Nicht jedes Image läuft als Benutzer 1000: Nextcloud braucht `www-data` (33).

---

⬅️ **Zurück:** [13 – Vaultwarden](13-vaultwarden.md) · ➡️ **Weiter:** [15 – Pi-hole](15-pihole.md)
