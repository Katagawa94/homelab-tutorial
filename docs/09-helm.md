# 09 – Helm

> **Was du am Ende hast:** Du kannst fertige App-Pakete (Helm-Charts) finden, mit eigenen Einstellungen installieren,
> aktualisieren und zurückrollen.
>
> ⏱️ **Zeit:** ca. 45 Minuten
>
> 🧠 **Neue Begriffe:** [Helm, Chart, Values, Release](glossar.md#container--kubernetes), Repository, Revision

---

## Warum Helm?

Für linkding hast du in Kapitel 08 vier Dateien geschrieben: PVC, Deployment, Service und Secret. Größere Apps wie
Immich (Kapitel 24) oder Argo CD (Kapitel 13) bestehen aus **Dutzenden** Objekten. Die will niemand von Hand schreiben.

**Helm** ist der Paketmanager für Kubernetes, vergleichbar mit `apt` oder `nix`:

| Begriff | Bedeutung | Vergleich mit `apt` |
|---------|-----------|---------------------|
| **Chart** | ein Paket: Vorlagen für alle Kubernetes-Objekte einer App | ein `.deb`-Paket |
| **Repository** | Sammlung von Charts im Internet | eine Paketquelle |
| **Values** | deine Einstellungen, die in die Vorlagen eingesetzt werden | Konfigurationsdatei |
| **Release** | ein installiertes Chart mit Namen | ein installiertes Paket |
| **Revision** | jede Installation/Änderung eines Releases bekommt eine Nummer | – |

```
Chart (Vorlagen)  +  deine Values  ──helm──►  fertige Manifeste  ──►  Cluster
```

Als Beispiel nehmen wir **podinfo**, eine kleine Demo-App mit bunter Weboberfläche, die extra zum Lernen gebaut wurde.

## 1. Repository hinzufügen

> 💻 **Auf deinem Rechner** (im Ordner `homelab-tutorial`)

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update
```

```
"podinfo" has been added to your repositories
...Successfully got an update from the "podinfo" chart repository
Update Complete. ⎈Happy Helming!⎈
```

Was gibt es darin?

```bash
helm search repo podinfo
```

```
NAME              CHART VERSION   APP VERSION   DESCRIPTION
podinfo/podinfo   6.15.0          6.15.0        Podinfo Helm chart for Kubernetes
```

- **CHART VERSION**: Version des Pakets (der Vorlagen)
- **APP VERSION**: Version der App darin

Die Versionen können bei dir neuer sein.

> 💡 Charts für fast jede App findest du auf <https://artifacthub.io>. Manche Projekte veröffentlichen Charts auch in
> Container-Registries (**OCI**). Dann entfällt `helm repo add`, und man schreibt direkt z. B.
> `oci://ghcr.io/stefanprodan/charts/podinfo`.

## 2. Welche Einstellungen gibt es?

Jedes Chart hat Standardwerte. Anzeigen:

```bash
helm show values podinfo/podinfo | less
```

(Blättern mit Pfeiltasten, Beenden mit `q`.) Ein Ausschnitt:

```yaml
replicaCount: 1
...
ui:
  color: "#34577c"
  message: ""
...
service:
  enabled: true
  type: ClusterIP
  httpPort: 9898
  externalPort: 9898
```

Du überschreibst **nur die Werte, die du ändern willst**, in einer eigenen Datei:

```yaml
# examples/09-helm/podinfo-values.yaml
replicaCount: 2

ui:
  message: "Hallo aus meinem Homelab!"
  color: "#2e7d32"                # Hintergrundfarbe (grün)

service:
  type: LoadBalancer              # im Heimnetz erreichbar …
  externalPort: 9898              # … unter http://<VM-IP>:9898
```

## 3. Was würde Helm erzeugen?

Bevor du installierst, lass dir zeigen, welche Manifeste Helm aus Chart und Values baut:

```bash
helm template podinfo podinfo/podinfo -n lernen -f examples/09-helm/podinfo-values.yaml | less
```

Du findest darin alte Bekannte:

```yaml
# Source: podinfo/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: podinfo
...
spec:
  type: LoadBalancer
  ports:
    - port: 9898
...
# Source: podinfo/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: podinfo
...
spec:
  replicas: 2
...
            - name: PODINFO_UI_MESSAGE
              value: "Hallo aus meinem Homelab!"
```

> 💡 **Das ist das ganze Geheimnis von Helm:** Es erzeugt dieselben Deployments und Services, die du in Kapitel 07 und 08
> selbst geschrieben hast. Deine Values werden an die passenden Stellen eingesetzt. Weil du jetzt weißt, was ein Deployment
> und ein Service sind, kannst du auch jedes Chart verstehen und Fehler darin finden.

## 4. Installieren

```bash
helm install podinfo podinfo/podinfo -n lernen -f examples/09-helm/podinfo-values.yaml
```

```
NAME: podinfo
LAST DEPLOYED: Sat Sep 26 15:10:42 2026
NAMESPACE: lernen
STATUS: deployed
REVISION: 1
NOTES:
...
```

| Teil | Bedeutung |
|------|-----------|
| `podinfo` (1.) | Name des Releases, frei wählbar |
| `podinfo/podinfo` | Repository/Chart |
| `-n lernen` | Namespace |
| `-f …` | deine Values-Datei |

```bash
helm list -n lernen
kubectl get pods,services -n lernen -l app.kubernetes.io/name=podinfo
```

Öffne <http://192.168.178.11:9898>. Du siehst podinfo mit **grünem Hintergrund** und deiner Nachricht.
Lädst du mehrmals neu, wechselt der angezeigte Pod-Name, denn es laufen 2 Replicas.

## 5. Ändern: `helm upgrade`

Öffne `examples/09-helm/podinfo-values.yaml` in einem Editor und ändere:

```yaml
replicaCount: 3

ui:
  message: "Version 2 meines Homelabs"
  color: "#6a1b9a"                # lila
```

Anwenden:

```bash
helm upgrade podinfo podinfo/podinfo -n lernen -f examples/09-helm/podinfo-values.yaml
```

```
Release "podinfo" has been upgraded. Happy Helming!
...
REVISION: 2
```

Die Seite wird lila, und `kubectl get pods -n lernen` zeigt drei podinfo-Pods. Im Hintergrund hat Helm einfach die neuen
Manifeste per Rolling Update angewendet, genau wie du in Kapitel 07.

> 💡 **Praxistipp:** `helm upgrade --install …` installiert, wenn es das Release noch nicht gibt, und aktualisiert sonst.
> So brauchst du dir nur einen Befehl zu merken.

## 6. Geschichte und Rollback

```bash
helm history podinfo -n lernen
```

```
REVISION   UPDATED                    STATUS       CHART            APP VERSION   DESCRIPTION
1          Sat Sep 26 15:10:42 2026   superseded   podinfo-6.15.0   6.15.0        Install complete
2          Sat Sep 26 15:14:03 2026   deployed     podinfo-6.15.0   6.15.0        Upgrade complete
```

Zurück zu Revision 1:

```bash
helm rollback podinfo 1 -n lernen
```

```
Rollback was a success! Happy Helming!
```

Die Seite ist wieder grün. `helm history` zeigt jetzt eine **Revision 3**: Ein Rollback ist in Helm einfach eine neue
Revision mit den alten Werten.

Welche Values sind gerade aktiv?

```bash
helm get values podinfo -n lernen
```

Stell die Values-Datei danach wieder her:

```bash
git checkout examples/09-helm/podinfo-values.yaml
```

### Wo merkt sich Helm das alles?

```bash
kubectl get secrets -n lernen
```

```
NAME                            TYPE                 DATA   AGE
linkding-zugang                 Opaque               2      1h
sh.helm.release.v1.podinfo.v1   helm.sh/release.v1   1      10m
sh.helm.release.v1.podinfo.v2   helm.sh/release.v1   1      6m
sh.helm.release.v1.podinfo.v3   helm.sh/release.v1   1      2m
```

Helm speichert jede Revision als Secret **im Cluster**. Deshalb kann es jederzeit zurückrollen, auch von einem anderen Rechner aus.

## 7. Versionen festhalten

Ohne Angabe installiert Helm die **neueste** Chart-Version. Im Homelab willst du aber wissen, was läuft, und Updates
bewusst einspielen. Deshalb gibt man die Version mit an:

```bash
helm upgrade --install podinfo podinfo/podinfo --version 6.15.0 -n lernen -f examples/09-helm/podinfo-values.yaml
```

Ab Kapitel 13 steht die Version in einer Datei im Git-Repository, und in Kapitel 28 schlägt dir **Renovate**
automatisch Updates vor.

## 8. Übrigens: k3s nutzt selbst Helm

Erinnerst du dich an die Pods `helm-install-traefik-…` aus Kapitel 05? k3s hat Traefik per Helm-Chart installiert:

```bash
helm list -n kube-system
```

```
NAME          NAMESPACE    REVISION   ...   STATUS     CHART                   APP VERSION
traefik       kube-system  1          ...   deployed   traefik-<version>       v3.x.x
traefik-crd   kube-system  1          ...   deployed   traefik-crd-<version>   v3.x.x
```

(Versionen können abweichen.)

## 9. Teil B aufräumen

Du hast alle Grundlagen durch. Zeit, den Lern-Namespace zu entfernen. **Ein Namespace nimmt beim Löschen alles mit**:
Pods, Services, ConfigMaps, Secrets, PVCs (inkl. Daten!) und die Helm-Releases.

```bash
helm uninstall podinfo -n lernen
kubectl delete namespace lernen
```

```
release "podinfo" uninstalled
namespace "lernen" deleted
```

Prüfen:

```bash
kubectl get namespaces
kubectl get pv
```

`lernen` ist weg, und `kubectl get pv` meldet `No resources found`. Wegen `RECLAIMPOLICY Delete` ist auch das Volume
von linkding verschwunden. Das Repository entfernen wir nicht, `helm repo list` zeigt es weiterhin.

## ✅ Checkpoint

- [ ] `helm search repo podinfo` findet das Chart.
- [ ] Du hast mit `helm template` gesehen, welche Manifeste ein Chart erzeugt.
- [ ] podinfo lief unter <http://192.168.178.11:9898> mit deiner Nachricht.
- [ ] Du hast ein `helm upgrade` und ein `helm rollback` durchgeführt.
- [ ] Der Namespace `lernen` ist gelöscht.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| `Error: INSTALLATION FAILED: cannot re-use a name that is still in use` | Das Release existiert schon → `helm upgrade` bzw. `helm upgrade --install` benutzen |
| `Error: repo podinfo not found` | `helm repo add …` vergessen oder Tippfehler → `helm repo list` |
| Änderungen in der Values-Datei wirken nicht | Hast du beim `upgrade` `-f <datei>` angegeben? Ohne `-f` nimmt Helm die Standardwerte |
| Einrückungsfehler: `error converting YAML to JSON` | In der Values-Datei nur Leerzeichen, keine Tabs, und die Einrückung wie in `helm show values` |
| Namespace hängt in `Terminating` | Meist erledigt sich das nach 1–2 Minuten. `kubectl get all -n lernen` zeigt, worauf gewartet wird |

## 🎓 Was du gelernt hast

- **Helm-Charts** sind Vorlagen für Kubernetes-Manifeste, **Values** sind deine Einstellungen dazu.
- `helm show values` zeigt die Einstellmöglichkeiten, `helm template` die fertigen Manifeste.
- `helm install` / `upgrade` / `rollback` / `uninstall` verwalten ein **Release** mit durchnummerierten **Revisionen**.
- Chart-Versionen sollte man festhalten (`--version`).
- Ein Namespace nimmt beim Löschen alles mit, was darin liegt.

---

## 🎉 Teil B geschafft!

Du kennst jetzt die Bausteine, aus denen jede App im Homelab besteht:

| Baustein | Wofür | Kapitel |
|----------|-------|---------|
| Pod | läuft | 06 |
| Deployment | hält Pods am Leben, aktualisiert sie | 07 |
| Service (ClusterIP / LoadBalancer) | macht Pods erreichbar | 07 |
| ConfigMap / Secret | Konfiguration und Passwörter | 08 |
| PVC / PV / StorageClass | Daten, die bleiben | 08 |
| Helm | fertige Pakete aus all dem | 09 |

In **Teil C** wird es ernst: Tailscale im Cluster, Jellyfin, der Samsung-TV, GitOps und die Grafikkarte.

---

⬅️ **Zurück:** [08 – Konfiguration & Daten](08-konfiguration-daten.md) · ➡️ **Weiter:** 10 – Tailscale Operator *(folgt in Phase 3)*
