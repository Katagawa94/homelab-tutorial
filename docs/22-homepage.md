# 22 – Homepage

> **Was du am Ende hast:** Ein Dashboard unter `https://homepage.<tailnet>.ts.net` mit Kacheln für alle Dienste,
> Live-Daten aus Jellyfin, Sonarr und Radarr sowie dem Status jedes Pods direkt aus Kubernetes.
>
> ⏱️ **Zeit:** ca. 45 Minuten
>
> 🧠 **Neue Begriffe:** [RBAC](glossar.md#container--kubernetes), [ServiceAccount](glossar.md#container--kubernetes),
> [ClusterRole](glossar.md#container--kubernetes), [configMapGenerator](glossar.md#container--kubernetes), `subPath`

---

> 📸 **Snapshot-Routine:** Snapshot der VM anlegen (bei ausgeschalteter VM).

## Teil E im Überblick

Ab hier kommen nützliche Apps dazu, die nichts mit Medien zu tun haben. Jede bekommt ihren **eigenen Namespace**.
So bleiben sie sauber getrennt, und du kannst eine App samt allem Zubehör mit einem Befehl entfernen.

| Kapitel | App | Namespace | Neues Kubernetes-Konzept |
|---------|-----|-----------|--------------------------|
| 22 | Homepage | `homepage` | RBAC, configMapGenerator |
| 23 | Vaultwarden | `vaultwarden` | Konfiguration per Git ändern |
| 24 | Immich | `immich` | StatefulSet, mehrere Komponenten, GPU teilen |
| 25 | Paperless-ngx | `paperless` | App mit Hintergrund-Warteschlange |
| 26 | Uptime Kuma | `uptime-kuma` | Überwachung von außen |

## 1. Einmalig: deinen Tailnet-Namen eintragen

Einige Apps müssen ihre eigene Adresse kennen (z. B. `https://vaultwarden.tail1a2b3c.ts.net`). In den Dateien unter
`kubernetes/apps/` steht dafür der Platzhalter **`tail1a2b3c.ts.net`**. Ersetze ihn einmal überall durch deinen Tailnet-Namen
(den vom Spickzettel):

```bash
grep -rl 'tail1a2b3c.ts.net' kubernetes/apps/
```

```
kubernetes/apps/homepage/config/services.yaml
kubernetes/apps/homepage/deployment.yaml
kubernetes/apps/paperless/deployment.yaml
kubernetes/apps/vaultwarden/deployment.yaml
```

```bash
grep -rl 'tail1a2b3c.ts.net' kubernetes/apps/ | xargs sed -i 's/tail1a2b3c\.ts\.net/<DEIN-TAILNET>.ts.net/g'
git diff --stat
git commit -am "Tailnet-Namen eintragen"
git push
```

(Also z. B. `s/tail1a2b3c\.ts\.net/tail9x8y7z.ts.net/g`.)

## 2. Was Homepage besonders macht: Rechte im Cluster

Homepage zeigt zu jeder App an, ob ihre Pods laufen und wie viel CPU und RAM sie brauchen. Dafür muss Homepage
**Kubernetes selbst fragen**, genau wie du mit `kubectl get pods`. Aber mit welchen Rechten?

Bisher hast du mit der kubeconfig aus Kapitel 05 gearbeitet: **Admin**, darf alles. Ein Programm im Cluster soll
dagegen nur genau das dürfen, was es braucht. Dafür gibt es **RBAC** (*Role-Based Access Control*):

```
 ServiceAccount "homepage"  ◄── ClusterRoleBinding ──►  ClusterRole "homepage"
   (wer?)                        (verbindet)              (was darf man?)
     ▲                                                     - pods, nodes, namespaces: get, list
     │                                                     - ingresses: get, list
 Pod homepage läuft als dieser ServiceAccount              - metrics: get, list
```

[`kubernetes/apps/homepage/rbac.yaml`](../kubernetes/apps/homepage/rbac.yaml):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: homepage
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: homepage
rules:
  - apiGroups: [""]
    resources: ["namespaces", "pods", "nodes"]
    verbs: ["get", "list"]                # nur lesen, nichts ändern!
  ...
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: homepage
roleRef:
  kind: ClusterRole
  name: homepage
subjects:
  - kind: ServiceAccount
    name: homepage
    namespace: homepage
```

Im Deployment sagt `serviceAccountName: homepage`, unter welcher Identität der Pod läuft.

> 💡 **Role oder ClusterRole?** Eine *Role* gilt nur in einem Namespace, eine *ClusterRole* im ganzen Cluster.
> Homepage soll Pods in *allen* Namespaces sehen, deshalb ClusterRole.

## 3. Konfiguration als echte Dateien: configMapGenerator

Homepage wird über fünf YAML-Dateien eingerichtet. Die liegen ganz normal in
[`kubernetes/apps/homepage/config/`](../kubernetes/apps/homepage/config/), und Kustomize macht daraus eine ConfigMap:

```yaml
# kubernetes/apps/homepage/kustomization.yaml (Ausschnitt)
configMapGenerator:
  - name: homepage-config
    files:
      - config/settings.yaml
      - config/services.yaml
      - config/widgets.yaml
      - config/bookmarks.yaml
      - config/kubernetes.yaml
```

Probier aus, was dabei herauskommt:

```bash
kubectl kustomize kubernetes/apps/homepage | grep "name: homepage-config"
```

```
  name: homepage-config-b98k8k5655
          name: homepage-config-b98k8k5655
```

Kustomize hängt einen **Hash** an den Namen, eine Prüfsumme über den Inhalt, und trägt ihn auch im Deployment ein.
Ändert sich eine Datei, ändert sich der Name. Das Deployment zeigt dann auf eine „neue“ ConfigMap und **startet
automatisch neu**. So kann Homepage keine veraltete Konfiguration mehr haben (in Kapitel 08 musstest du noch warten oder neu starten).

Im Deployment wird jede Datei mit **`subPath`** einzeln eingebunden:

```yaml
            - name: config
              mountPath: /app/config/services.yaml
              subPath: services.yaml      # nur diese eine Datei einbinden, nicht den ganzen Ordner
```

Ohne `subPath` würde die ConfigMap den ganzen Ordner `/app/config` ersetzen, und Homepage könnte dort nichts mehr selbst ablegen.

## 4. API-Schlüssel für die Widgets

Die Kacheln für Jellyfin, Sonarr und Radarr zeigen Live-Daten (laufende Streams, Warteschlange …). Dafür braucht
Homepage die **API-Schlüssel** der Apps. In [`config/services.yaml`](../kubernetes/apps/homepage/config/services.yaml)
stehen Platzhalter:

```yaml
        widget:
          type: sonarr
          url: http://sonarr.media:8989
          key: "{{HOMEPAGE_VAR_SONARR_KEY}}"
```

Homepage ersetzt `{{HOMEPAGE_VAR_…}}` durch die gleichnamige Umgebungsvariable. Die kommt aus einem Secret. Beachte:
Homepage liegt im Namespace `homepage`, Sonarr in `media`. Deshalb lautet die Adresse `http://sonarr.media:8989`
(Service **.** Namespace, Kapitel 07).

Die Schlüssel findest du in Sonarr und Radarr unter **Settings → General → API Key**. Für Jellyfin legst du unter
**Dashboard → API-Schlüssel** einen neuen namens `homepage` an.

```bash
mkdir -p kubernetes/secrets/homepage
kubectl create secret generic homepage-keys -n homepage \
  --from-literal=HOMEPAGE_VAR_JELLYFIN_KEY='<JELLYFIN-KEY>' \
  --from-literal=HOMEPAGE_VAR_SONARR_KEY='<SONARR-KEY>' \
  --from-literal=HOMEPAGE_VAR_RADARR_KEY='<RADARR-KEY>' \
  --dry-run=client -o yaml \
| kubeseal --format yaml > kubernetes/secrets/homepage/homepage-keys.yaml
```

> 💡 Im Deployment steht bei diesem Secret `optional: true`. Homepage startet also auch ohne. Die Widgets zeigen dann einen Fehler, die Links funktionieren trotzdem.

## 5. Aktivieren

```bash
cp kubernetes/katalog/homepage.yaml kubernetes/aktiv/
git add kubernetes/aktiv/homepage.yaml kubernetes/secrets/homepage/
git commit -m "Homepage aktivieren"
git push
```

Öffne <https://homepage.tail1a2b3c.ts.net>. Oben siehst du die Auslastung des Clusters, darunter drei Gruppen:
**Medien**, **Verwaltung** und **Werkzeuge**. Kacheln von Apps, die noch nicht installiert sind (Immich, Paperless …),
zeigen einen roten Status. Das ändert sich in den nächsten Kapiteln.

> 💡 Lege dir Homepage als Startseite im Browser und als Lesezeichen auf dem Handy-Homescreen an.

### RBAC nachprüfen

Mit `kubectl auth can-i` fragst du Kubernetes, was eine Identität darf:

```bash
kubectl auth can-i list pods --as=system:serviceaccount:homepage:homepage
kubectl auth can-i delete pods --as=system:serviceaccount:homepage:homepage
```

```
yes
no
```

Homepage darf Pods auflisten, aber nicht löschen. Genau so soll es sein.

## 6. Anpassen

Füge z. B. ein Lesezeichen hinzu. Öffne `kubernetes/apps/homepage/config/bookmarks.yaml`:

```yaml
- Homelab:
    - Tutorial:
        - abbr: HL
          href: https://github.com/Katagawa94/homelab-tutorial
    - Tailscale:
        - abbr: TS
          href: https://login.tailscale.com/admin/machines
    - Proton VPN:
        - abbr: PV
          href: https://account.proton.me
```

```bash
git commit -am "Homepage: Lesezeichen Proton"
git push
```

Nach dem Sync startet Homepage von selbst neu (neuer Hash!), und das Lesezeichen ist da. Alle Möglichkeiten stehen in
der [Homepage-Dokumentation](https://gethomepage.dev/configs/services/). Icons findest du unter
[dashboard-icons](https://github.com/homarr-labs/dashboard-icons).

## ✅ Checkpoint

- [ ] `grep -r tail1a2b3c kubernetes/apps/` findet nichts mehr.
- [ ] `https://homepage.<tailnet>.ts.net` zeigt das Dashboard.
- [ ] Die Kacheln der Medien-Apps zeigen einen grünen Status und CPU/RAM.
- [ ] Die Widgets von Jellyfin, Sonarr und Radarr zeigen Daten.
- [ ] `kubectl auth can-i delete pods --as=system:serviceaccount:homepage:homepage` sagt `no`.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| `Host validation failed` im Browser | `HOMEPAGE_ALLOWED_HOSTS` im Deployment muss exakt `homepage.<dein-tailnet>.ts.net` enthalten (Schritt 1) |
| Kein Pod-Status an den Kacheln | `namespace` und `podSelector` in `services.yaml` prüfen, RBAC mit `kubectl auth can-i` testen |
| Widget: `API Error` | Schlüssel falsch oder Secret fehlt → `kubectl get secret homepage-keys -n homepage` |
| Änderung an `config/…` kommt nicht an | Gepusht? In Argo CD **Refresh**. Der Pod sollte einen neuen Namen haben (`kubectl get pods -n homepage`) |

## 🎓 Was du gelernt hast

- **RBAC**: Ein **ServiceAccount** ist die Identität eines Pods, eine **(Cluster)Role** beschreibt Rechte, ein **Binding** verbindet beides.
- `kubectl auth can-i … --as=…` prüft Rechte, ohne etwas auszuprobieren.
- **configMapGenerator** macht aus normalen Dateien eine ConfigMap. Der **Hash** im Namen sorgt für automatische Neustarts bei Änderungen.
- **`subPath`** bindet einzelne Dateien ein statt ganzer Ordner.
- Apps in anderen Namespaces erreicht man über `<service>.<namespace>`.

---

⬅️ **Zurück:** [21 – Bazarr & Seerr](21-bazarr-seerr.md) · ➡️ **Weiter:** [23 – Vaultwarden](23-vaultwarden.md)
