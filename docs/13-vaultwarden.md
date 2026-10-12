# 13 – Vaultwarden

> **Was du am Ende hast:** Ein eigener Passwortmanager, kompatibel mit allen offiziellen Bitwarden-Apps (Browser,
> Handy, Desktop). Er ist **nur in deinem Tailnet** erreichbar, und neue Registrierungen sind gesperrt.
>
> ⏱️ **Zeit:** ca. 45 Minuten
>
> 🧠 **Neue Begriffe:** [Kustomize](glossar.md#container--kubernetes), [Probes](glossar.md#container--kubernetes),
> Konfigurationsänderung per GitOps, Master-Passwort

---

> 📸 **Snapshot-Routine:** Snapshot der VM anlegen (z. B. `vor-vaultwarden`).

## Teil D: die wichtigsten Dienste zuerst

Die Plattform steht: Tailscale bringt Apps ins Tailnet, Argo CD rollt sie aus Git aus, Sealed Secrets schützt die
Passwörter. Jetzt kommen die drei Dienste, die im Alltag am meisten bringen:

| Kapitel | App | Wofür |
|---------|-----|-------|
| 13 | **Vaultwarden** | Passwortmanager für alle Geräte |
| 14 | **Nextcloud** | eigene Cloud für Dateien, Kalender und Kontakte |
| 15 | **Pi-hole** | Werbe- und Tracking-Blocker für alle Geräte |

Jede App bekommt ihren **eigenen Namespace** und wird, wie die Demo-App in Kapitel 11, per Git aktiviert.

---

## Was ist Vaultwarden?

**Vaultwarden** ist ein schlanker, inoffizieller Server für **Bitwarden**. Du benutzt die ganz normalen Bitwarden-Apps
und stellst dort nur deinen eigenen Server ein. Deine Passwörter liegen dann bei dir statt in einer fremden Cloud.

> ⚠️ **Verantwortung:** Ein selbst betriebener Passwortmanager heißt: Du bist für **Backups** verantwortlich. Geht die
> VM kaputt und es gibt kein Backup, sind alle Passwörter weg. Kapitel 29 (Backup) ist deshalb Pflicht, und bis dahin
> exportierst du den Tresor regelmäßig (siehe unten).

**Sicherheitsvorteil unseres Aufbaus:** Vaultwarden ist **nicht im Internet**, sondern nur im Tailnet erreichbar.
Wer es angreifen will, muss erst in dein Tailnet kommen.

## 1. Einmalig: deinen Tailnet-Namen eintragen

Einige Apps müssen ihre eigene Adresse kennen (z. B. `https://vaultwarden.tail1a2b3c.ts.net`). In den Dateien unter
`kubernetes/apps/` steht dafür der Platzhalter **`tail1a2b3c.ts.net`**. Ersetze ihn einmal überall durch deinen
Tailnet-Namen (den vom Spickzettel):

```bash
grep -rl 'tail1a2b3c.ts.net' kubernetes/apps/
```

```
kubernetes/apps/homepage/config/services.yaml
kubernetes/apps/homepage/deployment.yaml
kubernetes/apps/nextcloud/deployment.yaml
kubernetes/apps/paperless/deployment.yaml
kubernetes/apps/vaultwarden/deployment.yaml
```

```bash
grep -rl 'tail1a2b3c.ts.net' kubernetes/apps/ | xargs sed -i 's/tail1a2b3c\.ts\.net/<DEIN-TAILNET>.ts.net/g'
git diff --stat
git commit -am "Tailnet-Namen eintragen"
git push
```

(Also z. B. `s/tail1a2b3c\.ts\.net/tail9x8y7z.ts.net/g`.) Das gilt gleich für alle späteren Apps mit.

## 2. Die Manifeste verstehen

[`kubernetes/apps/vaultwarden/`](../kubernetes/apps/vaultwarden/) enthält fünf Dateien. Das Muster wirst du bei jeder
weiteren App wiedersehen:

```
kubernetes/apps/vaultwarden/
├── kustomization.yaml   ← zählt auf, was zusammengehört
├── namespace.yaml       ← Namespace "vaultwarden"
├── pvc-data.yaml        ← Speicher für den Tresor
├── deployment.yaml      ← Vaultwarden selbst
├── service.yaml         ← feste Adresse im Cluster
└── ingress.yaml         ← https://vaultwarden.<tailnet>.ts.net (Kapitel 10)
```

### Kustomize: mehrere Dateien als Einheit

```yaml
# kubernetes/apps/vaultwarden/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: vaultwarden
resources:
  - namespace.yaml
  - pvc-data.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
```

**Kustomize** ist in `kubectl` eingebaut. Die `kustomization.yaml` zählt auf, welche Dateien zusammengehören, und
`namespace: vaultwarden` setzt den Namespace für alle auf einmal. Argo CD erkennt die Datei und benutzt Kustomize
automatisch. Was dabei herauskommt, kannst du dir vorher ansehen:

```bash
kubectl kustomize kubernetes/apps/vaultwarden | less
```

> 💡 **Kustomize oder Helm?** Beide erzeugen am Ende normale Manifeste. **Helm** nutzen wir für fertige Pakete anderer
> Leute (Tailscale Operator, Argo CD), **Kustomize** für unsere eigenen Manifeste. So bleibt alles lesbar.

### Der Speicher ist geschützt

```yaml
# kubernetes/apps/vaultwarden/pvc-data.yaml (Ausschnitt)
metadata:
  name: vaultwarden-data
  annotations:
    argocd.argoproj.io/sync-options: Prune=false   # Argo CD darf diesen PVC nie löschen
```

Diese Annotation steht an **jedem** PVC im Repository. Löschst du aus Versehen eine Datei, räumt Argo CD alles weg,
aber nie deine Daten (Kapitel 11, „Sicherheitsnetze“).

### Probes: Ist Vaultwarden gesund?

```yaml
          startupProbe:
            httpGet:
              path: /alive
              port: http
            periodSeconds: 5
            failureThreshold: 30
          livenessProbe:
            httpGet:
              path: /alive
              port: http
            periodSeconds: 30
```

Vaultwarden antwortet unter `/alive`, solange es gesund ist. Kubernetes fragt dort regelmäßig nach:

| Probe | Frage | Bei „Nein“ |
|-------|-------|------------|
| **startupProbe** | „Bist du schon hochgefahren?“ | weiter warten (hier bis zu 30 × 5 s) |
| **readinessProbe** | „Kannst du gerade Anfragen annehmen?“ | Service schickt keine Anfragen an diesen Pod (kommt bei Jellyfin vor) |
| **livenessProbe** | „Lebst du noch?“ | Container wird neu gestartet |

So erkennt Kubernetes auch eine App, die zwar läuft, aber hängt. Gegen solche Fälle hilft die Selbstheilung aus Kapitel 07 allein nicht.

### Zwei wichtige Einstellungen

```yaml
          env:
            - name: DOMAIN        # die Adresse, unter der Vaultwarden erreichbar ist
              value: https://vaultwarden.tail9x8y7z.ts.net
            - name: SIGNUPS_ALLOWED
              value: "true"       # Kapitel 13: nach dem Anlegen deines Kontos auf "false" setzen!
```

- **`DOMAIN`** braucht Vaultwarden für Links und Sicherheitsfunktionen. Die hast du in Schritt 1 eingetragen.
- **`SIGNUPS_ALLOWED`**: Solange `true`, kann sich jeder, der die Seite erreicht, ein Konto anlegen. Das brauchen wir
  genau einmal, für dich.

## 3. Aktivieren

```bash
cp kubernetes/katalog/vaultwarden.yaml kubernetes/aktiv/
git add kubernetes/aktiv/vaultwarden.yaml
git commit -m "Vaultwarden aktivieren"
git push
```

In Argo CD auf **root → Refresh**, dann erscheint die Kachel **vaultwarden**.

```bash
kubectl get pods,pvc,ingress -n vaultwarden
```

## 4. Dein Konto anlegen

1. Öffne <https://vaultwarden.tail1a2b3c.ts.net> → **Konto erstellen**.
2. E-Mail-Adresse, Name und ein **Master-Passwort**.

> ⚠️ **Das Master-Passwort kann niemand zurücksetzen**, auch du als Server-Betreiber nicht, denn die Daten sind damit
> verschlüsselt. Wähle eine lange Passphrase (z. B. vier bis sechs zufällige Wörter), die du dir merken kannst, und
> schreibe sie auf Papier an einen sicheren Ort.

3. Anmelden. Dein Tresor ist leer und bereit.

## 5. Registrierung schließen, per Git

Jetzt kommt eine typische GitOps-Aufgabe: eine **Einstellung ändern**. Öffne
`kubernetes/apps/vaultwarden/deployment.yaml` und ändere:

```yaml
            - name: SIGNUPS_ALLOWED
              value: "false"      # Registrierung geschlossen
```

```bash
git commit -am "Vaultwarden: Registrierung schließen"
git push
```

Nach dem Sync startet Vaultwarden neu. Test: Auf der Anmeldeseite **Konto erstellen** probieren. Es erscheint
*„Registration not allowed or user already exists“*. ✅

> 💡 Wolltest du später doch jemandem ein Konto geben (Familie), stellst du den Wert kurz auf `"true"`, lässt die Person
> sich registrieren und schließt wieder. Jede Änderung steht dann im `git log`.

## 6. Die Apps verbinden

In allen Bitwarden-Apps wählst du auf dem Anmeldebildschirm den Server aus:

1. Bei **„Anmelden bei“** bzw. **„Region“** → **Selbst gehostet**
2. **Server-URL:** `https://vaultwarden.tail1a2b3c.ts.net`
3. E-Mail und Master-Passwort

| Gerät | App |
|-------|-----|
| Browser (Firefox, Chrome …) | Erweiterung **Bitwarden** |
| Handy | App **Bitwarden** (iOS/Android) |
| Desktop | **Bitwarden**-App. Unter NixOS z. B. `bitwarden-desktop` |

> 💡 **Unterwegs:** Die Apps müssen den Server erreichen, also Tailscale auf dem Handy eingeschaltet lassen. Ohne
> Verbindung funktionieren sie trotzdem mit einer lokalen, verschlüsselten Kopie. Nur Änderungen werden dann erst später
> abgeglichen.

### Passwörter umziehen

Aus einem anderen Passwortmanager exportieren und in Vaultwarden importieren: Web-Oberfläche → **Werkzeuge → Daten importieren**.
Danach die Exportdatei **sicher löschen**, denn sie enthält alle Passwörter im Klartext.

## 7. Bis zum richtigen Backup: exportieren

Bis Kapitel 29 eingerichtet ist, mach regelmäßig einen **verschlüsselten Export**:

Web-Oberfläche → **Werkzeuge → Tresor exportieren** → Format **`.json (Encrypted)`** → *Passwortgeschützt*,
eigenes Export-Passwort. Die Datei auf einem anderen Gerät oder USB-Stick aufbewahren.

## ✅ Checkpoint

- [ ] `grep -r tail1a2b3c kubernetes/apps/` findet nichts mehr.
- [ ] `https://vaultwarden.<tailnet>.ts.net` ist erreichbar, dein Konto existiert.
- [ ] `SIGNUPS_ALLOWED` steht auf `"false"`, eine neue Registrierung wird abgelehnt.
- [ ] Browser-Erweiterung und Handy-App sind mit deinem Server verbunden.
- [ ] Es gibt einen ersten verschlüsselten Export.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| App meldet `An error has occurred` bzw. kann nicht verbinden | Server-URL exakt mit `https://` eingetragen? Läuft Tailscale auf dem Gerät? |
| Web-Oberfläche zeigt eine Warnung zur `DOMAIN` | `DOMAIN` muss genau der Adresse im Browser entsprechen (Schritt 1) |
| Registrierung trotz `false` möglich | Sync abgewartet? `kubectl get deploy vaultwarden -n vaultwarden -o yaml \| grep -A1 SIGNUPS` |
| Master-Passwort vergessen | Leider nicht wiederherstellbar. Neues Konto anlegen und aus dem letzten Export importieren |

## 🎓 Was du gelernt hast

- Jede App besteht aus demselben Muster: **Kustomize** fasst Namespace, PVC, Deployment, Service und Ingress zusammen.
- **Probes** lassen Kubernetes erkennen, ob eine App hochgefahren und gesund ist.
- Vaultwarden ist ein Bitwarden-kompatibler Server. Alle offiziellen Apps funktionieren damit.
- Dienste **nur im Tailnet** anzubieten, verkleinert die Angriffsfläche enorm.
- Einstellungen änderst du per **Git**: Datei ändern → push → Argo CD startet die App mit dem neuen Wert.
- Selbst betreiben heißt selbst sichern.

---

⬅️ **Zurück:** [12 – Secrets im Git](12-sealed-secrets.md) · ➡️ **Weiter:** [14 – Nextcloud](14-nextcloud.md)
