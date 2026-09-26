# 21 – Bazarr & Seerr

> **Was du am Ende hast:** Bazarr lädt automatisch deutsche und englische Untertitel. In Seerr können du und deine
> Familie Filme und Serien bequem per Klick wünschen, auch vom Handy aus.
>
> ⏱️ **Zeit:** ca. 45 Minuten
>
> 🧠 **Neue Begriffe:** Sprachprofil, Untertitel-Provider, Tailscale-Sharing

---

## 1. Aktivieren

```bash
cp kubernetes/katalog/{bazarr,seerr}.yaml kubernetes/aktiv/
git add kubernetes/aktiv/
git commit -m "Bazarr und Seerr aktivieren"
git push
```

```bash
kubectl get pods -n media
```

Jetzt laufen im Namespace `media` acht Apps: Jellyfin, qBittorrent (2 Container), Prowlarr, Sonarr, Radarr, Bazarr und Seerr.

> 💡 **Seerr ist anders gebaut:** Es ist kein LinuxServer-Image, sondern das offizielle Image des Projekts. Es läuft
> von vornherein als Benutzer `1000` (wie Jellyfin) und braucht deshalb einen `securityContext` statt `PUID`/`PGID`.
> Schau in [`kubernetes/apps/media/seerr/deployment.yaml`](../kubernetes/apps/media/seerr/deployment.yaml) und vergleiche mit Sonarr.
> Seerr ist übrigens der Nachfolger von *Jellyseerr* und *Overseerr*, die sich 2025 zusammengeschlossen haben.

## Teil A: Bazarr, Untertitel automatisch

Bazarr beobachtet Sonarr und Radarr. Kommt ein neuer Film oder eine neue Folge dazu, sucht Bazarr passende Untertitel
und legt sie **neben** die Videodatei, z. B. `Film (2020).de.srt`. Jellyfin findet sie dort automatisch.

Das hilft auch dem Samsung-TV: **Text-Untertitel (SRT)** kann er direkt anzeigen. Bild-Untertitel von Blu-rays
müssten dagegen ins Video eingebrannt werden (Kapitel 12).

Öffne <https://bazarr.tail1a2b3c.ts.net>.

### Anmeldung schützen

**Settings → General → Security → Authentication:** `Form`, Benutzername und Passwort → **Save**.

### Sprachen

**Settings → Languages**:

1. **Languages Filter:** `German`, `English`
2. **Languages Profiles → Add New Profile:**
   - Name: `Deutsch + Englisch`
   - Languages: `German`, `English` hinzufügen
3. **Default Settings:** ☑ Series und ☑ Movies → Profil `Deutsch + Englisch`
4. **Save**

### Untertitel-Quellen (Provider)

**Settings → Providers → +**:

| Provider | Anmerkung |
|----------|-----------|
| **OpenSubtitles.com** | die größte Sammlung. Kostenloses Konto auf <https://www.opensubtitles.com> nötig, Zugangsdaten eintragen |
| **Podnapisi** | ohne Konto nutzbar |
| **Embedded Subtitles** | nutzt bereits in der Videodatei enthaltene Untertitel |

### Mit Sonarr und Radarr verbinden

**Settings → Sonarr**: ☑ Enabled

| Feld | Wert |
|------|------|
| Address | **`sonarr`** |
| Port | `8989` |
| API Key | aus Sonarr (Settings → General) |

**Test** → **Save**. Dasselbe unter **Settings → Radarr** mit `radarr`, Port `7878` und dem Radarr-API-Key.

> 💡 Bazarr erwartet hier nur den **Namen**, ohne `http://`, anders als Prowlarr. Jede App hat ihre Eigenheiten.
> Schau im Zweifel, was das Feld verlangt.

Unter **Movies** erscheint jetzt *Night of the Living Dead* aus Kapitel 20. Bazarr sucht selbstständig, du kannst die
Suche aber auch per Lupen-Symbol anstoßen. Danach:

> 🐧 **In der VM**

```bash
ls "/data/media/movies/Night of the Living Dead (1968)/"
```

```
Night of the Living Dead (1968).en.srt
Night of the Living Dead (1968).mp4
```

In Jellyfin lassen sich die Untertitel jetzt beim Abspielen auswählen.

## Teil B: Seerr, die Wunschliste

Seerr ist die **freundliche Oberfläche** für alle, die nicht an Radarr und Sonarr herumschrauben sollen: Film suchen,
auf **Anfragen** klicken, fertig. Seerr gibt den Wunsch an Radarr oder Sonarr weiter.

Öffne <https://seerr.tail1a2b3c.ts.net>. Ein Einrichtungsassistent startet.

### Schritt 1: Mit Jellyfin verbinden

| Feld | Wert |
|------|------|
| Server-Typ | **Jellyfin** |
| Hostname | **`jellyfin`** |
| Port | `8096` |
| SSL | ☐ |
| E-Mail | deine E-Mail-Adresse (für Seerr) |
| Benutzername / Passwort | dein **Jellyfin**-Admin-Konto |

Seerr übernimmt die Anmeldung von Jellyfin. Du brauchst also kein eigenes Seerr-Passwort.

### Schritt 2: Bibliotheken

**Bibliotheken synchronisieren** → ☑ **Filme** · ☑ **Serien** → **Scan starten**. Seerr weiß dann, was schon vorhanden ist.

### Schritt 3: Dienste

**Radarr-Server hinzufügen**:

