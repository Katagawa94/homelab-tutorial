# 10 – Tailscale Operator

> **Was du am Ende hast:** Der Tailscale Operator läuft im Cluster. Jede App, der du einen kleinen *Ingress* gibst,
> erscheint automatisch als eigenes Gerät im Tailnet, mit echter HTTPS-Adresse wie `https://whoami.<tailnet>.ts.net`.
>
> ⏱️ **Zeit:** ca. 45 Minuten
>
> 🧠 **Neue Begriffe:** [Operator](glossar.md#container--kubernetes), [CRD](glossar.md#container--kubernetes),
> [Ingress](glossar.md#container--kubernetes), [IngressClass](glossar.md#container--kubernetes),
> [Tag](glossar.md#netzwerk), [OAuth-Client](glossar.md#netzwerk)

---

> 📸 **Snapshot-Routine:** Lege in Proxmox einen Snapshot der VM an (z. B. `vor-tailscale-operator`).
> Ab Teil C arbeitest du mit den Dateien in [`kubernetes/`](../kubernetes/). Das ist nicht mehr Lernmaterial, sondern
> **die echte Konfiguration deines Homelabs**.

## Wie funktioniert das?

In Kapitel 03 hast du Proxmox mit `tailscale serve` ins Tailnet gebracht, von Hand und für genau einen Dienst.
Im Cluster soll das für jede App automatisch passieren. Dafür gibt es den **Tailscale Operator**.

Ein **Operator** ist ein Programm, das im Cluster läuft und Kubernetes um neues Wissen erweitert. Der Tailscale Operator
beobachtet alle **Ingress**-Objekte. Findet er einen mit `ingressClassName: tailscale`, dann

1. startet er einen kleinen **Proxy-Pod** für diese App,
2. meldet diesen Proxy als eigenes Gerät im Tailnet an (z. B. `whoami`),
3. besorgt ein HTTPS-Zertifikat und
4. leitet alle Anfragen an den Service der App weiter.

```
 Laptop/Handy ──Tailnet──► Proxy-Pod "whoami" ──► Service whoami ──► Pods whoami
  https://whoami.tail1a2b3c.ts.net   (vom Operator angelegt)
```

Damit der Operator Geräte in *deinem* Tailnet anlegen darf, braucht er zwei Dinge: **Tags** und einen **OAuth-Client**.

## 1. Tags in der Tailnet-Richtlinie

Geräte in Tailscale gehören normalerweise einer Person. Server und Proxys sollen aber keiner Person gehören, sondern
über **Tags** (Etiketten) verwaltet werden. Wir legen zwei Tags an:

| Tag | Bekommt | Besitzer |
|-----|---------|----------|
| `tag:k8s-operator` | der Operator selbst | Admins des Tailnets |
| `tag:k8s` | jeder Proxy, den der Operator anlegt | der Operator (`tag:k8s-operator`) |

1. Öffne die [Admin-Konsole → Access controls](https://login.tailscale.com/admin/acls/file).
2. Wechsle in den **JSON editor**.
3. Suche den Abschnitt `"tagOwners"`. Gibt es ihn schon (evtl. auskommentiert mit `//`), ersetze ihn. Sonst füge ihn
   direkt nach der ersten `{` ein:

   ```jsonc
   "tagOwners": {
     "tag:k8s-operator": [],
     "tag:k8s": ["tag:k8s-operator"],
   },
   ```

4. **Save**. Tailscale prüft die Datei und meldet Tippfehler sofort.

> 💡 `"tag:k8s-operator": []` heißt: Nur Admins dürfen dieses Tag vergeben, und als Besitzer des Tailnets bist du Admin.
> `"tag:k8s": ["tag:k8s-operator"]` heißt: Der Operator darf seinen Proxys das Tag `tag:k8s` geben.

## 2. OAuth-Client erstellen

Der **OAuth-Client** ist der Zugangsschlüssel, mit dem der Operator die Tailscale-API benutzen darf, und zwar nur
für genau die Rechte, die wir ihm geben.

1. Öffne in der Admin-Konsole **Settings → Trust credentials** (in älteren Oberflächen: **OAuth clients**).
2. Klicke **+ Credential** und wähle **OAuth**.
3. **Description:** `k3s-operator`
4. **Scopes** (Rechte), jeweils **Write** auswählen (Read ist dann automatisch dabei):

   | Bereich | Scope | Wofür |
   |---------|-------|-------|
   | Devices | **Core** | Geräte (Proxys) anlegen und löschen |
   | Keys | **Auth Keys** | Anmeldeschlüssel für neue Proxys erzeugen |
   | General | **Services** | Tailscale-Services verwalten |

5. Bei **Tags** jeweils `tag:k8s-operator` hinzufügen.
6. **Generate credential**.
7. Kopiere **Client ID** und **Client secret** sofort in deinen Passwortmanager.
   **Das Secret wird nur dieses eine Mal angezeigt.**

## 3. Das Secret für den Operator

> 💻 **Auf deinem Rechner** (im Ordner `homelab-tutorial`, ggf. `nix develop`)

Der Operator läuft im Namespace `tailscale` und erwartet seine Zugangsdaten im Secret **`operator-oauth`**.
Wie in Kapitel 08 legen wir es per Befehl an, damit die Zugangsdaten nicht in einer Datei landen:

```bash
kubectl create namespace tailscale
kubectl create secret generic operator-oauth -n tailscale \
  --from-literal=client_id='<CLIENT-ID>' \
  --from-literal=client_secret='<CLIENT-SECRET>'
```

```
namespace/tailscale created
secret/operator-oauth created
```

> 💡 In Kapitel 14 wandert dieses Secret verschlüsselt ins Git-Repository. Bis dahin existiert es nur im Cluster.

## 4. Den Operator installieren

Die Einstellungen liegen in [`kubernetes/infrastructure/tailscale-operator/values.yaml`](../kubernetes/infrastructure/tailscale-operator/values.yaml):

```yaml
operatorConfig:
  hostname: tailscale-operator    # Name des Operators in der Tailscale-Admin-Konsole
```

Mehr brauchen wir nicht, alles andere passt in der Standardeinstellung. Installieren wie in Kapitel 09:

```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update
helm upgrade --install tailscale-operator tailscale/tailscale-operator \
  --namespace tailscale \
  --version 1.102.4 \
  -f kubernetes/infrastructure/tailscale-operator/values.yaml \
  --wait
```

```
Release "tailscale-operator" does not exist. Installing it now.
NAME: tailscale-operator
NAMESPACE: tailscale
STATUS: deployed
REVISION: 1
```

> 💡 Die Versionsnummer `1.102.4` entspricht der Tailscale-Version. Eine neuere Version darfst du gern nehmen
> (`helm search repo tailscale`). Trage sie dann auch in [`kubernetes/katalog/tailscale-operator.yaml`](../kubernetes/katalog/tailscale-operator.yaml) ein,
> denn dort übernimmt Argo CD in Kapitel 13 die Verwaltung.

## 5. Läuft der Operator?

```bash
kubectl get pods -n tailscale
```

```
NAME                        READY   STATUS    RESTARTS   AGE
operator-6b8c9d7f4d-k2x9m   1/1     Running   0          40s
```

In der [Admin-Konsole → Machines](https://login.tailscale.com/admin/machines) erscheint ein neues Gerät
**tailscale-operator** mit dem Tag `tag:k8s-operator`. 🎉

Der Operator hat Kubernetes außerdem um neue Fähigkeiten erweitert:

```bash
kubectl get ingressclass
```

```
NAME        CONTROLLER                      PARAMETERS   AGE
tailscale   tailscale.com/ts-ingress                     1m
traefik     traefik.io/ingress-controller   <none>       3d
```

Es gibt jetzt zwei **IngressClasses**: `traefik` (von k3s) und `tailscale`. Mit `ingressClassName` wählt jeder Ingress,
wer sich um ihn kümmern soll.

```bash
kubectl get crd | grep tailscale
```

```
connectors.tailscale.com         2026-09-26T15:20:11Z
dnsconfigs.tailscale.com         2026-09-26T15:20:11Z
proxyclasses.tailscale.com       2026-09-26T15:20:11Z
proxygroups.tailscale.com        2026-09-26T15:20:11Z
recorders.tailscale.com          2026-09-26T15:20:11Z
...
```

Das sind **CRDs** (*Custom Resource Definitions*): neue Objekttypen, die der Operator mitbringt. Für dieses Tutorial
reicht der normale Ingress. Die CRDs brauchst du erst für fortgeschrittene Dinge.

## 6. Erster Test: whoami im Tailnet

Die Testdatei [`examples/10-tailscale-operator/whoami.yaml`](../examples/10-tailscale-operator/whoami.yaml) enthält
Namespace, Deployment und Service (wie in Kapitel 07) und dazu einen **Ingress**:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  namespace: tailscale-test
spec:
  ingressClassName: tailscale     # "Tailscale, bitte kümmere dich um diesen Ingress"
  defaultBackend:
    service:
      name: whoami
      port:
        number: 80
  tls:
    - hosts:
        - whoami                  # → https://whoami.<tailnet>.ts.net
```

> 💡 Mehrere Objekte in einer Datei werden in YAML durch `---` getrennt.

```bash
kubectl apply -f examples/10-tailscale-operator/whoami.yaml
```

Nach etwa 30 Sekunden:

```bash
kubectl get ingress -n tailscale-test
```

```
NAME     CLASS       HOSTS   ADDRESS                     PORTS     AGE
whoami   tailscale   *       whoami.tail1a2b3c.ts.net    80, 443   45s
```

Unter `ADDRESS` steht die Tailscale-Adresse. Den vom Operator gestarteten Proxy findest du im Namespace `tailscale`:

```bash
kubectl get pods -n tailscale
```

```
NAME                        READY   STATUS    RESTARTS   AGE
operator-6b8c9d7f4d-k2x9m   1/1     Running   0          5m
ts-whoami-7hq2x-0           1/1     Running   0          50s
```

Öffne <https://whoami.tail1a2b3c.ts.net> (mit deinem Tailnet-Namen). Der allererste Aufruf kann bis zu einer Minute
dauern, weil das Zertifikat ausgestellt wird. Danach siehst du die bekannte whoami-Ausgabe, verschlüsselt und mit gültigem Zertifikat. 🔒

Probier es auch vom Handy über Mobilfunk. In der Admin-Konsole ist außerdem ein neues Gerät **whoami** mit dem Tag `tag:k8s` aufgetaucht.

## 7. Aufräumen

```bash
kubectl delete -f examples/10-tailscale-operator/whoami.yaml
```

Der Operator räumt hinter sich auf: Der Proxy-Pod verschwindet, und das Gerät **whoami** wird nach kurzer Zeit aus der
Admin-Konsole entfernt.

## ✅ Checkpoint

- [ ] In der Tailnet-Richtlinie stehen `tag:k8s-operator` und `tag:k8s`.
- [ ] Client ID und Secret des OAuth-Clients liegen in deinem Passwortmanager.
- [ ] `kubectl get pods -n tailscale` zeigt den Operator als `Running`.
- [ ] In der Admin-Konsole gibt es das Gerät **tailscale-operator**.
- [ ] `https://whoami.<tailnet>.ts.net` hat funktioniert (und ist nach dem Aufräumen wieder weg).

## 🔧 Wenn etwas schiefgeht

Der wichtigste Befehl: **die Logs des Operators**.

```bash
kubectl logs -n tailscale deployment/operator
```

| Meldung / Problem | Lösung |
|-------------------|--------|
| Pod `operator-…` bleibt in `ContainerCreating` | Das Secret `operator-oauth` fehlt oder liegt im falschen Namespace → `kubectl get secret -n tailscale` |
| `requested tags [tag:k8s-operator] are invalid or not permitted` | `tagOwners` fehlt in der Richtlinie, oder dem OAuth-Client wurde das Tag nicht zugewiesen |
| `401` / `403` / `unauthorized` | Client-ID/Secret vertauscht oder falsch kopiert, oder ein Scope fehlt. Secret löschen und neu anlegen, dann `kubectl rollout restart deployment/operator -n tailscale` |
| Ingress hat keine `ADDRESS` | Logs des Operators und des Proxys ansehen: `kubectl logs -n tailscale ts-whoami-…-0` |
| Zertifikatsfehler im Browser | Ist **HTTPS** in der Admin-Konsole unter **DNS** aktiviert (Kapitel 01)? Beim ersten Aufruf eine Minute warten |
| Gerät heißt `whoami-1` | Ein altes Gerät gleichen Namens existiert noch → in der Admin-Konsole löschen |

## 🎓 Was du gelernt hast

- Ein **Operator** erweitert Kubernetes und automatisiert Aufgaben. Oft bringt er eigene Objekttypen (**CRDs**) mit.
- Ein **Ingress** beschreibt, wie eine App von außen erreichbar ist. Die **IngressClass** bestimmt, wer ihn umsetzt.
- **Tags** machen Geräte im Tailnet unabhängig von Personen.
- Ein **OAuth-Client** gibt einem Programm genau begrenzte Rechte.
- Mit dem Tailscale Operator reicht ein Ingress mit `ingressClassName: tailscale`, und die App ist per HTTPS im Tailnet erreichbar.

---

⬅️ **Zurück:** [09 – Helm](09-helm.md) · ➡️ **Weiter:** [11 – Jellyfin](11-jellyfin.md)
