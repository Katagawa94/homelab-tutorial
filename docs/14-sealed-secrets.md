# 14 – Secrets im Git

> **Was du am Ende hast:** Die Zugangsdaten für Tailscale (und ggf. GitHub) liegen **verschlüsselt** im Git-Repository.
> Nur dein Cluster kann sie entschlüsseln, und nach einem Neuaufbau ist alles automatisch wieder da.
>
> ⏱️ **Zeit:** ca. 45 Minuten
>
> 🧠 **Neue Begriffe:** [Sealed Secrets](glossar.md#container--kubernetes), SealedSecret, [kubeseal](glossar.md#container--kubernetes),
> öffentlicher/privater Schlüssel

---

> 📸 **Snapshot-Routine:** Snapshot der VM anlegen (z. B. `vor-sealed-secrets`).

## Das Problem

Bisher hast du Secrets per Befehl angelegt: `operator-oauth` (Kapitel 10) und, nur bei privatem Repository, `repo-homelab` (Kapitel 13).
Sie existieren **nur im Cluster**. Geht die VM kaputt, müsstest du sie von Hand neu anlegen. Das widerspricht der
GitOps-Idee: *Alles steht in Git.*

Aber ins Git dürfen sie nicht, denn Secrets sind nur base64-kodiert (Kapitel 08). Die Lösung: **verschlüsseln**.

## Wie Sealed Secrets funktioniert

Der **Sealed-Secrets-Controller** im Cluster erzeugt ein Schlüsselpaar:

- einen **öffentlichen Schlüssel**: Damit kann *jeder* verschlüsseln, auch du auf deinem Rechner.
- einen **privaten Schlüssel**: Nur damit kann man entschlüsseln. Er verlässt den Cluster nie.

```
 Dein Rechner                          Git                     Cluster
┌───────────────┐   kubeseal    ┌──────────────┐  Argo CD  ┌────────────────────────────┐
│ Secret (klar) │ ────────────► │ SealedSecret │ ────────► │ Controller entschlüsselt   │
└───────────────┘  öffentl.     │ (verschlüss.)│           │ → normales Secret          │
                   Schlüssel    └──────────────┘           └────────────────────────────┘
```

Wie bei einem Briefkasten: Einwerfen kann jeder, aufschließen nur der Besitzer.

## 1. Den Controller aktivieren

Die Einstellungen in [`kubernetes/infrastructure/sealed-secrets/values.yaml`](../kubernetes/infrastructure/sealed-secrets/values.yaml)
sind kurz. Wir geben dem Controller nur den Namen, unter dem `kubeseal` ihn standardmäßig sucht:

```yaml
fullnameOverride: sealed-secrets-controller
```

Aktivieren, der neue Arbeitsablauf aus Kapitel 13:

```bash
cp kubernetes/katalog/sealed-secrets.yaml kubernetes/aktiv/
git add kubernetes/aktiv/sealed-secrets.yaml
git commit -m "Sealed Secrets aktivieren"
git push
```

Nach dem Sync (Argo CD → **Refresh**):

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

```
NAME                                         READY   STATUS    RESTARTS   AGE
sealed-secrets-controller-7c8d9f6b5d-q2m4x   1/1     Running   0          40s
```

Test, ob `kubeseal` den Controller findet:

```bash
kubeseal --fetch-cert | head -3
```

```
-----BEGIN CERTIFICATE-----
MIIEzTCCArWgAwIBAgIRAK...
```

Das ist der **öffentliche** Schlüssel. Er ist nicht geheim.

## 2. Den privaten Schlüssel sichern ⚠️

Das ist der wichtigste Schritt des Kapitels. **Ohne den privaten Schlüssel sind alle SealedSecrets wertlos**, zum
Beispiel nach einer Neuinstallation der VM. Sichere ihn deshalb an einem Ort **außerhalb** des Clusters und **außerhalb** von Git:

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key.yaml
```

Speichere die Datei `sealed-secrets-key.yaml` in deinem Passwortmanager (als Dateianhang) oder auf einem verschlüsselten
USB-Stick. **Danach die Datei löschen:**

```bash
rm sealed-secrets-key.yaml
```

> 💡 `sealed-secrets-key*.yaml` steht zusätzlich in der `.gitignore`, damit die Datei nicht versehentlich committet wird.
>
> **Wiederherstellen** (nach einem Neuaufbau, *bevor* der Controller startet):
> `kubectl apply -f sealed-secrets-key.yaml`, danach den Controller neu starten.

## 3. Das Tailscale-Secret versiegeln

Wir erzeugen das Secret wie in Kapitel 10, diesmal aber **nicht im Cluster**, sondern nur als Text, den wir direkt an
`kubeseal` weiterreichen. Client ID und Secret holst du aus dem Passwortmanager:

```bash
mkdir -p kubernetes/secrets/tailscale
kubectl create secret generic operator-oauth -n tailscale \
  --from-literal=client_id='<CLIENT-ID>' \
  --from-literal=client_secret='<CLIENT-SECRET>' \
  --dry-run=client -o yaml \
| kubeseal --format yaml > kubernetes/secrets/tailscale/operator-oauth.yaml
```

| Teil | Bedeutung |
|------|-----------|
| `--dry-run=client -o yaml` | Secret **nicht anlegen**, sondern nur als YAML ausgeben |
| `\|` (Pipe) | die Ausgabe direkt an den nächsten Befehl weitergeben, ohne Zwischendatei |
| `kubeseal --format yaml` | mit dem öffentlichen Schlüssel verschlüsseln |
| `> …` | Ergebnis in die Datei schreiben |

Das Ergebnis:

```bash
cat kubernetes/secrets/tailscale/operator-oauth.yaml
```

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: operator-oauth
  namespace: tailscale
spec:
  encryptedData:
    client_id: AgBy3i4OJSWK+PiTySYZZA1rO43cGDEq...
    client_secret: AgCtr8HZFBOGZ5Njlk1UT2IK1qB8...
  template:
    metadata:
      name: operator-oauth
      namespace: tailscale
```

Diese Datei **darf** ins Git. Ohne den privaten Schlüssel aus deinem Cluster kann niemand etwas damit anfangen.

> 💡 **Name und Namespace sind Teil der Verschlüsselung.** Dieses SealedSecret lässt sich nur als `operator-oauth` im
> Namespace `tailscale` entschlüsseln. Kopiert jemand die Datei in einen anderen Namespace, funktioniert sie nicht.

## 4. Nur bei privatem Repository: das GitHub-Token versiegeln

Hast du in Kapitel 13 kein Token angelegt (öffentliches Repository), **überspringe diesen Schritt** und in Schritt 5 die zweite Zeile.

Das Repository-Secret für Argo CD braucht zusätzlich sein **Label** (Kapitel 13). Mit `kubectl label --local` hängen
wir es an, bevor verschlüsselt wird:

```bash
mkdir -p kubernetes/secrets/argocd
kubectl create secret generic repo-homelab -n argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/Katagawa94/homelab-tutorial.git \
  --from-literal=username=git \
  --from-literal=password='<TOKEN>' \
  --dry-run=client -o yaml \
| kubectl label -f - --local -o yaml argocd.argoproj.io/secret-type=repository \
| kubeseal --format yaml > kubernetes/secrets/argocd/repo-homelab.yaml
```

Prüfe, dass das Label mitgekommen ist:

```bash
grep -A2 labels kubernetes/secrets/argocd/repo-homelab.yaml
```

```
      labels:
        argocd.argoproj.io/secret-type: repository
```

## 5. Bestehende Secrets übergeben

Die beiden Secrets existieren schon im Cluster, von Hand angelegt. Aus Sicherheitsgründen überschreibt der Controller
keine Secrets, die er nicht selbst angelegt hat. Wir erlauben es ihm ausdrücklich:

```bash
kubectl annotate secret operator-oauth -n tailscale sealedsecrets.bitnami.com/managed=true
kubectl annotate secret repo-homelab -n argocd sealedsecrets.bitnami.com/managed=true
```

## 6. Ins Git damit

Die Application [`secrets`](../kubernetes/katalog/secrets.yaml) rollt alles aus `kubernetes/secrets/` aus, inklusive Unterordnern:

```bash
cp kubernetes/katalog/secrets.yaml kubernetes/aktiv/
git add kubernetes/aktiv/secrets.yaml kubernetes/secrets/
git status                         # Nur SealedSecrets? Keine Klartext-Secrets?
git commit -m "Secrets für Tailscale und Argo CD versiegelt"
git push
```

> ⚠️ **Schau bei `git status` genau hin**: Es dürfen nur die Dateien in `kubernetes/secrets/` und `kubernetes/aktiv/secrets.yaml`
> neu sein. Taucht irgendwo ein Klartext-Secret auf: **nicht committen!**

## 7. Prüfen

```bash
kubectl get sealedsecrets -A
```

```
NAMESPACE   NAME             STATUS   SYNCED   AGE
argocd      repo-homelab              True     1m
tailscale   operator-oauth            True     1m
```

`SYNCED True` heißt: Der Controller hat entschlüsselt und das Secret angelegt bzw. übernommen. Das Secret gehört jetzt dem SealedSecret:

```bash
kubectl get secret operator-oauth -n tailscale -o jsonpath='{.metadata.ownerReferences[0].kind}'; echo
```

```
SealedSecret
```

(Die Zeile `repo-homelab` gibt es nur bei privatem Repository.) In Argo CD ist die App **secrets** *Synced* und *Healthy*.

### Der Beweis

Lösch das Secret im Cluster:

```bash
kubectl delete secret operator-oauth -n tailscale
kubectl get secret operator-oauth -n tailscale
```

Nach wenigen Sekunden ist es wieder da, neu erzeugt aus dem SealedSecret in Git. 🎉

## Ein Secret ändern

Wird z. B. der OAuth-Client von Tailscale (oder bei privatem Repository das GitHub-Token) erneuert, wiederholst du einfach Schritt 3 bzw. 4 mit dem neuen Wert. Die Datei wird überschrieben,
dann folgen `git commit` und `git push`. Den Rest erledigen Argo CD und der Controller.

## Regeln für Secrets ab jetzt

1. **Nie** ein `kind: Secret` mit echten Werten ins Git, nur `kind: SealedSecret`.
2. Alle SealedSecrets liegen in `kubernetes/secrets/<namespace>/<name>.yaml`.
3. Den privaten Schlüssel des Controllers **sicher aufbewahren**.

## ✅ Checkpoint

- [ ] `kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets` zeigt den Controller als `Running`.
- [ ] Der private Schlüssel ist sicher außerhalb von Cluster und Git abgelegt.
- [ ] `kubectl get sealedsecrets -A` zeigt die SealedSecrets mit `SYNCED True`.
- [ ] Ein gelöschtes Secret wurde automatisch wiederhergestellt.
- [ ] Argo CD zeigt alle Apps als **Synced** und **Healthy**.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| `kubeseal`: `cannot fetch certificate` | Läuft der Controller? Heißt er `sealed-secrets-controller` im Namespace `kube-system`? |
| `SYNCED False`, Meldung `Resource already exists and is not managed by SealedSecret` | Schritt 5 vergessen → Secret annotieren |
| `no key could decrypt secret` | Mit einem anderen Cluster (anderem Schlüssel) verschlüsselt, oder Name/Namespace nachträglich geändert → neu versiegeln |
| Argo-CD-Repository plötzlich `authentication required` | Label fehlt im SealedSecret → Schritt 4 mit `kubectl label …` wiederholen |
| Details nachlesen | `kubectl describe sealedsecret <name> -n <namespace>` und `kubectl logs -n kube-system deploy/sealed-secrets-controller` |

## 🎓 Was du gelernt hast

- **Sealed Secrets** verschlüsselt mit einem öffentlichen Schlüssel, nur der Controller im Cluster kann entschlüsseln.
- `kubectl create … --dry-run=client -o yaml | kubeseal` erzeugt SealedSecrets, ohne dass Klartext auf der Platte landet.
- SealedSecrets sind an Name und Namespace gebunden.
- Der **private Schlüssel** muss gesichert werden, sonst sind nach einem Neuaufbau alle Secrets verloren.
- Jetzt liegt **alles** in Git: Apps, Einstellungen und (verschlüsselt) Zugangsdaten.

---

⬅️ **Zurück:** [13 – GitOps mit Argo CD](13-argocd.md) · ➡️ **Weiter:** [15 – GPU an die VM durchreichen](15-gpu-passthrough.md)
