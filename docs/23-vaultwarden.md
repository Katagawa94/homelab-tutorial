# 23 – Vaultwarden

> **Was du am Ende hast:** Ein eigener Passwortmanager, kompatibel mit allen offiziellen Bitwarden-Apps (Browser,
> Handy, Desktop). Er ist **nur in deinem Tailnet** erreichbar, und neue Registrierungen sind gesperrt.
>
> ⏱️ **Zeit:** ca. 30 Minuten
>
> 🧠 **Neue Begriffe:** Konfigurationsänderung per GitOps, Master-Passwort

---

## Was ist Vaultwarden?

**Vaultwarden** ist ein schlanker, inoffizieller Server für **Bitwarden**. Du benutzt die ganz normalen Bitwarden-Apps
und stellst dort nur deinen eigenen Server ein. Deine Passwörter liegen dann bei dir statt in einer fremden Cloud.

> ⚠️ **Verantwortung:** Ein selbst betriebener Passwortmanager heißt: Du bist für **Backups** verantwortlich. Geht die
> VM kaputt und es gibt kein Backup, sind alle Passwörter weg. Kapitel 27 (Backup) ist deshalb Pflicht, und bis dahin
> exportierst du den Tresor regelmäßig (siehe unten).

**Sicherheitsvorteil unseres Aufbaus:** Vaultwarden ist **nicht im Internet**, sondern nur im Tailnet erreichbar.
Wer es angreifen will, muss erst in dein Tailnet kommen.

## Die Manifeste

[`kubernetes/apps/vaultwarden/`](../kubernetes/apps/vaultwarden/) enthält nichts Neues: Namespace, PVC, Deployment,
Service und Ingress. Interessant sind nur zwei Umgebungsvariablen:

```yaml
          env:
            - name: DOMAIN        # die Adresse, unter der Vaultwarden erreichbar ist
              value: https://vaultwarden.tail9x8y7z.ts.net
            - name: SIGNUPS_ALLOWED
              value: "true"       # Kapitel 23: nach dem Anlegen deines Kontos auf "false" setzen!
```

- **`DOMAIN`** braucht Vaultwarden für Links und Sicherheitsfunktionen. Du hast sie in Kapitel 22 (Schritt 1) schon eingetragen.
- **`SIGNUPS_ALLOWED`**: Solange `true`, kann sich jeder, der die Seite erreicht, ein Konto anlegen. Das brauchen wir
  genau einmal, für dich.

## 1. Aktivieren

```bash
cp kubernetes/katalog/vaultwarden.yaml kubernetes/aktiv/
git add kubernetes/aktiv/vaultwarden.yaml
git commit -m "Vaultwarden aktivieren"
git push
```

```bash
kubectl get pods -n vaultwarden
```

## 2. Dein Konto anlegen

1. Öffne <https://vaultwarden.tail1a2b3c.ts.net> → **Konto erstellen**.
2. E-Mail-Adresse, Name und ein **Master-Passwort**.

> ⚠️ **Das Master-Passwort kann niemand zurücksetzen**, auch du als Server-Betreiber nicht, denn die Daten sind damit
> verschlüsselt. Wähle eine lange Passphrase (z. B. vier bis sechs zufällige Wörter), die du dir merken kannst, und
> schreibe sie auf Papier an einen sicheren Ort.

3. Anmelden. Dein Tresor ist leer und bereit.

## 3. Registrierung schließen, per Git

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

## 4. Die Apps verbinden

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

## 5. Bis zum richtigen Backup: exportieren

Bis Kapitel 27 eingerichtet ist, mach regelmäßig einen **verschlüsselten Export**:

Web-Oberfläche → **Werkzeuge → Tresor exportieren** → Format **`.json (Encrypted)`** → *Passwortgeschützt*,
eigenes Export-Passwort. Die Datei auf einem anderen Gerät oder USB-Stick aufbewahren.

## ✅ Checkpoint

- [ ] `https://vaultwarden.<tailnet>.ts.net` ist erreichbar, dein Konto existiert.
- [ ] `SIGNUPS_ALLOWED` steht auf `"false"`, eine neue Registrierung wird abgelehnt.
- [ ] Browser-Erweiterung und Handy-App sind mit deinem Server verbunden.
- [ ] Es gibt einen ersten verschlüsselten Export.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| App meldet `An error has occurred` bzw. kann nicht verbinden | Server-URL exakt mit `https://` eingetragen? Läuft Tailscale auf dem Gerät? |
| Web-Oberfläche zeigt eine Warnung zur `DOMAIN` | `DOMAIN` muss genau der Adresse im Browser entsprechen (Kapitel 22, Schritt 1) |
| Registrierung trotz `false` möglich | Sync abgewartet? `kubectl get deploy vaultwarden -n vaultwarden -o yaml \| grep -A1 SIGNUPS` |
| Master-Passwort vergessen | Leider nicht wiederherstellbar. Neues Konto anlegen und aus dem letzten Export importieren |

## 🎓 Was du gelernt hast

- Vaultwarden ist ein Bitwarden-kompatibler Server. Alle offiziellen Apps funktionieren damit.
- Dienste **nur im Tailnet** anzubieten, verkleinert die Angriffsfläche enorm.
- Einstellungen änderst du per **Git**: Datei ändern → push → Argo CD startet die App mit dem neuen Wert.
- Selbst betreiben heißt selbst sichern.

---

⬅️ **Zurück:** [22 – Homepage](22-homepage.md) · ➡️ **Weiter:** [24 – Immich](24-immich.md)
