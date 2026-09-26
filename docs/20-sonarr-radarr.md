# 20 – Sonarr & Radarr

> **Was du am Ende hast:** Radarr (Filme) und Sonarr (Serien) sind mit Prowlarr, qBittorrent und Jellyfin verbunden.
> Ein gewünschter Film wird gesucht, durchs VPN geladen, per Hardlink einsortiert und erscheint automatisch in Jellyfin.
>
> ⏱️ **Zeit:** ca. 1 Stunde
>
> 🧠 **Neue Begriffe:** Root Folder, Download-Kategorie, Qualitätsprofil, Import

---

> ⚖️ Denk an den Hinweis aus [Kapitel 17](17-arr-ueberblick.md): nur legale Inhalte. Das Beispiel in diesem Kapitel ist ein gemeinfreier Film.

## 1. Aktivieren

Sonarr und Radarr sind fast identisch aufgebaut, deshalb richten wir sie zusammen ein. Beide binden **`/data`** ein,
denn sie müssen Dateien von `downloads/` nach `media/` verlinken.

```bash
cp kubernetes/katalog/{sonarr,radarr}.yaml kubernetes/aktiv/
git add kubernetes/aktiv/
git commit -m "Sonarr und Radarr aktivieren"
git push
```

```bash
kubectl get pods -n media -l 'app in (sonarr,radarr)'
```

```
NAME                      READY   STATUS    RESTARTS   AGE
radarr-5c8d7f9b6d-lx7kd   1/1     Running   0          1m
sonarr-6f9d8c7b5d-9mzq7   1/1     Running   0          1m
```

> 💡 `-l 'app in (sonarr,radarr)'` ist ein **Label-Selector** mit Auswahlliste, eine Erweiterung dessen, was du in Kapitel 07 gelernt hast.

Beide Oberflächen öffnen und wie bei Prowlarr **Forms-Login** mit eigenem Passwort einrichten:

- <https://radarr.tail1a2b3c.ts.net>
- <https://sonarr.tail1a2b3c.ts.net>

## 2. Radarr einrichten

Alle Einstellungen findest du unter **Settings**. Oben rechts **Show Advanced** einschalten, damit alle Optionen sichtbar sind.

### Media Management

| Einstellung | Wert | Warum |
|-------------|------|-------|
| Rename Movies | ☑ | einheitliche Namen, die Jellyfin sicher erkennt |
| Standard Movie Format | `{Movie Title} ({Release Year})` | wie in Kapitel 11 |
| Movie Folder Format | `{Movie Title} ({Release Year})` | |
| **Use Hardlinks instead of Copy** | ☑ (Standard) | **der** Grund für die ganze `/data`-Struktur |
| Minimum Free Space | `20480` MB | bei weniger als 20 GB freiem Platz keine Importe mehr |
| **Root Folders → Add Root Folder** | **`/data/media/movies`** | hier landen die Filme |

### Download Clients

**+** → **qBittorrent**:

| Feld | Wert |
|------|------|
| Name | `qBittorrent` |
| Host | **`qbittorrent`** (der Service-Name) |
| Port | `8080` |
| Username / Password | die qBittorrent-Zugangsdaten aus Kapitel 18 |
| Category | `radarr` |

**Test** → **Save**. Die **Kategorie** sorgt dafür, dass qBittorrent Radarrs Downloads in `/data/downloads/radarr/`
ablegt und Radarr nur „seine“ Downloads anfasst.

### Connect: Jellyfin Bescheid sagen

Damit neue Filme sofort in Jellyfin auftauchen, statt erst beim nächsten Bibliotheks-Scan:

1. In **Jellyfin**: **Dashboard → API-Schlüssel → +** → Name `radarr` → Schlüssel kopieren.
2. In **Radarr**: **Settings → Connect → + → Emby / Jellyfin**:

| Feld | Wert |
|------|------|
| Name | `Jellyfin` |
| Notification Triggers | ☑ On File Import · ☑ On File Upgrade · ☑ On Rename · ☑ On Movie Delete |
| Host | **`jellyfin`** |
| Port | `8096` |
| API Key | der Schlüssel aus Jellyfin |
| Update Library | ☑ |

**Test** → **Save**.

### Qualitätsprofil für eine kleine Platte

**Settings → Profiles**: Für 300 GB ist **HD-1080p** ein guter Standard. Ein 4K-Film belegt oft 40–80 GB, ein
1080p-Film 5–15 GB. Du wählst das Profil später bei jedem Film aus. Merk dir einfach: im Zweifel HD-1080p.

## 3. Sonarr einrichten

Genau wie Radarr, mit diesen Unterschieden:

| Bereich | Einstellung | Wert |
|---------|-------------|------|
| Media Management | Rename Episodes | ☑ |
| Media Management | Standard Episode Format | `{Series Title} S{season:00}E{episode:00} - {Episode Title}` |
| Media Management | Season Folder Format | `Season {season:00}` |
| Media Management | Use Hardlinks instead of Copy | ☑ |
| Media Management | Minimum Free Space | `20480` MB |
| Media Management | **Root Folder** | **`/data/media/tv`** |
| Download Clients | qBittorrent, Host `qbittorrent`, Port `8080` | Category **`tv-sonarr`** |
| Connect | Emby / Jellyfin, Host `jellyfin`, Port `8096` | eigener Jellyfin-API-Schlüssel `sonarr` |
| Profiles | Standard | **HD-1080p** |

## 4. Prowlarr mit Sonarr und Radarr verbinden

