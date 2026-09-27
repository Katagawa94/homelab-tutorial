# 25 – Paperless-ngx

> **Was du am Ende hast:** Ein digitales Dokumentenarchiv. Rechnungen, Verträge und Briefe werden eingescannt,
> per Texterkennung (OCR) durchsuchbar gemacht und automatisch sortiert.
>
> ⏱️ **Zeit:** ca. 45 Minuten
>
> 🧠 **Neue Begriffe:** OCR, Warteschlange (Broker), CSRF

---

## Was macht Paperless?

Du fotografierst oder scannst ein Dokument, und Paperless

1. **erkennt den Text** darin (OCR, auf Deutsch und Englisch),
2. speichert ein **durchsuchbares PDF**,
3. schlägt **Korrespondent** (z. B. „Stadtwerke“), **Dokumenttyp** („Rechnung“) und **Tags** vor und lernt dabei mit.

Danach findest du jede Rechnung der letzten zehn Jahre mit einer Suche nach „Stadtwerke 2026“.

## Aufbau

```
 Browser / Handy-App ──► paperless (Webserver + Hintergrund-Arbeiter)
                               │  "Dokument X verarbeiten"
                               ▼
                         paperless-redis (Valkey): die Warteschlange
```

Das Muster kennst du von Immich: Der Webserver nimmt Aufträge an und legt sie in eine **Warteschlange** (den *Broker*,
hier Valkey). Ein Hintergrund-Prozess im selben Container arbeitet sie ab. So bleibt die Oberfläche flott, auch wenn gerade
ein 50-seitiges PDF per OCR verarbeitet wird.

Als Datenbank nutzt Paperless eine **SQLite**-Datei im PVC `paperless-data`. Für einen Haushalt reicht das völlig.

| PVC | Inhalt | Größe |
|-----|--------|-------|
| `paperless-data` | Datenbank, Suchindex, gelernte Zuordnungen | 2 GiB |
| `paperless-media` | **die Dokumente** (Originale + durchsuchbare PDFs) | 20 GiB |

Beide liegen auf der Systemplatte und sind damit im Proxmox-Backup (Kapitel 27) enthalten.

## Die wichtigsten Einstellungen

Aus [`kubernetes/apps/paperless/deployment.yaml`](../kubernetes/apps/paperless/deployment.yaml):

```yaml
            - name: PAPERLESS_URL         # Adresse im Tailnet, wichtig für den Login-Schutz (CSRF)
              value: https://paperless.tail9x8y7z.ts.net
            - name: PAPERLESS_REDIS
              value: redis://paperless-redis:6379
            - name: PAPERLESS_OCR_LANGUAGE
              value: deu+eng              # Texterkennung auf Deutsch und Englisch
            - name: USERMAP_UID
              value: "1000"
```

> 💡 **Was ist CSRF?** Ein Schutz gegen gefälschte Formulare von fremden Webseiten. Paperless akzeptiert Logins nur
> von der Adresse in `PAPERLESS_URL`. Stimmt die nicht mit der Adresse im Browser überein, schlägt das Anmelden fehl.
> Deshalb war der Schritt „Tailnet-Namen eintragen“ in Kapitel 22 wichtig.

## 1. Secrets anlegen

Paperless braucht einen geheimen Schlüssel (für Sitzungen) und die Zugangsdaten des ersten Admins:

```bash
mkdir -p kubernetes/secrets/paperless
kubectl create secret generic paperless-secrets -n paperless \
  --from-literal=PAPERLESS_SECRET_KEY="$(openssl rand -hex 32)" \
  --from-literal=PAPERLESS_ADMIN_USER='<BENUTZERNAME>' \
  --from-literal=PAPERLESS_ADMIN_PASSWORD='<PASSWORT>' \
  --dry-run=client -o yaml \
| kubeseal --format yaml > kubernetes/secrets/paperless/paperless-secrets.yaml
```

> 💡 `$(openssl rand -hex 32)` wird von der Shell **vor** dem Befehl ausgeführt und durch 64 zufällige Zeichen ersetzt.
> Den Schlüssel musst du dir nicht merken.

## 2. Aktivieren