| Feld | Wert |
|------|------|
| Standard-Server | ☑ |
| Servername | `Radarr` |
| Hostname oder IP | **`radarr`** |
| Port | `7878` |
| API-Schlüssel | aus Radarr |
| → **Testen**, dann: | |
| Qualitätsprofil | `HD-1080p` |
| Stammverzeichnis | `/data/media/movies` |
| Mindestverfügbarkeit | `Veröffentlicht` |

**Sonarr-Server hinzufügen**: analog mit `sonarr`, Port `8989`, Profil `HD-1080p`, Stammverzeichnis `/data/media/tv`.

**Einrichtung abschließen**.

### Allgemeine Einstellungen

**Einstellungen → Allgemein → Anwendungs-URL:** `https://seerr.tail1a2b3c.ts.net`. So stimmen Links in
Benachrichtigungen.

### Ausprobieren

Suche oben nach einem Film, klicke ihn an → **Anfragen**. In Radarr unter **Activity** siehst du, wie die Suche startet.

## Teil C: Familie und Freunde einladen

Deine Familie soll Jellyfin (oder Seerr) nutzen, aber nicht in dein ganzes Tailnet dürfen. Dafür gibt es in Tailscale
das **Teilen einzelner Geräte**:

1. [Admin-Konsole → Machines](https://login.tailscale.com/admin/machines) → beim Gerät **jellyfin** auf **⋯ → Share…**
2. Einladungslink erzeugen oder E-Mail-Adresse eingeben.
3. Die eingeladene Person installiert Tailscale, meldet sich mit **ihrem eigenen** Konto an und nimmt die Einladung an.
4. Sie erreicht jetzt `https://jellyfin.<dein-tailnet>.ts.net`, aber **nur dieses eine Gerät**, nicht Proxmox, nicht Sonarr.

Dasselbe kannst du mit **seerr** machen.

In **Jellyfin** legst du für jede Person einen eigenen Benutzer an (**Dashboard → Benutzer**). In **Seerr** importierst
du diese Benutzer unter **Benutzer → Jellyfin-Benutzer importieren**. Neue Anfragen von Nicht-Admins musst du in Seerr
freigeben, sofern du ihnen nicht die Berechtigung **Automatisch genehmigen** gibst. So bleibt die Kontrolle über den
Plattenplatz bei dir.

## 🎉 Teil D geschafft!

Der komplette Medien-Kreislauf läuft:

```
Wunsch (Seerr) → Suche (Radarr/Sonarr + Prowlarr) → Download (qBittorrent + Proton VPN)
      → Hardlink nach /data/media → Untertitel (Bazarr) → Anschauen (Jellyfin, auch auf dem Samsung-TV)
```

Wie viel Leistung braucht das alles?

```bash
kubectl top pods -n media
```

```
NAME                           CPU(cores)   MEMORY(bytes)
bazarr-…                       4m           180Mi
jellyfin-…                     12m          610Mi
prowlarr-…                     2m           160Mi
qbittorrent-…                  15m          310Mi
radarr-…                       6m           240Mi
seerr-…                        3m           220Mi
sonarr-…                       6m           250Mi
```

Zusammen etwa 2 GB RAM im Ruhezustand. Die VM hat 12 GB, also ist noch viel Luft für Teil E.

## ✅ Checkpoint

- [ ] Bazarr ist mit Sonarr und Radarr verbunden (beide Tests grün).
- [ ] Neben dem Testfilm liegt eine `.srt`-Datei.
- [ ] Seerr ist mit Jellyfin, Radarr und Sonarr verbunden.
- [ ] Eine Anfrage in Seerr taucht in Radarr auf.
- [ ] Argo CD zeigt alle Apps als **Synced** und **Healthy**.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Bazarr findet keine Untertitel | Provider eingerichtet? Bei OpenSubtitles.com gibt es ein Tageslimit. **System → Logs** in Bazarr lesen |
| Bazarr: `Unable to connect to Sonarr` | Nur `sonarr` als Adresse (ohne `http://`), Port und API-Key prüfen |
| Seerr: Jellyfin-Anmeldung schlägt fehl | Hostname `jellyfin`, Port `8096`, SSL aus. Jellyfin-Benutzer muss Admin sein |
| Seerr zeigt vorhandene Filme als „nicht verfügbar“ | **Einstellungen → Jellyfin → Bibliotheken scannen** |
| Seerr-Pod startet nicht: `permission denied` in `/app/config` | `kubectl logs -n media deploy/seerr`. Der `securityContext` muss `1000` sein |
| Eingeladene Person erreicht Jellyfin nicht | Hat sie die Einladung mit **ihrem** Tailscale-Konto angenommen? Ist Tailscale auf ihrem Gerät verbunden? |

## 🎓 Was du gelernt hast

- **Bazarr** ergänzt Untertitel über Sprachprofile und Provider und legt sie als `.srt` neben die Videos.
- **Seerr** ist eine einfache Oberfläche für Wünsche und nutzt die Jellyfin-Anmeldung.
- Nicht jedes Image funktioniert gleich: LinuxServer-Images nehmen `PUID/PGID`, andere laufen per `securityContext` als Benutzer `1000`.
- Mit **Tailscale-Sharing** gibst du anderen gezielt Zugriff auf einzelne Dienste, ohne offene Ports und ohne Zugang zum restlichen Tailnet.

---

⬅️ **Zurück:** [20 – Sonarr & Radarr](20-sonarr-radarr.md) · ➡️ **Weiter:** 22 – Homepage *(folgt in Phase 5)*