Jetzt verteilt Prowlarr seine Indexer. Du brauchst die **API-Keys** von Sonarr und Radarr
(jeweils **Settings → General → Security → API Key**).

In **Prowlarr**: **Settings → Apps → + → Radarr**:

| Feld | Wert |
|------|------|
| Sync Level | Full Sync |
| Prowlarr Server | **`http://prowlarr:9696`** |
| Radarr Server | **`http://radarr:7878`** |
| API Key | API-Key von Radarr |

**Test** → **Save**. Dasselbe mit **Sonarr** (`http://sonarr:8989`, API-Key von Sonarr).

Schau in Radarr unter **Settings → Indexers** nach: Dort steht jetzt **Internet Archive (Prowlarr)**, ohne dass du ihn
in Radarr eingetragen hast. ✅

## 5. Der große Test: ein Film von Wunsch bis Jellyfin

Wir holen einen **gemeinfreien** Film: *Night of the Living Dead* (1968).

1. **Radarr → Movies → Add New** → `Night of the Living Dead` → den Film von **1968** wählen.
2. **Root Folder:** `/data/media/movies` · **Quality Profile:** `Any` (beim Internet Archive gibt es selten „schöne“ Releases) ·
   ☑ **Start search for missing movie** → **Add Movie**.

Beobachte, was passiert:

| Wo | Was du siehst |
|----|---------------|
| Radarr → **Activity → Queue** | Der Download erscheint mit Fortschritt |
| qBittorrent | Ein neuer Torrent in der Kategorie `radarr`, geladen durch das VPN |
| Radarr → **Activity → History** | *Grabbed* → *Imported* |
| Jellyfin | Der Film taucht in der Bibliothek **Filme** auf |

### Hat der Hardlink geklappt?

> 🐧 **In der VM**

```bash
find /data -name "*Night of the Living Dead*" -type f -exec ls -li {} \;
```

```
1310845 -rw-rw-r-- 2 homelab homelab 734003200 Sep 27 11:40 /data/downloads/radarr/Night.of.the.Living.Dead.1968/…mp4
1310845 -rw-rw-r-- 2 homelab homelab 734003200 Sep 27 11:40 /data/media/movies/Night of the Living Dead (1968)/Night of the Living Dead (1968).mp4
```

**Gleiche Inode-Nummer, Link-Zähler 2**: eine Datei, zwei Namen, nur einmal Platz belegt. 🎉

Und in Jellyfin: Film anklicken, ▶️. Auch auf dem Samsung-TV.

## 6. Eine Serie

In **Sonarr → Series → Add New** funktioniert es genauso. Sonarr überwacht dann jede Staffel und holt neue Folgen
automatisch, sobald sie erscheinen. Wähle beim Hinzufügen unter **Monitor** z. B. *Future Episodes*, damit nicht gleich
alle alten Staffeln geladen werden. Die Platte ist klein!

## ✅ Checkpoint

- [ ] Radarr und Sonarr sind erreichbar und mit Passwort geschützt.
- [ ] Root Folders: `/data/media/movies` (Radarr) und `/data/media/tv` (Sonarr).
- [ ] Download-Client qBittorrent: **Test** grün, Kategorien `radarr` / `tv-sonarr`.
- [ ] Jellyfin-Verbindung: **Test** grün.
- [ ] In Radarr und Sonarr stehen die Indexer aus Prowlarr.
- [ ] Der Testfilm liegt per **Hardlink** in `/data/media/movies` und läuft in Jellyfin.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Download-Client-Test: `Unable to connect` | Host `qbittorrent`, Port `8080`? Läuft qBittorrent (`2/2`)? `FIREWALL_INPUT_PORTS=8080` im Gluetun-Container gesetzt? |
| Download-Client-Test: `Authentication failure` | Benutzer/Passwort aus Kapitel 18 prüfen |
| Import schlägt fehl: `Permission denied` | Rechte auf `/data` prüfen: `ls -ln /data/downloads /data/media` muss `1000 1000` zeigen. Sonst in der VM: `sudo chown -R 1000:1000 /data` |
| Datei wurde **kopiert** statt verlinkt (Link-Zähler 1) | Sehen alle Apps die Platte unter `/data`? Ist „Use Hardlinks“ an? Hardlinks gehen nur innerhalb von `/data` |
| Radarr: `No files found are eligible for import` | Der Download enthält vielleicht nur Extras/Samples. **Activity → Queue** → Details lesen, ggf. manuell importieren |
| Jellyfin zeigt den Film nicht | Connect-Test in Radarr grün? Sonst in Jellyfin **Bibliotheken scannen** |
| Prowlarr-Sync: `Unable to connect to Radarr` | Adresse **mit** `http://` und Port, API-Key vollständig kopiert? |

## 🎓 Was du gelernt hast

- **Root Folders** sind die Zielordner, **Kategorien** trennen die Downloads der Apps in qBittorrent.
- Die Apps verbinden sich über **Service-Namen** und **API-Keys**.
- Prowlarr **synchronisiert** Indexer automatisch in Sonarr und Radarr.
- Der Import per **Hardlink** spart Platz. Du hast es mit `ls -li` selbst überprüft.
- Mit **Qualitätsprofilen** und **Minimum Free Space** schonst du die kleine Platte.

---

⬅️ **Zurück:** [19 – Prowlarr](19-prowlarr.md) · ➡️ **Weiter:** [21 – Bazarr & Seerr](21-bazarr-seerr.md)