```bash
cp kubernetes/katalog/paperless.yaml kubernetes/aktiv/
git add kubernetes/aktiv/paperless.yaml kubernetes/secrets/paperless/
git commit -m "Paperless-ngx aktivieren"
git push
```

```bash
kubectl get pods -n paperless -w
```

Der erste Start dauert 1–3 Minuten (Datenbank anlegen). Mitlesen: `kubectl logs -n paperless deploy/paperless -f`.

## 3. Erste Schritte

Öffne <https://paperless.tail1a2b3c.ts.net> und melde dich mit den Zugangsdaten aus dem Secret an.

### Ein Dokument hochladen

Zieh ein PDF oder ein Foto eines Briefs auf die Seite (oder **Dokumente → Hochladen**). Nach einigen Sekunden
erscheint es in der Liste. Öffne es: Unter **Inhalt** steht der erkannte Text.

### Ordnung schaffen

| Begriff | Beispiel | Wofür |
|---------|----------|-------|
| **Korrespondent** | Stadtwerke, Finanzamt, Arbeitgeber | Wer hat es geschickt? |
| **Dokumenttyp** | Rechnung, Vertrag, Kontoauszug | Was ist es? |
| **Tags** | Steuer 2026, Auto, Wohnung | frei wählbare Schlagworte |
| **Speicherpfad** | optional | wie die Datei im Archiv benannt wird |

Weise den ersten Dokumenten diese Angaben von Hand zu. Paperless lernt daraus und schlägt sie beim nächsten ähnlichen Dokument selbst vor.

### Vom Handy scannen

Es gibt Community-Apps für Paperless-ngx, z. B. **Paperless Mobile** (Android) oder **Swift Paperless** (iOS). Server:
`https://paperless.tail1a2b3c.ts.net`. Dort fotografierst du einen Brief und lädst ihn direkt hoch. Das Original kann
danach (bei unwichtigen Dokumenten) ins Altpapier.

> 💡 **Office-Dateien** (Word, Excel, E-Mails) kann Paperless mit zwei Zusatzdiensten (*Tika* und *Gotenberg*) ebenfalls
> verarbeiten. Die sind hier nicht enthalten, aber mit dem Wissen aus diesem Tutorial kannst du sie selbst ergänzen:
> zwei Deployments plus Services im Namespace `paperless`.

## ✅ Checkpoint

- [ ] `kubectl get pods -n paperless` zeigt `paperless` und `paperless-redis` als `Running`.
- [ ] Anmeldung unter `https://paperless.<tailnet>.ts.net` funktioniert.
- [ ] Ein hochgeladenes Dokument ist per Volltext durchsuchbar.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| `CSRF verification failed` beim Login | `PAPERLESS_URL` stimmt nicht mit der Adresse im Browser überein (Kapitel 22, Schritt 1) |
| Login mit den Secret-Daten klappt nicht | Der Admin wird nur beim **ersten** Start angelegt. Passwort ändern: `kubectl exec -it -n paperless deploy/paperless -- python3 manage.py changepassword <BENUTZER>` |
| Dokumente bleiben „in Bearbeitung“ | Läuft `paperless-redis`? Logs: `kubectl logs -n paperless deploy/paperless` |
| Pod `OOMKilled` bei großen PDFs | `limits.memory` erhöhen |
| Texterkennung schlecht | Bessere Scans (300 dpi, gerade, gut beleuchtet). Bei rein deutschen Dokumenten `PAPERLESS_OCR_LANGUAGE=deu` |

## 🎓 Was du gelernt hast

- Paperless trennt **Webserver** und **Hintergrundarbeit** über eine Warteschlange (Valkey), ein sehr verbreitetes Muster.
- **SQLite** reicht für viele Homelab-Apps. Eine eigene Datenbank wie bei Immich ist nicht immer nötig.
- Manche Apps prüfen, unter welcher Adresse sie aufgerufen werden (**CSRF**). Die Adresse muss dann konfiguriert sein.
- **Einmal-Einstellungen** (Admin-Konto) wirken nur beim ersten Start. Spätere Änderungen macht man in der App.

---

⬅️ **Zurück:** [24 – Immich](24-immich.md) · ➡️ **Weiter:** [26 – Uptime Kuma](26-uptime-kuma.md)
