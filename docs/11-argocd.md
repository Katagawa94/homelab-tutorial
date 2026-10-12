# 11 – GitOps mit Argo CD

> **Was du am Ende hast:** Argo CD läuft im Cluster und sorgt dafür, dass der Cluster **immer genau dem Inhalt dieses
> Git-Repositories** entspricht. Änderungen machst du ab jetzt per `git push`, nicht mehr per `kubectl apply`.
>
> ⏱️ **Zeit:** ca. 1,5 Stunden
>
> 🧠 **Neue Begriffe:** [GitOps](glossar.md#container--kubernetes), [Argo CD](glossar.md#container--kubernetes),
> [Application](glossar.md#container--kubernetes), [App-of-Apps](glossar.md#container--kubernetes),
> [Sync, Prune, Self-Heal](glossar.md#container--kubernetes), [Personal Access Token](glossar.md#netzwerk)

---

> 📸 **Snapshot-Routine:** Snapshot der VM anlegen (z. B. `vor-argocd`).

## Das Problem

Bisher hast du den Cluster mit `kubectl apply` und `helm install` von deinem Rechner aus verändert. Das hat Nachteile:

- Was läuft *wirklich* im Cluster? Stimmt das noch mit den Dateien überein?
- Wer hat wann was geändert?
- Nach einem Totalausfall: Welche Befehle waren das noch mal, in welcher Reihenfolge?

## Die Idee: GitOps

**Das Git-Repository ist die einzige Wahrheit.** Ein Programm im Cluster, hier **Argo CD**, schaut regelmäßig ins
Repository und gleicht den Cluster daran an. Genau das hat in Kapitel 07 der Kontroll-Kreislauf mit Pods gemacht,
nur eine Ebene höher:

```
 Du ── git push ──► GitHub-Repository ◄── schaut alle 3 Min. nach ── Argo CD (im Cluster)
                                                                         │
                                                        gleicht an ◄─────┘
                                                            ▼
                                                        Cluster
```

| Vorher | Mit GitOps |
|--------|------------|
| `kubectl apply -k …` | Datei ändern → `git commit` → `git push` |
| Rückgängig: „Was war noch mal vorher?“ | `git revert` |
| Geschichte: keine | `git log` zeigt jede Änderung |
| Neuaufbau: viele Befehle aus dem Gedächtnis | Argo CD installieren und auf das Repository zeigen, der Rest passiert von selbst |

## Wie ist `kubernetes/` aufgebaut?

```
kubernetes/
├── bootstrap/
│   └── root.yaml             ← die "Wurzel": einmalig von Hand angewendet
├── aktiv/                    ← jede Datei hier = eine App, die Argo CD ausrollt
├── katalog/                  ← Vorlagen für alle Apps, die es gibt
│   ├── argocd.yaml           (dieses Kapitel)
│   ├── tailscale-operator.yaml
│   ├── hallo.yaml            (Demo-App zum Ausprobieren)
│   ├── sealed-secrets.yaml   (Kapitel 12)
│   ├── vaultwarden.yaml      (Kapitel 13)
│   ├── nextcloud.yaml        (Kapitel 14)
│   ├── pihole.yaml           (Kapitel 15)
│   └── …                     (Jellyfin, *arr-Stack, Immich …)
├── infrastructure/           ← Values und Zusatz-Manifeste für Helm-Charts
├── apps/                     ← unsere eigenen Manifeste (Vaultwarden, Nextcloud …)
└── secrets/                  ← verschlüsselte Secrets (Kapitel 12)
```

In Argo CD beschreibt eine **Application**: *„Nimm diese Manifeste (aus Git oder einem Helm-Chart) und rolle sie in
diesen Namespace aus.“* Die Application `root` zeigt auf den Ordner `aktiv/`, und der enthält wiederum Applications.
Dieses Muster heißt **App-of-Apps**:

```
Application "root"  ──► kubernetes/aktiv/
                          ├── argocd.yaml              ──► Helm-Chart argo-cd
                          ├── tailscale-operator.yaml  ──► Helm-Chart tailscale-operator
                          ├── vaultwarden.yaml         ──► kubernetes/apps/vaultwarden
                          └── …
```

**Eine App aktivieren = ihre Datei aus `katalog/` nach `aktiv/` kopieren und pushen.** So bestimmst du selbst,
wann welche App dazukommt.

## 1. Push-Zugang zum Repository

> 💻 **Auf deinem Rechner**

Ab jetzt schreibst du ins Repository. Am einfachsten geht das per SSH mit dem Key, den du in Kapitel 01 bei GitHub hinterlegt hast:

```bash
git remote set-url origin git@github.com:Katagawa94/homelab-tutorial.git
git pull
```

> 💡 **Welcher Branch?** Argo CD folgt dem **Standard-Branch** des Repositories (`HEAD`). Welcher das ist, siehst du auf
> GitHub unter **Settings → General → Default branch**. Arbeite ab jetzt auf genau diesem Branch.

> ⚠️ **Öffentliches Repository = alles ist öffentlich.** Dieses Repository ist öffentlich, damit Argo CD es ohne
> Zugangsdaten lesen kann und die Tutorial-Website funktioniert. Das heißt: **Alles, was du committest, kann jeder lesen.**
> Deshalb gelangen Zugangsdaten in diesem Tutorial nur **verschlüsselt** ins Repository (Kapitel 12). Vor jedem Commit
> kurz `git diff --staged` ansehen.

> 💡 **Eigene Kopie?** Wenn du das Tutorial mit einem **eigenen** Repository (Fork) nachbaust, ersetze überall in
> `kubernetes/` die Adresse `github.com/Katagawa94/homelab-tutorial` durch deine:
> `grep -rl 'Katagawa94/homelab-tutorial' kubernetes/ | xargs sed -i 's#Katagawa94/homelab-tutorial#<DEIN-NAME>/<DEIN-REPO>#g'`

## 2. Nur bei privatem Repository: ein Lese-Token für Argo CD

Ein **öffentliches** Repository kann Argo CD ohne Zugangsdaten lesen, **dann überspringst du die Schritte 2 und 4**.

Ist dein Repository **privat**, braucht Argo CD einen Schlüssel zum Lesen. Wir erstellen einen
**Fine-grained Personal Access Token**, der nur dieses eine Repository lesen darf:

1. GitHub → Profilbild → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**
2. **Token name:** `argocd-homelab`
3. **Expiration:** z. B. 1 Jahr (trag dir die Erneuerung in den Kalender ein!)
4. **Repository access:** *Only select repositories* → `homelab-tutorial`
5. **Permissions → Repository permissions → Contents:** `Read-only`
6. **Generate token** und den Token (`github_pat_…`) in den Passwortmanager kopieren.

## 3. Argo CD installieren

Argo CD soll sich später selbst über Git verwalten. Irgendwer muss es aber zum ersten Mal installieren. Dieser erste
Schritt heißt **Bootstrap**, und den machen wir mit Helm.

Die Einstellungen in [`kubernetes/infrastructure/argocd/values.yaml`](../kubernetes/infrastructure/argocd/values.yaml):

```yaml
configs:
  params:
    # Argo CD selbst spricht nur HTTP. HTTPS übernimmt der Tailscale-Ingress
    server.insecure: true

dex:
  enabled: false                  # Login über externe Anbieter (GitHub, Google …)
notifications:
  enabled: false                  # Benachrichtigungen (Slack, E-Mail …)
```

Installieren:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version 10.9.2 \
  -f kubernetes/infrastructure/argocd/values.yaml \
  --wait
```

Die Weboberfläche kommt, wie whoami in Kapitel 10, per Tailscale-Ingress ins Tailnet:

```bash
kubectl apply -f kubernetes/infrastructure/argocd/manifests/ingress.yaml
kubectl get pods -n argocd
```

```
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          1m
argocd-applicationset-controller-5d8c7f9b4-7xk2p    1/1     Running   0          1m
argocd-redis-6f9d8c7b5-q2m4x                        1/1     Running   0          1m
argocd-repo-server-7c9f8d6b4-lx7kd                  1/1     Running   0          1m
argocd-server-5b7d9c8f6-9mzq7                       1/1     Running   0          1m
```

| Pod | Aufgabe |
|-----|---------|
| `repo-server` | holt das Git-Repository und erzeugt daraus Manifeste (auch aus Helm-Charts und Kustomize) |
| `application-controller` | vergleicht Soll (Git) und Ist (Cluster) und gleicht an |
| `server` | Weboberfläche und API |
| `redis` | Zwischenspeicher |
| `applicationset-controller` | erzeugt Applications aus Vorlagen (brauchen wir nicht, schadet aber nicht) |

### Anmelden

Das erste Admin-Passwort hat Argo CD zufällig erzeugt und in einem Secret abgelegt:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d; echo
```

Öffne <https://argocd.tail1a2b3c.ts.net> und melde dich mit **`admin`** und diesem Passwort an.

**Sofort ändern:** links **User Info → Update Password**, und das neue Passwort in den Passwortmanager. Danach das
Start-Passwort löschen:

```bash
kubectl delete secret argocd-initial-admin-secret -n argocd
```

## 4. Nur bei privatem Repository: Zugangsdaten hinterlegen

Argo CD erkennt Zugangsdaten für Repositories an einem Secret mit einem bestimmten **Label**
(`<TOKEN>` durch deinen `github_pat_…` ersetzen):

```bash
kubectl create secret generic repo-homelab -n argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/Katagawa94/homelab-tutorial.git \
  --from-literal=username=git \
  --from-literal=password='<TOKEN>'
kubectl label secret repo-homelab -n argocd argocd.argoproj.io/secret-type=repository
```

In der Weboberfläche unter **Settings → Repositories** steht das Repository jetzt mit **CONNECTION STATUS: Successful**. ✅

(Bei einem öffentlichen Repository taucht es dort erst auf, sobald die erste Application es benutzt, nämlich in Schritt 5.)

## 5. Die Wurzel pflanzen

[`kubernetes/bootstrap/root.yaml`](../kubernetes/bootstrap/root.yaml):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Katagawa94/homelab-tutorial.git
    targetRevision: HEAD          # HEAD = Standard-Branch des Repositories
    path: kubernetes/aktiv
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true                 # Datei aus aktiv/ gelöscht → Application wird entfernt
      selfHeal: true              # Änderungen am Cluster vorbei werden zurückgesetzt
```

Das ist der **letzte `kubectl apply`** für Dinge in `kubernetes/`:

```bash
kubectl apply -f kubernetes/bootstrap/root.yaml
```

In der Weboberfläche erscheint die Kachel **root**: *Healthy* und *Synced*, aber noch ohne Inhalt, denn `aktiv/` ist leer.

### Die Begriffe in der Oberfläche

| Status | Bedeutung |
|--------|-----------|
| **Synced** | Cluster entspricht Git |
| **OutOfSync** | Cluster weicht von Git ab |
| **Healthy** | alle Objekte laufen (Pods bereit, PVCs gebunden …) |
| **Progressing** | wird gerade ausgerollt |
| **Degraded** | etwas ist kaputt (z. B. Pod im `CrashLoopBackOff`) |

| Einstellung in `syncPolicy` | Bedeutung |
|-----------------------------|-----------|
| `automated` | Änderungen in Git automatisch ausrollen (**Sync**) |
| `prune: true` | Was aus Git gelöscht wurde, wird auch im Cluster gelöscht |
| `selfHeal: true` | Wer am Cluster „vorbei“ etwas ändert, wird zurückgesetzt |

## 6. Die bestehenden Apps an Argo CD übergeben

Tailscale Operator und Argo CD selbst laufen bereits, allerdings per Hand mit Helm installiert. Argo CD kann sie
**übernehmen**: Es rendert dieselben Manifeste und stellt fest, dass die Objekte schon existieren. Nichts wird neu gestartet.

### Helm „vergessen lassen“

Helm führt über seine Installationen Buch (Kapitel 09: die `sh.helm.release…`-Secrets). Ab jetzt ist Argo CD zuständig.
Wir löschen nur Helms **Buchführung**, die Apps selbst bleiben stehen:

```bash
kubectl delete secret -n tailscale -l owner=helm,name=tailscale-operator
kubectl delete secret -n argocd -l owner=helm,name=argocd
helm list -A
```

`helm list -A` zeigt die beiden jetzt nicht mehr an, Traefik aus `kube-system` aber schon. Die Pods laufen unverändert weiter.

> ⚠️ Nicht `helm uninstall` benutzen, das würde die Apps löschen!

### Aktivieren

Die Versionen in `katalog/` müssen zu dem passen, was du installiert hast (`1.102.4` für den Tailscale Operator und
`10.9.2` für Argo CD). Hast du neuere genommen, passe die Dateien vorher an.

```bash
cp kubernetes/katalog/{argocd,tailscale-operator}.yaml kubernetes/aktiv/
git add kubernetes/aktiv/
git commit -m "Argo CD übernimmt Argo CD und den Tailscale Operator"
git push
```

Argo CD schaut alle drei Minuten ins Repository. Nicht warten? In der Oberfläche bei **root** auf **Refresh** klicken.

Nach kurzer Zeit erscheinen zwei neue Kacheln, **argocd** und **tailscale-operator**. Beide sollten nach ein, zwei
Minuten **Synced** und **Healthy** sein.

## 7. Die erste App per Git: `hallo`

Zum Ausprobieren gibt es eine kleine Demo-App: **hallo**, das whoami aus Kapitel 07. Diesmal aber nicht per
`kubectl apply`, sondern so, wie ab jetzt **jede** App ins Homelab kommt. Die Manifeste liegen in
[`kubernetes/apps/hallo/`](../kubernetes/apps/hallo/): Namespace, Deployment, Service und ein Tailscale-Ingress.

```bash
cp kubernetes/katalog/hallo.yaml kubernetes/aktiv/
git add kubernetes/aktiv/hallo.yaml
git commit -m "Demo-App hallo aktivieren"
git push
```

Klick in Argo CD auf **root** → **Refresh**. Eine neue Kachel **hallo** erscheint. Klick darauf: Du siehst den ganzen
Baum, den du in Teil B kennengelernt hast, als Bild:

```
hallo (Application)
├── Namespace hallo
├── Service hallo
├── Ingress hallo
└── Deployment hallo
    └── ReplicaSet hallo-5f7d8c9b6f
        └── Pod hallo-5f7d8c9b6f-xk2lp
```

Öffne <https://hallo.tail1a2b3c.ts.net>. Ganz oben steht `Name: hallo-von-argocd`.

## 8. Self-Heal ausprobieren

Jetzt kommt der spannende Teil. Mach etwas kaputt:

```bash
kubectl scale deployment hallo -n hallo --replicas=0
kubectl get pods -n hallo -w
```

Innerhalb von Sekunden bemerkt Argo CD: *„In Git steht `replicas: 1`, im Cluster `0`.“* Und stellt es wieder her.
In der Oberfläche siehst du kurz **OutOfSync**, dann wieder **Synced**.

Noch mal, radikaler:

```bash
kubectl delete service hallo -n hallo
```

Kurz danach ist der Service wieder da.

## 9. Eine Änderung per Git

Öffne `kubernetes/apps/hallo/deployment.yaml` und ändere den Namen, den whoami anzeigt:

```yaml
          env:
            - name: WHOAMI_NAME   # Kapitel 11: diesen Wert per Git ändern
              value: geaendert-per-git
```

```bash
git diff                          # Was habe ich geändert?
git commit -am "hallo: neuer Name"
git push
```

Klick in Argo CD auf **Refresh** (oder warte drei Minuten). Die App **hallo** wird **OutOfSync**, dann synchronisiert
Argo CD und tauscht den Pod per Rolling Update aus (Kapitel 07). Lade <https://hallo.tail1a2b3c.ts.net> neu:
`Name: geaendert-per-git`.

**Das ist ab jetzt dein Arbeitsablauf:** Datei ändern → commit → push → Argo CD erledigt den Rest.

## 10. Die Demo wieder entfernen

Die Demo-App hat ihren Zweck erfüllt. Eine App deaktivierst du, indem du ihre Datei aus `aktiv/` löschst:

```bash
git rm kubernetes/aktiv/hallo.yaml
git commit -m "Demo-App hallo entfernen"
git push
```

Nach dem nächsten Sync ist die Kachel **hallo** verschwunden. Aber:

```bash
kubectl get pods -n hallo
```

Der Pod läuft noch! Das ist Absicht (siehe nächster Abschnitt): Ohne *Finalizer* entfernt Argo CD nur die
**Application**, nicht die Objekte, die sie angelegt hat. Aufräumen machst du bewusst selbst. Ein Namespace nimmt dabei
alles mit (Kapitel 09):

```bash
kubectl delete namespace hallo
```

Die Manifeste in `kubernetes/apps/hallo/` bleiben übrigens im Repository. Willst du später noch einmal üben, kopierst du
einfach `katalog/hallo.yaml` wieder nach `aktiv/`.

## 11. Sicherheitsnetze

Mit `prune: true` löscht Argo CD alles, was aus Git verschwindet. Damit ein Versehen keine Daten kostet, gibt es zwei Schutzmechanismen:

1. **PVCs werden nie automatisch gelöscht.** Sie haben die Annotation
   `argocd.argoproj.io/sync-options: Prune=false`. Argo CD zeigt sie dann als „müsste gelöscht werden“ an, tut es aber nicht.
2. **Applications ohne Finalizer.** Löschst du eine Datei aus `aktiv/`, verschwindet nur die *Application*. Die
   Kubernetes-Objekte, die sie angelegt hat, bleiben stehen, und du räumst sie bewusst selbst auf.

## 12. Die Argo-CD-Kommandozeile (optional)

Alles aus der Oberfläche geht auch im Terminal (`argocd` ist in der `flake.nix` enthalten):

```bash
argocd login argocd.tail1a2b3c.ts.net --grpc-web --username admin
argocd app list
argocd app get vaultwarden
argocd app sync vaultwarden          # sofort synchronisieren statt 3 Minuten warten
```

## ✅ Checkpoint

- [ ] `https://argocd.<tailnet>.ts.net` öffnet Argo CD, das Start-Passwort ist geändert und gelöscht.
- [ ] Unter **Settings → Repositories** ist dein Repository **Successful** (bei privatem Repository).
- [ ] Die Apps `root`, `argocd` und `tailscale-operator` sind **Synced** und **Healthy**.
- [ ] `helm list -A` zeigt nur noch `traefik` und `traefik-crd`.
- [ ] Du hast Self-Heal beobachtet (hallo kam von allein zurück).
- [ ] Du hast eine Änderung per `git push` ausgerollt und die Demo-App wieder entfernt.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Repository: `authentication required` / `repository not found` | Token falsch, abgelaufen oder ohne Zugriff auf das Repository. Secret löschen und neu anlegen (Schritt 4), Label nicht vergessen |
| `app path does not exist` | Die Datei ist nicht gepusht, oder du arbeitest nicht auf dem Standard-Branch → `git status`, `git log origin/HEAD` |
| App bleibt **OutOfSync**, obwohl nichts geändert wurde | Auf die App klicken → **App Diff**. Oft ändern Operatoren Felder selbst. Bei Fragen die Unterschiede genau ansehen |
| `argocd`-App: `metadata.annotations: Too long` | In `katalog/argocd.yaml` muss `ServerSideApply=true` stehen |
| App **Degraded** | Auf die rote Kachel im Baum klicken → **Events** und **Logs**. Dieselbe Fehlersuche wie in Teil B, nur mit Bildern |
| Änderungen per `kubectl` „verschwinden“ | Das ist Self-Heal und so gewollt. Änderungen gehören nach Git |
| Du hast dich ausgesperrt (Passwort vergessen) | Passwort per Befehl zurücksetzen: `argocd account bcrypt --password '<NEU>'` erzeugt einen Hash. Den mit `kubectl -n argocd patch secret argocd-secret -p '{"stringData":{"admin.password":"<HASH>"}}'` eintragen |

## 🎓 Was du gelernt hast

- **GitOps**: Das Git-Repository beschreibt den Soll-Zustand, Argo CD gleicht den Cluster laufend daran an.
- Eine **Application** verbindet eine Quelle (Git-Ordner oder Helm-Chart + Values) mit einem Ziel im Cluster.
- **App-of-Apps**: Eine Wurzel-Application verwaltet alle anderen. Aktivieren heißt Datei nach `aktiv/` kopieren.
- **Sync** rollt aus, **Prune** löscht Entferntes, **Self-Heal** setzt Änderungen am Git vorbei zurück.
- Bestehende Installationen lassen sich an Argo CD übergeben, ohne sie neu zu starten.
- Öffentliche Repositories liest Argo CD ohne Zugangsdaten, private brauchen einen Lese-Token.

---

⬅️ **Zurück:** [10 – Tailscale Operator](10-tailscale-operator.md) · ➡️ **Weiter:** [12 – Secrets im Git](12-sealed-secrets.md)
