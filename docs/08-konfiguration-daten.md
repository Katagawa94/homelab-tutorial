# 08 – Konfiguration & Daten

> **Was du am Ende hast:** Eine Webseite, deren Inhalt aus einer ConfigMap kommt, und einen Lesezeichen-Manager
> (linkding) mit Passwort aus einem Secret und Daten, die jeden Neustart überleben.
>
> ⏱️ **Zeit:** ca. 1 Stunde
>
> 🧠 **Neue Begriffe:** [ConfigMap](glossar.md#container--kubernetes), [Secret](glossar.md#container--kubernetes),
> Volume, [PersistentVolume (PV)](glossar.md#container--kubernetes),
> [PersistentVolumeClaim (PVC)](glossar.md#container--kubernetes), [StorageClass](glossar.md#container--kubernetes)

---

## Das Problem

In Kapitel 06 hast du gelernt: **Container sind vergänglich.** Außerdem steckt in einem Image nur das Programm,
nicht *deine* Einstellungen. Eine echte App braucht aber drei Dinge von außen:

| Was | Beispiel Jellyfin | Kubernetes-Lösung |
|-----|-------------------|-------------------|
| **Konfiguration** | Zeitzone, Benutzer-ID | **ConfigMap** |
| **Geheimnisse** | Passwörter, API-Schlüssel | **Secret** |
| **Daten, die bleiben** | Datenbank, Einstellungen, Filme | **PersistentVolumeClaim** |

Alle Dateien liegen in [`examples/08-konfiguration-daten/`](../examples/08-konfiguration-daten/).

## Teil 1: ConfigMap, eine Webseite aus der Konfiguration

### Die ConfigMap

Eine **ConfigMap** ist eine Sammlung von Schlüssel-Wert-Paaren. Der Wert kann auch ein ganzer Dateiinhalt sein:

```yaml
# examples/08-konfiguration-daten/webseite/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: webseite
  namespace: lernen
data:
  # Jeder Eintrag unter "data" wird später zu einer Datei im Container.
  index.html: |
    <!DOCTYPE html>
    <html lang="de">
      ...
        <h1>🏠 Hallo aus meinem Homelab!</h1>
        <p>Dieser Text kommt aus einer ConfigMap.</p>
      ...
    </html>
```

> 💡 Das `|` nach `index.html:` bedeutet in YAML: *„Jetzt kommt mehrzeiliger Text, genau so, wie er eingerückt ist.“*

### Die ConfigMap als Datei einbinden

Im Deployment wird die ConfigMap als **Volume** eingebunden. Ein Volume ist ein Stück Speicher, das in einem Ordner
des Containers erscheint:

```yaml
# Ausschnitt aus examples/08-konfiguration-daten/webseite/deployment.yaml
    spec:
      containers:
        - name: nginx
          image: nginx:1.30
          volumeMounts:
            - name: inhalt                        # welches Volume (siehe unten) …
              mountPath: /usr/share/nginx/html    # … wo im Container erscheinen soll
              readOnly: true
      volumes:
        - name: inhalt
          configMap:
            name: webseite                        # die ConfigMap aus configmap.yaml
```

```
ConfigMap "webseite"                 Container nginx
┌──────────────────────┐             /usr/share/nginx/html/
│ index.html: <html>…  │ ──────────► └── index.html
└──────────────────────┘
```

Alles auf einmal anwenden. `kubectl apply` nimmt auch ganze Ordner:

```bash
kubectl apply -f examples/08-konfiguration-daten/webseite/
```

```
configmap/webseite created
deployment.apps/webseite created
service/webseite created
```

Öffne <http://192.168.178.11:8081>: **„🏠 Hallo aus meinem Homelab!“**

### Konfiguration ändern, ohne das Image anzufassen

1. Öffne `examples/08-konfiguration-daten/webseite/configmap.yaml` in einem Editor und ändere den Text in der
   `<h1>`-Zeile, z. B. in `Mein Server, meine Regeln!`.
2. Anwenden:

   ```bash
   kubectl apply -f examples/08-konfiguration-daten/webseite/configmap.yaml
   ```

3. Warte bis zu einer Minute und lade die Seite neu. Der neue Text erscheint, **ohne dass der Pod neu gestartet wurde**.

> 💡 Als Volume eingebundene ConfigMaps werden automatisch aktualisiert (mit etwas Verzögerung). Viele Apps lesen ihre
> Konfiguration aber nur beim Start. Dann hilft `kubectl rollout restart deployment/<name> -n <namespace>`.

ConfigMaps können auch **Umgebungsvariablen** liefern statt Dateien. Das nutzen wir später z. B. für `TZ=Europe/Berlin`.
Wie das aussieht, zeigt dir gleich das Secret.

Stell die Datei wieder auf den Originalzustand zurück:

```bash
git checkout examples/08-konfiguration-daten/webseite/configmap.yaml
```

## Teil 2: Secret, das Passwort für linkding

Als Nächstes installieren wir **linkding**, einen schlanken Lesezeichen-Manager. Er soll beim ersten Start einen
Admin-Benutzer anlegen, und dafür braucht er ein Passwort.

### Secret anlegen

Passwörter gehören **nicht** in Dateien im Git-Repository. Deshalb legen wir das Secret direkt per Befehl an
(`<DEIN-PASSWORT>` ersetzen):

```bash
kubectl create secret generic linkding-zugang -n lernen \
  --from-literal=LD_SUPERUSER_NAME=homelab \
  --from-literal=LD_SUPERUSER_PASSWORD='<DEIN-PASSWORT>'
```

```
secret/linkding-zugang created
```

> 💡 Das `\` am Zeilenende heißt: *„Der Befehl geht in der nächsten Zeile weiter.“*

### Wie geheim ist ein Secret?

```bash
kubectl get secret linkding-zugang -n lernen -o yaml
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: linkding-zugang
  namespace: lernen
data:
  LD_SUPERUSER_NAME: aG9tZWxhYg==
  LD_SUPERUSER_PASSWORD: bWVpbi1nZWhlaW1lcy1wYXNzd29ydA==
type: Opaque
```

Sieht verschlüsselt aus? Ist es nicht:

```bash
kubectl get secret linkding-zugang -n lernen -o jsonpath='{.data.LD_SUPERUSER_PASSWORD}' | base64 -d; echo
```

Dein Passwort erscheint im Klartext.

> ⚠️ **Base64 ist keine Verschlüsselung**, nur eine andere Schreibweise. Kubernetes schützt Secrets über
> *Zugriffsrechte* (nicht jeder darf sie lesen), nicht über Verschlüsselung. Deshalb gilt:
> **Secrets niemals als normale YAML-Datei ins Git-Repository!**
> In Kapitel 14 lernst du **Sealed Secrets** kennen. Damit werden Secrets so verschlüsselt, dass sie ins Repository dürfen.

### Secret als Umgebungsvariablen

Im Deployment von linkding holen wir mit `envFrom` **alle** Einträge des Secrets als Umgebungsvariablen in den Container:

```yaml
# Ausschnitt aus examples/08-konfiguration-daten/linkding/deployment.yaml
          envFrom:
            - secretRef:
                name: linkding-zugang     # alle Einträge des Secrets werden Umgebungsvariablen
```

Im Container gibt es dann `LD_SUPERUSER_NAME=homelab` und `LD_SUPERUSER_PASSWORD=…`. Genau diese Namen erwartet
linkding laut seiner Dokumentation.

## Teil 3: Daten, die bleiben

### PV, PVC und StorageClass

Kubernetes trennt Speicher in zwei Rollen:

| Objekt | Vergleich | Wer legt es an? |
|--------|-----------|-----------------|
| **PersistentVolumeClaim (PVC)** | die Bestellung: „Ich brauche 1 GB.“ | du, als Teil deiner App |
| **PersistentVolume (PV)** | das gelieferte Paket: ein echter Ordner auf der Platte | automatisch, durch die StorageClass |
| **StorageClass** | der Lieferdienst: *wie* und *wo* Speicher entsteht | ist bei k3s schon da |

```bash
kubectl get storageclass
```

```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  2d
```

Die StorageClass **`local-path`** legt für jeden PVC einen Ordner auf der Festplatte der VM an, unter
`/var/lib/rancher/k3s/storage/`. Zwei Spalten sind wichtig:

- **`RECLAIMPOLICY Delete`**: Wird der PVC gelöscht, wird **auch der Ordner mit allen Daten gelöscht**. ⚠️
- **`WaitForFirstConsumer`**: Der Ordner wird erst angelegt, wenn ein Pod den PVC wirklich benutzt.

### Den PVC anlegen

```yaml
# examples/08-konfiguration-daten/linkding/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: linkding-daten
  namespace: lernen
spec:
  storageClassName: local-path    # von k3s mitgeliefert: Ordner auf der Festplatte der VM
  accessModes:
    - ReadWriteOnce               # darf von einem Node gleichzeitig beschrieben werden
  resources:
    requests:
      storage: 1Gi
```

```bash
kubectl apply -f examples/08-konfiguration-daten/linkding/pvc.yaml
kubectl get pvc -n lernen
```

```
NAME             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
linkding-daten   Pending                                      local-path     5s
```

`Pending` ist hier **richtig**: `WaitForFirstConsumer`, es gibt noch keinen Pod, der den Speicher nutzt.

### linkding starten

Das Deployment bindet den PVC als Volume ein, dort, wo linkding laut Dokumentation seine Datenbank ablegt:

```yaml
# Ausschnitt aus examples/08-konfiguration-daten/linkding/deployment.yaml
spec:
  replicas: 1
  strategy:
    type: Recreate                # erst alten Pod beenden, dann neuen starten (wichtig bei Datenbanken!)
  ...
          volumeMounts:
            - name: daten
              mountPath: /etc/linkding/data
      volumes:
        - name: daten
          persistentVolumeClaim:
            claimName: linkding-daten     # der PVC aus pvc.yaml
```

> 💡 **Warum `strategy: Recreate`?** Beim Rolling Update (Kapitel 07) laufen kurz alter und neuer Pod gleichzeitig.
> Zwei Programme, die gleichzeitig in dieselbe Datenbank-Datei schreiben, können sie beschädigen.
> `Recreate` beendet erst den alten Pod und startet dann den neuen. Das bedeutet ein paar Sekunden Ausfall, aber sichere Daten.
> Das gilt für fast alle Homelab-Apps, auch Jellyfin.

```bash
kubectl apply -f examples/08-konfiguration-daten/linkding/
kubectl get pods,pvc,pv -n lernen
```

```
NAME                            READY   STATUS    RESTARTS   AGE
pod/linkding-5c9d7f8b6-q2m4x    1/1     Running   0          40s
pod/webseite-7d4f6b9c8-lx7kd    1/1     Running   0          15m

NAME                                   STATUS   VOLUME                                     CAPACITY   ...
persistentvolumeclaim/linkding-daten   Bound    pvc-3f2a9c1e-8b7d-4e6f-a5c4-1d2e3f4a5b6c   1Gi        ...

NAME                                                        CAPACITY   RECLAIM POLICY   STATUS   CLAIM                   ...
persistentvolume/pvc-3f2a9c1e-8b7d-4e6f-a5c4-1d2e3f4a5b6c   1Gi        Delete           Bound    lernen/linkding-daten   ...
```

Der PVC ist jetzt **`Bound`**: Die StorageClass hat automatisch ein passendes **PV** erzeugt und verbunden.

### Ausprobieren

1. Öffne <http://192.168.178.11:9090> (der erste Start kann ca. 30 Sekunden dauern).
2. Melde dich mit `homelab` und deinem Passwort an.
3. Füge ein Lesezeichen hinzu, z. B. `https://jellyfin.org`.

### Der Beweis: Daten überleben

Lösche den Pod:

```bash
kubectl delete pod -l app=linkding -n lernen
kubectl get pods -n lernen -w
```

Sobald der neue Pod `Running` ist (`Strg+C` beendet das Beobachten), lade die Seite neu. Du bist noch angemeldet, und
**dein Lesezeichen ist noch da**. 🎉

Vergleiche mit Kapitel 06: Dort war die Änderung nach dem Neustart weg. Der Unterschied ist das Volume.

### Wo liegen die Daten wirklich?

> 🐧 **In der VM** (`ssh homelab@k3s`)

```bash
sudo ls /var/lib/rancher/k3s/storage/
```

```
pvc-3f2a9c1e-8b7d-4e6f-a5c4-1d2e3f4a5b6c_lernen_linkding-daten
```

```bash
sudo ls /var/lib/rancher/k3s/storage/pvc-*_lernen_linkding-daten/
```

```
db.sqlite3  favicons  previews  secretkey.txt
```

Das ist ein ganz normaler Ordner auf der 60-GB-Systemplatte der VM. Genau diese Platte sichern wir in Kapitel 27 mit Proxmox-Backups.

> 💡 **Ausblick:** Für Jellyfins Filme nutzen wir in Kapitel 11 **keinen** automatisch angelegten Ordner, sondern ein
> **von Hand angelegtes PV**, das auf `/data` zeigt, die 300-GB-Platte aus Kapitel 04.

## Aufräumen

Webseite und linkding bleiben noch bis zum Ende von Kapitel 09 stehen. Aufgeräumt wird dort mit einem Befehl.

## ✅ Checkpoint

- [ ] <http://192.168.178.11:8081> zeigt die Webseite aus der ConfigMap.
- [ ] Du hast den Text in der ConfigMap geändert und die Änderung im Browser gesehen.
- [ ] Du weißt, dass Secrets nur base64-kodiert und nicht verschlüsselt sind.
- [ ] `kubectl get pvc -n lernen` zeigt `linkding-daten` als `Bound`.
- [ ] Dein Lesezeichen in linkding hat das Löschen des Pods überlebt.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| linkding-Pod: `CreateContainerConfigError` | Das Secret fehlt oder heißt anders → `kubectl get secrets -n lernen` |
| Login bei linkding klappt nicht | Das Secret wird nur beim **ersten** Start ausgewertet. Secret korrigieren, dann PVC und Pod löschen (die Daten sind dann weg) und `kubectl apply -f examples/08-konfiguration-daten/linkding/` erneut ausführen |
| PVC bleibt `Pending`, obwohl der Pod existiert | `kubectl describe pvc linkding-daten -n lernen` → Events lesen. Tippfehler bei `storageClassName`? |
| Webseite zeigt nach Änderung den alten Text | Bis zu 1 Minute warten, Browser-Cache umgehen (`Strg+Shift+R`) |
| `error: the path "…" does not exist` | Du bist nicht im Ordner `homelab-tutorial` → `cd ~/homelab-tutorial` |

## 🎓 Was du gelernt hast

- **ConfigMaps** liefern Konfiguration als Dateien oder Umgebungsvariablen.
- **Secrets** funktionieren genauso, sind aber nur base64-kodiert und gehören nie im Klartext ins Git-Repository.
- **Volumes** binden Speicher in einen Container ein.
- Ein **PVC** bestellt Speicher, die **StorageClass** liefert ein **PV**, und die Daten überleben jeden Pod-Neustart.
- **Achtung:** Wird ein PVC mit `local-path` gelöscht, sind die Daten weg.
- Apps mit Datenbank laufen mit `strategy: Recreate`.

---

⬅️ **Zurück:** [07 – Deployments & Services](07-deployments-services.md) · ➡️ **Weiter:** [09 – Helm](09-helm.md)
