# 13 – GitOps mit Argo CD

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
│   ├── argocd.yaml
│   ├── tailscale-operator.yaml
│   ├── media-basis.yaml
│   ├── jellyfin.yaml
│   ├── sealed-secrets.yaml   (Kapitel 14)
│   ├── secrets.yaml          (Kapitel 14)
│   └── nvidia-device-plugin.yaml (Kapitel 16)
├── infrastructure/           ← Values und Zusatz-Manifeste für Helm-Charts
├── apps/                     ← unsere eigenen Manifeste (Jellyfin …)
└── secrets/                  ← verschlüsselte Secrets (Kapitel 14)
```

In Argo CD beschreibt eine **Application**: *„Nimm diese Manifeste (aus Git oder einem Helm-Chart) und rolle sie in
diesen Namespace aus.“* Die Application `root` zeigt auf den Ordner `aktiv/`, und der enthält wiederum Applications.
Dieses Muster heißt **App-of-Apps**:

```
Application "root"  ──► kubernetes/aktiv/
                          ├── argocd.yaml              ──► Helm-Chart argo-cd
                          ├── tailscale-operator.yaml  ──► Helm-Chart tailscale-operator
                          ├── media-basis.yaml         ──► kubernetes/apps/media/basis
                          └── jellyfin.yaml            ──► kubernetes/apps/media/jellyfin
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
> Deshalb gelangen Zugangsdaten in diesem Tutorial nur **verschlüsselt** ins Repository (Kapitel 14). Vor jedem Commit
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

Die Weboberfläche kommt, wie Jellyfin, per Tailscale-Ingress ins Tailnet:

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

Tailscale Operator, Argo CD selbst und Jellyfin laufen bereits, allerdings per Hand installiert. Argo CD kann sie
**übernehmen**: Es rendert dieselben Manifeste und stellt fest, dass die Objekte schon existieren. Nichts wird neu gestartet.

### Helm „vergessen lassen“

Tailscale Operator und Argo CD wurden mit `helm install` installiert, und Helm führt darüber Buch (Kapitel 09: die
`sh.helm.release…`-Secrets). Ab jetzt ist Argo CD zuständig. Wir löschen nur Helms **Buchführung**, die Apps selbst bleiben stehen:

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
cp kubernetes/katalog/{argocd,tailscale-operator,media-basis,jellyfin}.yaml kubernetes/aktiv/
git add kubernetes/aktiv/
git commit -m "Argo CD übernimmt Argo CD, Tailscale Operator und Jellyfin"
git push
```

Argo CD schaut alle drei Minuten ins Repository. Nicht warten? In der Oberfläche bei **root** auf **Refresh** klicken.

Nach kurzer Zeit erscheinen vier neue Kacheln. Klick auf **jellyfin**: Du siehst den ganzen Baum, den du in Teil B
kennengelernt hast, als Bild:

```
jellyfin (Application)
├── Service jellyfin
├── PersistentVolumeClaim jellyfin-config
├── Ingress jellyfin
└── Deployment jellyfin
    └── ReplicaSet jellyfin-5f7d8c9b6f
        └── Pod jellyfin-5f7d8c9b6f-xk2lp
```

Alle vier Apps sollten nach ein, zwei Minuten **Synced** und **Healthy** sein.

## 7. Self-Heal ausprobieren

Jetzt kommt der spannende Teil. Mach etwas kaputt:

```bash
kubectl scale deployment jellyfin -n media --replicas=0
kubectl get pods -n media -w
```

Innerhalb von Sekunden bemerkt Argo CD: *„In Git steht `replicas: 1`, im Cluster `0`.“* Und stellt es wieder her.
In der Oberfläche siehst du kurz **OutOfSync**, dann wieder **Synced**.

Noch mal, radikaler:

```bash
kubectl delete service jellyfin -n media
```

Kurz danach ist der Service wieder da, mit derselben `EXTERNAL-IP`. Dein Samsung-TV merkt davon nichts.

## 8. Eine Änderung per Git

Jellyfin soll mehr RAM bekommen. Öffne `kubernetes/apps/media/jellyfin/deployment.yaml` und ändere das Limit:

```yaml
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              memory: 6Gi               # vorher: 4Gi
```

```bash
git diff                          # Was habe ich geändert?
git commit -am "Jellyfin: RAM-Limit auf 6 GiB"
git push
```

Klick in Argo CD auf **Refresh** (oder warte drei Minuten). Die App **jellyfin** wird **OutOfSync**, dann synchronisiert
Argo CD: Jellyfin startet mit dem neuen Limit neu (wegen `strategy: Recreate` mit kurzer Unterbrechung). Prüfen:

```bash
kubectl get deployment jellyfin -n media -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'; echo
```

```
6Gi
```

**Das ist ab jetzt dein Arbeitsablauf:** Datei ändern → commit → push → Argo CD erledigt den Rest.

## 9. Sicherheitsnetze

Mit `prune: true` löscht Argo CD alles, was aus Git verschwindet. Damit ein Versehen keine Daten kostet, gibt es zwei Schutzmechanismen:

1. **PVCs werden nie automatisch gelöscht.** Sie haben die Annotation
   `argocd.argoproj.io/sync-options: Prune=false`. Argo CD zeigt sie dann als „müsste gelöscht werden“ an, tut es aber nicht.
2. **Applications ohne Finalizer.** Löschst du eine Datei aus `aktiv/`, verschwindet nur die *Application*. Die
   Kubernetes-Objekte, die sie angelegt hat, bleiben stehen, und du räumst sie bewusst selbst auf.

## 10. Die Argo-CD-Kommandozeile (optional)

Alles aus der Oberfläche geht auch im Terminal (`argocd` ist in der `flake.nix` enthalten):

```bash
argocd login argocd.tail1a2b3c.ts.net --grpc-web --username admin
argocd app list
argocd app get jellyfin
argocd app sync jellyfin          # sofort synchronisieren statt 3 Minuten warten
```

## ✅ Checkpoint

- [ ] `https://argocd.<tailnet>.ts.net` öffnet Argo CD, das Start-Passwort ist geändert und gelöscht.
- [ ] Unter **Settings → Repositories** ist dein Repository **Successful** (bei privatem Repository).
- [ ] Die Apps `root`, `argocd`, `tailscale-operator`, `media-basis` und `jellyfin` sind **Synced** und **Healthy**.
- [ ] `helm list -A` zeigt nur noch `traefik` und `traefik-crd`.
- [ ] Du hast Self-Heal beobachtet (Jellyfin kam von allein zurück).
- [ ] Du hast eine Änderung per `git push` ausgerollt.

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

⬅️ **Zurück:** [12 – Jellyfin auf dem Samsung-TV](12-samsung-tv.md) · ➡️ **Weiter:** [14 – Secrets im Git](14-sealed-secrets.md)
