# 06 – Erster Pod

> **Was du am Ende hast:** Du hast einen Container in Kubernetes gestartet, hineingeschaut, seine Logs gelesen und
> verstanden, warum ein einzelner Pod allein nicht reicht.
>
> ⏱️ **Zeit:** ca. 45 Minuten
>
> 🧠 **Neue Begriffe:** [Container](glossar.md#container--kubernetes), [Image](glossar.md#container--kubernetes),
> [Registry](glossar.md#container--kubernetes), [Pod](glossar.md#container--kubernetes),
> [Manifest](glossar.md#container--kubernetes), [YAML](glossar.md#container--kubernetes)

---

> 📸 **Snapshot-Routine:** In Teil B brauchst du keine neuen Snapshots. Geht etwas schief, springst du zu `k3s-frisch` zurück.

## Vorbereitung

> 💻 **Auf deinem Rechner:** Alle Befehle in Teil B laufen auf deinem Rechner, im Ordner des Repositories:

```bash
cd ~/homelab-tutorial     # dort, wo du das Repository in Kapitel 01 geklont hast
git pull                  # neueste Version des Tutorials holen
nix develop               # Werkzeuge laden (falls du Nix nutzt)
kubectl get nodes         # Verbindung zum Cluster prüfen
```

## Container, Image, Pod: was ist was?

| Begriff | Vergleich | Beispiel |
|---------|-----------|----------|
| **Image** | ein Kuchenrezept | `nginx:1.30`, ein fertig verpacktes Programm samt allem, was es braucht |
| **Registry** | das Kochbuch-Regal | Docker Hub, von dort lädt Kubernetes die Images |
| **Container** | ein gebackener Kuchen | ein laufendes Programm, gestartet aus einem Image |
| **Pod** | der Teller | die Hülle, in der Kubernetes einen (oder mehrere) Container betreibt |

Kubernetes startet nie „nackte“ Container, sondern immer **Pods**. Meist steckt genau ein Container in einem Pod.

Als erstes Beispiel nehmen wir **nginx**, einen kleinen Webserver.

## 1. Einen Pod starten, der schnelle Weg

```bash
kubectl run nginx --image=nginx:1.30
```

```
pod/nginx created
```

Schau sofort nach:

```bash
kubectl get pods
```

```
NAME    READY   STATUS              RESTARTS   AGE
nginx   0/1     ContainerCreating   0          3s
```

Kubernetes lädt gerade das Image herunter. Nach ein paar Sekunden:

```
NAME    READY   STATUS    RESTARTS   AGE
nginx   1/1     Running   0          12s
```

| Spalte | Bedeutung |
|--------|-----------|
| `READY 1/1` | 1 von 1 Containern im Pod ist bereit |
| `STATUS` | `Running`: läuft |
| `RESTARTS` | wie oft der Container abgestürzt ist und neu gestartet wurde |

Mehr Details mit `-o wide`:

```bash
kubectl get pods -o wide
```

```
NAME    READY   STATUS    RESTARTS   AGE   IP          NODE   ...
nginx   1/1     Running   0          1m    10.42.0.9   k3s    ...
```

Jeder Pod bekommt eine eigene **IP-Adresse** aus einem internen Netz (`10.42.x.x`). Diese Adresse ist nur *innerhalb* des Clusters erreichbar.

## 2. Was ist passiert? `describe`

```bash
kubectl describe pod nginx
```

Die Ausgabe ist lang. Scrolle ganz nach unten zu **Events**:

```
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  2m    default-scheduler  Successfully assigned default/nginx to k3s
  Normal  Pulling    2m    kubelet            Pulling image "nginx:1.30"
  Normal  Pulled     2m    kubelet            Successfully pulled image "nginx:1.30" in 4.1s
  Normal  Created    2m    kubelet            Created container: nginx
  Normal  Started    2m    kubelet            Started container nginx
```

Das ist die Lebensgeschichte des Pods:

1. **Scheduled**: Der *Scheduler* hat entschieden, auf welchem Node der Pod läuft. Wir haben nur einen, `k3s`.
2. **Pulling / Pulled**: Der *kubelet* (der Kubernetes-Agent auf dem Node) hat das Image geladen.
3. **Created / Started**: Der Container läuft.

> 💡 **Merke:** Wenn ein Pod nicht startet, ist `kubectl describe pod <name>` **immer** der erste Blick. Die Events
> verraten fast immer, was schiefgeht.

## 3. Was sagt die App? `logs`

```bash
kubectl logs nginx
```

```
/docker-entrypoint.sh: Configuration complete; ready for start up
2026/09/26 14:02:11 [notice] 1#1: nginx/1.30.5
2026/09/26 14:02:11 [notice] 1#1: start worker processes
```

Das ist alles, was nginx auf den Bildschirm schreibt. Mit `-f` („follow“) siehst du neue Zeilen live, Beenden mit `Strg+C`:

```bash
kubectl logs -f nginx
```

## 4. Die Webseite ansehen: `port-forward`

Der Pod hat nur eine interne IP. Für einen schnellen Test baut `kubectl` einen Tunnel von deinem Rechner zum Pod:

```bash
kubectl port-forward pod/nginx 8080:80
```

```
Forwarding from 127.0.0.1:8080 -> 80
```

Öffne im Browser <http://localhost:8080>. Du siehst **„Welcome to nginx!“**

Lass das Terminal offen und schau im zweiten Terminal auf die Logs (`kubectl logs nginx`). Dort taucht dein Seitenaufruf auf.

Beende den Tunnel mit `Strg+C`.

> 💡 `port-forward` ist ein Werkzeug zum Testen. Dauerhaft erreichbar machst du Apps mit einem **Service** (Kapitel 07).

## 5. In den Container hineinschauen: `exec`

```bash
kubectl exec -it nginx -- bash
```

Die Eingabezeile ändert sich, **du bist jetzt im Container**:

```
root@nginx:/#
```

Schau dich um:

```bash
cat /etc/os-release | head -1      # Der Container hat sein eigenes Mini-Linux
ls /usr/share/nginx/html           # Hier liegt die Webseite
```

Jetzt ändern wir die Webseite:

```bash
echo "<h1>Hallo aus dem Pod!</h1>" > /usr/share/nginx/html/index.html
exit
```

Erneut `kubectl port-forward pod/nginx 8080:80` und <http://localhost:8080> öffnen: **„Hallo aus dem Pod!“** 🎉
(Danach wieder `Strg+C`.)

| Teil | Bedeutung |
|------|-----------|
| `-it` | interaktiv, mit Terminal |
| `--` | alles danach ist der Befehl, der im Container laufen soll |
| `bash` | eine Shell starten |

## 6. Den Pod löschen

```bash
kubectl delete pod nginx
kubectl get pods
```

```
No resources found in default namespace.
```

Der Pod ist weg, und **niemand startet ihn neu**. Stell dir vor, das wäre Jellyfin gewesen und der Pod wäre wegen eines
Fehlers beendet worden. Dein Film wäre weg, bis du ihn von Hand neu startest. Genau dieses Problem löst in Kapitel 07
das **Deployment**.

## 7. Der richtige Weg: ein Manifest

`kubectl run` ist praktisch zum Ausprobieren. In der Praxis beschreibt man aber alles in **Manifesten**: YAML-Dateien,
die man speichern, versionieren und jederzeit wieder anwenden kann.

Öffne [`examples/06-erster-pod/pod.yaml`](../examples/06-erster-pod/pod.yaml):

```yaml
apiVersion: v1          # Welche Version der Kubernetes-API dieses Objekt beschreibt
kind: Pod               # Was für ein Objekt: ein Pod
metadata:
  name: nginx           # Name des Pods (muss im Namespace eindeutig sein)
  labels:
    app: nginx          # Etikett, über das man Pods später wiederfindet
spec:                   # Der Soll-Zustand: was im Pod laufen soll
  containers:
    - name: nginx                 # Name des Containers im Pod
      image: nginx:1.30           # Image von Docker Hub, mit fester Version
      ports:
        - containerPort: 80       # Port, auf dem nginx im Container lauscht
```

**Jedes** Kubernetes-Manifest hat diese vier Teile:

| Teil | Frage, die er beantwortet |
|------|---------------------------|
| `apiVersion` | In welcher „Sprachversion“ ist das geschrieben? |
| `kind` | *Was* ist das? (Pod, Deployment, Service …) |
| `metadata` | *Wie heißt* es, in welchem Namespace, mit welchen Labels? |
| `spec` | *Wie soll* es aussehen? (der Soll-Zustand) |

Anwenden:

```bash
kubectl apply -f examples/06-erster-pod/pod.yaml
```

```
pod/nginx created
```

Und jetzt der spannende Test: `kubectl port-forward pod/nginx 8080:80` → <http://localhost:8080>.

Du siehst wieder **„Welcome to nginx!“**. Deine Änderung aus Schritt 5 ist weg.

> 💡 **Die wichtigste Lektion dieses Kapitels:** Container sind **vergänglich**. Alles, was ein Container zur Laufzeit
> in sein Dateisystem schreibt, verschwindet mit ihm. Ein neuer Container startet immer frisch aus dem Image.
> Daten, die bleiben sollen (Jellyfin-Einstellungen, deine Filme …), brauchen **Volumes**. Die lernst du in Kapitel 08.

### Befehl oder Manifest?

| | `kubectl run …` (imperativ) | `kubectl apply -f …` (deklarativ) |
|--|------------------------------|-----------------------------------|
| Stil | „Tu das!“ | „So soll es sein.“ |
| Wiederholbar? | Befehl muss man sich merken | Datei liegt im Git-Repository |
| Mehrfach ausführen | Fehler: *already exists* | kein Problem, `apply` gleicht nur ab |
| Einsatz | schnell etwas ausprobieren | alles, was bleiben soll |

Probier es aus: Führe `kubectl apply -f examples/06-erster-pod/pod.yaml` noch einmal aus.

```
pod/nginx unchanged
```

Kubernetes vergleicht Soll und Ist und stellt fest: Passt schon.

### Kubernetes erklärt sich selbst

Was darf alles unter `spec.containers` stehen? Frag Kubernetes:

```bash
kubectl explain pod.spec.containers
kubectl explain pod.spec.containers.ports
```

Und so sieht der Pod aus Sicht von Kubernetes aus, inklusive allem, was Kubernetes selbst ergänzt hat:

```bash
kubectl get pod nginx -o yaml
```

Ganz unten steht ein Abschnitt `status:`. Das ist der **Ist-Zustand**, den Kubernetes selbst pflegt.

## 8. k9s: Kubernetes mit Oberfläche

Tippen ist gut zum Lernen, aber für den Überblick gibt es **k9s**, eine Oberfläche im Terminal.

```bash
k9s
```

Die wichtigsten Tasten:

| Taste | Wirkung |
|-------|---------|
| `:pod` + `Enter` | Pods anzeigen (auch `:deploy`, `:svc`, `:ns` …) |
| `0` | alle Namespaces anzeigen |
| `↑` `↓` | Pod auswählen |
| `d` | describe |
| `l` | Logs |
| `s` | Shell im Container (wie `exec`) |
| `Esc` | zurück |
| `Strg+d` | löschen (mit Rückfrage) |
| `?` | Hilfe |
| `:q` | beenden |

Drück `0` und schau dir alle Pods an, auch die aus `kube-system`, die du in Kapitel 05 kennengelernt hast.

## 9. Aufräumen

```bash
kubectl delete -f examples/06-erster-pod/pod.yaml
```

```
pod "nginx" deleted
```

## ✅ Checkpoint

- [ ] Du kannst einen Pod mit `kubectl run` und mit `kubectl apply -f` starten.
- [ ] Du hast die Events in `kubectl describe pod` gelesen.
- [ ] Du hast mit `kubectl logs` und `kubectl exec` in einen Pod geschaut.
- [ ] Du hast gesehen, dass Änderungen im Container nach dem Neustart weg sind.
- [ ] `kubectl get pods` zeigt `No resources found in default namespace.`

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| `STATUS` = `ErrImagePull` oder `ImagePullBackOff` | Tippfehler im Image-Namen oder in der Version? `kubectl describe pod` zeigt die genaue Meldung |
| `STATUS` = `Pending` | `kubectl describe pod` → Events lesen. Oft ist zu wenig RAM oder CPU frei |
| `port-forward`: `address already in use` | Port 8080 ist auf deinem Rechner belegt → anderen Port nehmen, z. B. `8888:80` |
| `exec`: `bash: executable file not found` | Manche Images haben keine bash, dann `sh` statt `bash` verwenden |
| `Error from server (AlreadyExists)` | Ein Pod mit dem Namen existiert schon: `kubectl delete pod nginx` |

## 🎓 Was du gelernt hast

- Ein **Pod** ist die kleinste Einheit in Kubernetes und enthält einen oder mehrere Container.
- `get`, `describe`, `logs`, `exec`, `port-forward`, `delete`: das sind deine wichtigsten Werkzeuge.
- **Container sind vergänglich.** Was darin geändert wird, geht beim Neustart verloren.
- Ein einzelner Pod wird **nicht** neu gestartet, wenn er gelöscht wird.
- **Manifeste** (YAML) beschreiben den Soll-Zustand: `apiVersion`, `kind`, `metadata`, `spec`.
- `kubectl apply` gleicht den Cluster an das Manifest an und kann beliebig oft ausgeführt werden.

---

⬅️ **Zurück:** [05 – k3s installieren](05-k3s-installieren.md) · ➡️ **Weiter:** [07 – Deployments & Services](07-deployments-services.md)
