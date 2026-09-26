# 07 – Deployments & Services

> **Was du am Ende hast:** Eine App, die sich selbst heilt, sich skalieren und ohne Ausfall aktualisieren lässt und
> unter einer festen Adresse erreichbar ist, im Cluster **und** im Heimnetz.
>
> ⏱️ **Zeit:** ca. 1 Stunde
>
> 🧠 **Neue Begriffe:** [Namespace](glossar.md#container--kubernetes), [Deployment](glossar.md#container--kubernetes),
> [ReplicaSet](glossar.md#container--kubernetes), [Service](glossar.md#container--kubernetes),
> [LoadBalancer](glossar.md#container--kubernetes), Labels & Selectors, Rolling Update

---

## Die Beispiel-App: whoami

**whoami** ist ein winziger Webserver, der bei jedem Aufruf antwortet: *„Ich bin Pod XY.“* Damit sieht man hervorragend,
welcher Pod gerade eine Anfrage beantwortet.

Alle Dateien liegen in [`examples/07-deployments-services/`](../examples/07-deployments-services/).

## 1. Ein eigener Namespace

Bisher lief alles im Namespace `default`. Für Teil B legen wir einen eigenen „Ordner“ an: **`lernen`**.
Am Ende von Teil B löschen wir ihn, und alles darin ist mit einem Befehl aufgeräumt.

```yaml
# examples/07-deployments-services/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lernen
```

```bash
kubectl apply -f examples/07-deployments-services/namespace.yaml
kubectl get namespaces
```

```
NAME              STATUS   AGE
default           Active   2d
kube-node-lease   Active   2d
kube-public       Active   2d
kube-system       Active   2d
lernen            Active   5s
```

> 💡 Ab jetzt hängst du an `kubectl`-Befehle **`-n lernen`** an, sonst schaut `kubectl` im Namespace `default` nach.

## 2. Das Deployment

Ein **Deployment** sagt Kubernetes: *„Von diesem Pod sollen immer N Stück laufen.“*

```yaml
# examples/07-deployments-services/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  namespace: lernen
  labels:
    app: whoami
spec:
  replicas: 3                     # So viele Pods sollen laufen
  selector:
    matchLabels:
      app: whoami                 # Das Deployment "besitzt" alle Pods mit diesem Label …
  template:                       # … und so sieht jeder dieser Pods aus:
    metadata:
      labels:
        app: whoami               # muss zum selector oben passen!
    spec:
      containers:
        - name: whoami
          image: traefik/whoami:v1.11.0
          ports:
            - containerPort: 80
          resources:
            requests:             # So viel wird für den Pod reserviert
              cpu: 10m            # 10 Milli-CPUs = 1 % eines Kerns
              memory: 16Mi
            limits:               # Mehr darf der Pod nicht verbrauchen
              memory: 32Mi
```

Was ist neu gegenüber dem Pod aus Kapitel 06?

- **`template`**: Das ist *genau* das, was in Kapitel 06 unter `metadata` und `spec` des Pods stand. Das Deployment ist
  also eine Hülle um eine Pod-Vorlage.
- **`replicas`**: wie viele Kopien laufen sollen.
- **`selector`**: woran das Deployment „seine“ Pods erkennt, nämlich am **Label** `app: whoami`.
- **`resources`**: Wie viel CPU und RAM der Pod bekommt. **Requests** werden reserviert, **Limits** sind die Obergrenze.
  Überschreitet ein Pod sein RAM-Limit, wird er beendet (`OOMKilled`). So kann eine App nicht den ganzen Server lahmlegen.

```bash
kubectl apply -f examples/07-deployments-services/deployment.yaml
kubectl get deployments,replicasets,pods -n lernen
```

```
NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/whoami   3/3     3            3           20s

NAME                                DESIRED   CURRENT   READY   AGE
replicaset.apps/whoami-6d8f9c7b5d   3         3         3       20s

NAME                          READY   STATUS    RESTARTS   AGE
pod/whoami-6d8f9c7b5d-4xk2p   1/1     Running   0          20s
pod/whoami-6d8f9c7b5d-9mzq7   1/1     Running   0          20s
pod/whoami-6d8f9c7b5d-tw8rn   1/1     Running   0          20s
```

Es sind drei Ebenen entstanden:

```
Deployment  whoami                        ← was du geschrieben hast
└── ReplicaSet  whoami-6d8f9c7b5d         ← vom Deployment angelegt, hält die Anzahl
    ├── Pod  whoami-6d8f9c7b5d-4xk2p      ← vom ReplicaSet angelegt
    ├── Pod  whoami-6d8f9c7b5d-9mzq7
    └── Pod  whoami-6d8f9c7b5d-tw8rn
```

Die Namen verraten die Abstammung: `whoami` → `whoami-6d8f9c7b5d` → `whoami-6d8f9c7b5d-4xk2p`.
Das **ReplicaSet** fasst man praktisch nie direkt an. Wozu es gut ist, siehst du beim Update in Schritt 6.

## 3. Selbstheilung

Öffne ein **zweites Terminal** und beobachte die Pods live (`-w` = watch):

```bash
kubectl get pods -n lernen -w
```

Lösche im ersten Terminal einen Pod. Nimm einen Namen aus deiner Liste:

```bash
kubectl delete pod whoami-6d8f9c7b5d-4xk2p -n lernen
```

Im zweiten Terminal siehst du:

```
whoami-6d8f9c7b5d-4xk2p   1/1     Terminating         0          5m
whoami-6d8f9c7b5d-z7lq2   0/1     Pending             0          0s
whoami-6d8f9c7b5d-z7lq2   0/1     ContainerCreating   0          0s
whoami-6d8f9c7b5d-z7lq2   1/1     Running             0          1s
```

Sofort entsteht ein **neuer Pod** mit neuem Namen. Das ReplicaSet hat bemerkt: *„Soll 3, Ist 2“* und nachgelegt.
Das ist der **Kontroll-Kreislauf** (*Reconciliation Loop*), das Herzstück von Kubernetes:

```
    ┌──► Ist-Zustand beobachten ──► mit Soll vergleichen ──► Unterschied beheben ──┐
    └─────────────────────────────────────────────────────────────────────────────┘
```

Lass das zweite Terminal für die nächsten Schritte offen.

## 4. Skalieren

Mehr Pods? Schnell per Befehl:

```bash
kubectl scale deployment whoami --replicas=5 -n lernen
```

Im zweiten Terminal erscheinen zwei neue Pods. Aber Achtung: Jetzt stimmt der Cluster nicht mehr mit deiner Datei
überein (dort steht `replicas: 3`). Wendest du die Datei erneut an, gilt wieder die Datei:

```bash
kubectl apply -f examples/07-deployments-services/deployment.yaml
```

Zwei Pods gehen in `Terminating`, es bleiben 3.

> 💡 **Merke:** Die **Datei** ist die Wahrheit. Änderungen per Befehl sind schnell, gehen aber beim nächsten `apply`
> verloren. In Kapitel 13 (GitOps) passiert dieses „Zurücksetzen auf die Datei“ sogar automatisch.

## 5. Services: eine feste Adresse

Pods kommen und gehen, und jeder neue Pod bekommt eine neue IP. Wie sollen andere Apps sie finden?
Mit einem **Service**: einer festen Adresse, die Anfragen an alle passenden Pods verteilt.

```yaml
# examples/07-deployments-services/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: whoami
  namespace: lernen
  labels:
    app: whoami
spec:
  type: ClusterIP                 # nur innerhalb des Clusters erreichbar (Standard)
  selector:
    app: whoami                   # leitet an alle Pods mit diesem Label weiter
  ports:
    - port: 80                    # Port des Services
      targetPort: 80              # Port im Container
```

Wieder das Label `app: whoami`! **Labels und Selectors** sind der Klebstoff in Kubernetes: Der Service kennt keine
Pod-Namen, er sucht einfach nach allen Pods mit passendem Label.

```bash
kubectl apply -f examples/07-deployments-services/service.yaml
kubectl get service -n lernen
```

```
NAME     TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
whoami   ClusterIP   10.43.112.45   <none>        80/TCP    5s
```

Welche Pods stecken dahinter?

```bash
kubectl describe service whoami -n lernen | grep -i endpoints
```

```
Endpoints:         10.42.0.14:80,10.42.0.15:80,10.42.0.17:80
```

Drei Pod-IPs, genau unsere drei whoami-Pods.

### Test von innen

Eine `ClusterIP` ist nur *im* Cluster erreichbar. Wir starten deshalb einen Wegwerf-Pod mit Werkzeugen und testen von dort:

```bash
kubectl run test -n lernen --rm -it --restart=Never --image=busybox:1.38 -- sh
```

(`--rm` löscht den Pod beim Verlassen automatisch.) In der Shell des Test-Pods:

```sh
wget -qO- http://whoami
```

```
Hostname: whoami-6d8f9c7b5d-9mzq7
IP: 127.0.0.1
IP: 10.42.0.15
RemoteAddr: 10.42.0.20:43512
GET / HTTP/1.1
Host: whoami
...
```

Führe den Befehl mehrmals aus (Pfeiltaste ↑). Der **Hostname wechselt**, weil der Service die Anfragen auf alle drei Pods verteilt.

Beachte: Wir haben einfach `http://whoami` geschrieben. Das Cluster-DNS (CoreDNS) kennt jeden Service beim Namen:

| Adresse | Funktioniert von |
|---------|------------------|
| `whoami` | Pods im selben Namespace |
| `whoami.lernen` | Pods in allen Namespaces |
| `whoami.lernen.svc.cluster.local` | überall im Cluster (der vollständige Name) |

So werden später Sonarr und qBittorrent miteinander reden: über Service-Namen.

Test-Pod verlassen mit `exit`.

## 6. Ins Heimnetz: Service vom Typ LoadBalancer

Für den Samsung-TV reicht „nur im Cluster“ nicht. Der Typ **`LoadBalancer`** macht einen Service unter der IP der VM
erreichbar. In k3s erledigt das **ServiceLB**.

```yaml
# examples/07-deployments-services/service-lan.yaml
apiVersion: v1
kind: Service
metadata:
  name: whoami-lan
  namespace: lernen
  labels:
    app: whoami
spec:
  type: LoadBalancer              # k3s (ServiceLB) öffnet den Port auf der IP der VM
  selector:
    app: whoami
  ports:
    - port: 8080                  # http://<VM-IP>:8080 (Port 80 belegt bereits Traefik)
      targetPort: 80
```

```bash
kubectl apply -f examples/07-deployments-services/service-lan.yaml
kubectl get service -n lernen
```

```
NAME         TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)          AGE
whoami       ClusterIP      10.43.112.45    <none>           80/TCP           5m
whoami-lan   LoadBalancer   10.43.201.88    192.168.178.11   8080:31544/TCP   5s
```

Unter `EXTERNAL-IP` steht die IP deiner VM. Öffne im Browser <http://192.168.178.11:8080> und lade die Seite mehrmals neu.

Oder im Terminal:

```bash
for i in 1 2 3 4 5 6; do curl -s http://192.168.178.11:8080 | grep Hostname; done
```

```
Hostname: whoami-6d8f9c7b5d-tw8rn
Hostname: whoami-6d8f9c7b5d-9mzq7
Hostname: whoami-6d8f9c7b5d-z7lq2
...
```

> 💡 Zwei Services zeigen jetzt auf dieselben Pods, einer intern und einer fürs Heimnetz. Möglich ist das, weil beide
> nur über das Label auswählen. Da der Port auf der VM geöffnet wird, klappt übrigens auch <http://k3s:8080> über Tailscale.

### Die Service-Typen im Überblick

| Typ | Erreichbar von | Einsatz im Homelab |
|-----|----------------|--------------------|
| `ClusterIP` | nur im Cluster | Apps untereinander (Sonarr → qBittorrent) |
| `NodePort` | `<VM-IP>:30000–32767` | selten, unhandliche Ports |
| `LoadBalancer` | `<VM-IP>:<beliebiger Port>` | Heimnetz, z. B. Jellyfin für den Samsung-TV |
| *Tailscale* (Kapitel 10) | Tailnet mit HTTPS | Zugriff von unterwegs |

## 7. Rolling Update: neue Version ohne Ausfall

Eine neue Version von whoami ist erschienen. In [`deployment-v2.yaml`](../examples/07-deployments-services/deployment-v2.yaml)
sind zwei Dinge anders:

```bash
diff examples/07-deployments-services/deployment.yaml examples/07-deployments-services/deployment-v2.yaml
```

Ausgabe (gekürzt):

```diff
< # Kapitel 07: Ein Deployment sorgt dafür, dass immer 3 whoami-Pods laufen.
---
> # Kapitel 07: Version 2 des Deployments, für das Rolling Update.
> # Unterschiede zu deployment.yaml: neues Image (v1.12.0) und ein Name, den whoami anzeigt.
...
<           image: traefik/whoami:v1.11.0
---
>           image: traefik/whoami:v1.12.0   # geändert
>           env:                            # neu
>             - name: WHOAMI_NAME
>               value: version-2
```

Bevor du etwas anwendest, kannst du Kubernetes fragen, **was sich ändern würde**:

```bash
kubectl diff -f examples/07-deployments-services/deployment-v2.yaml
```

Jetzt anwenden und im zweiten Terminal zuschauen:

```bash
kubectl apply -f examples/07-deployments-services/deployment-v2.yaml
kubectl rollout status deployment/whoami -n lernen
```

```
Waiting for deployment "whoami" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "whoami" rollout to finish: 2 out of 3 new replicas have been updated...
deployment "whoami" successfully rolled out
```

Kubernetes ersetzt die Pods **nacheinander**: neuen Pod starten, warten bis er läuft, alten beenden, nächster.
So ist die App die ganze Zeit erreichbar. Prüfe es:

```bash
curl -s http://192.168.178.11:8080 | head -2
```

```
Name: version-2
Hostname: whoami-7f4b8d6c9a-kq5xz
```

Und hier kommt das ReplicaSet ins Spiel:

```bash
kubectl get replicasets -n lernen
```

```
NAME                DESIRED   CURRENT   READY   AGE
whoami-6d8f9c7b5d   0         0         0       20m     ← alte Version, auf 0 geschrumpft
whoami-7f4b8d6c9a   3         3         3       1m      ← neue Version
```

Für jede Version gibt es ein ReplicaSet. Das alte bleibt (leer) stehen, damit man **zurückrollen** kann.

### Zurückrollen

Die neue Version macht Probleme? Ein Befehl:

```bash
kubectl rollout history deployment/whoami -n lernen
kubectl rollout undo deployment/whoami -n lernen
```

Nach ein paar Sekunden zeigt `curl` keinen `Name:` mehr an, und die alte Version läuft wieder.

> 💡 Auch hier gilt: Das `undo` hat den Cluster verändert, nicht deine Dateien. Im echten Betrieb änderst du danach die
> Datei, damit Datei und Cluster wieder übereinstimmen.

## 8. Experiment: Labels sind alles

Was passiert, wenn ein Pod sein Label verliert? Nimm einen Pod-Namen aus `kubectl get pods -n lernen`:

```bash
kubectl label pod <POD-NAME> app- -n lernen      # "app-" entfernt das Label "app"
kubectl get pods -n lernen --show-labels
```

```
NAME                      READY   STATUS    ...   LABELS
whoami-6d8f9c7b5d-9mzq7   1/1     Running   ...   pod-template-hash=6d8f9c7b5d
whoami-6d8f9c7b5d-tw8rn   1/1     Running   ...   app=whoami,pod-template-hash=6d8f9c7b5d
whoami-6d8f9c7b5d-z7lq2   1/1     Running   ...   app=whoami,pod-template-hash=6d8f9c7b5d
whoami-6d8f9c7b5d-hx9w4   1/1     Running   ...   app=whoami,pod-template-hash=6d8f9c7b5d   ← neu!
```

Der Pod ohne Label läuft weiter, aber:

- Das ReplicaSet zählt ihn nicht mehr mit und hat **einen neuen gestartet**.
- Der Service schickt ihm **keine Anfragen** mehr.

Er ist ein „Waise“. Lösch ihn: `kubectl delete pod <POD-NAME> -n lernen`.

## 9. Aufräumen

Wir löschen alles mit dem Label `app=whoami`, aber nicht den Namespace, den brauchen wir in Kapitel 08 noch:

```bash
kubectl delete deployment,service -l app=whoami -n lernen
```

```
deployment.apps "whoami" deleted
service "whoami" deleted
service "whoami-lan" deleted
```

## ✅ Checkpoint

- [ ] Der Namespace `lernen` existiert.
- [ ] Du hast gesehen, wie ein gelöschter Pod automatisch ersetzt wird.
- [ ] Du hast whoami im Cluster über `http://whoami` und im Heimnetz über `http://192.168.178.11:8080` erreicht.
- [ ] Du hast ein Rolling Update und ein Rollback durchgeführt.
- [ ] `kubectl get all -n lernen` zeigt nur noch `No resources found`.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| `kubectl get pods` zeigt nichts | `-n lernen` vergessen? |
| `EXTERNAL-IP` bleibt `<pending>` | Der Port ist schon belegt (z. B. 80/443 durch Traefik) → anderen Port wählen. Nachsehen mit `kubectl get pods -n kube-system -l svccontroller.k3s.cattle.io/svcname=whoami-lan` |
| `http://192.168.178.11:8080` lädt nicht | `kubectl get endpointslices -n lernen`: Stehen dort IPs? Wenn nicht, passt der Selector nicht zu den Pod-Labels |
| `selector does not match template labels` | `spec.selector.matchLabels` und `spec.template.metadata.labels` müssen übereinstimmen |
| Pod mit Status `OOMKilled` | Das RAM-Limit ist zu niedrig → `limits.memory` erhöhen |

## 🎓 Was du gelernt hast

- **Namespaces** gruppieren zusammengehörige Objekte.
- Ein **Deployment** hält eine gewünschte Anzahl Pods am Leben, über ein **ReplicaSet**.
- Der **Kontroll-Kreislauf** vergleicht ständig Soll und Ist und behebt Unterschiede.
- **Requests** reservieren Ressourcen, **Limits** begrenzen sie.
- Ein **Service** gibt Pods eine feste Adresse und einen DNS-Namen. Er findet die Pods über **Labels**.
- `ClusterIP` ist nur für den Cluster, `LoadBalancer` fürs Heimnetz.
- **Rolling Updates** tauschen Pods ohne Ausfall aus, `rollout undo` rollt zurück.
- `kubectl diff` zeigt vorher, was ein `apply` ändern würde.

---

⬅️ **Zurück:** [06 – Erster Pod](06-erster-pod.md) · ➡️ **Weiter:** [08 – Konfiguration & Daten](08-konfiguration-daten.md)
