# 19 – Prowlarr

> **Was du am Ende hast:** Prowlarr läuft und kennt deine Suchquellen (Indexer). In Kapitel 20 verteilt es sie
> automatisch an Sonarr und Radarr.
>
> ⏱️ **Zeit:** ca. 20 Minuten
>
> 🧠 **Neue Begriffe:** [Indexer](glossar.md#medien), API-Key, Cluster-DNS

---

## Was macht Prowlarr?

Sonarr und Radarr müssen wissen, **wo** sie suchen sollen. Diese Suchquellen heißen **Indexer**. Ohne Prowlarr müsstest du
jeden Indexer in Sonarr **und** in Radarr einzeln eintragen. Mit Prowlarr trägst du ihn **einmal** ein, und Prowlarr
verteilt ihn an alle anderen Apps:

```
                 ┌──────────┐
 Indexer A ───►  │          │ ───► Sonarr
 Indexer B ───►  │ Prowlarr │
 Indexer C ───►  │          │ ───► Radarr
                 └──────────┘
```

## 1. Aktivieren

Die Manifeste in [`kubernetes/apps/media/prowlarr/`](../kubernetes/apps/media/prowlarr/) folgen dem Muster aus Kapitel 17.
Prowlarr braucht als einzige der *arr-Apps **kein** `/data`, denn es verwaltet nur Suchquellen, keine Dateien.

```bash
cp kubernetes/katalog/prowlarr.yaml kubernetes/aktiv/
git add kubernetes/aktiv/prowlarr.yaml
git commit -m "Prowlarr aktivieren"
git push
```

```bash
kubectl get pods -n media -l app=prowlarr
```

```
NAME                        READY   STATUS    RESTARTS   AGE
prowlarr-7b9c8d6f5d-q2m4x   1/1     Running   0          1m
```

## 2. Erster Start

Öffne <https://prowlarr.tail1a2b3c.ts.net>.

Beim ersten Aufruf verlangt Prowlarr eine **Authentifizierung**:

| Feld | Wert |
|------|------|
| Authentication Method | **Forms (Login Page)** |
| Authentication Required | **Enabled** |
| Username / Password | eigene Werte → Passwortmanager |

> 💡 Die Oberflächen von Prowlarr, Sonarr und Radarr lassen sich unter **Settings → UI → UI Language** auf Deutsch
> umstellen. Das Tutorial nennt die englischen Begriffe, weil die meisten Anleitungen im Netz sie verwenden.

## 3. Einen Indexer hinzufügen

**Indexers → Add Indexer**. Prowlarr kennt Hunderte Indexer. Filtere nach **Privacy: Public** und **Language**.

Für einen legalen Test eignet sich **Internet Archive**. Das Internet Archive stellt gemeinfreie Filme, alte
Fernsehsendungen und freie Musik bereit:

1. Suche nach `Internet Archive` und klicke darauf.
2. Einstellungen übernehmen → **Test** → **Save**.

> 💡 **Wo kommen weitere Indexer her?** Öffentliche Indexer lassen sich mit einem Klick hinzufügen. Private Tracker
> (Einladung nötig) funktionieren genauso, brauchen aber Zugangsdaten. Achte bei jedem Indexer darauf, dass du die
> Inhalte legal laden darfst.

### Test

Oben **Search** → Suchbegriff `Night of the Living Dead` → **Search**. In der Ergebnisliste erscheint unter anderem der
gemeinfreie Horrorklassiker von 1968. Prowlarr funktioniert. 🎉

## 4. Wie reden die Apps miteinander?

Gleich verbinden wir Prowlarr mit Sonarr und Radarr, dann Radarr mit qBittorrent und Jellyfin. Die Adressen sind dabei
immer **Service-Namen** aus Kapitel 07:

| Von | Nach | Adresse |
|-----|------|---------|
| Prowlarr | Sonarr | `http://sonarr:8989` |
| Prowlarr | Radarr | `http://radarr:7878` |
| Sonarr/Radarr | Prowlarr | `http://prowlarr:9696` |
| Sonarr/Radarr | qBittorrent | `http://qbittorrent:8080` |
| Sonarr/Radarr | Jellyfin | `http://jellyfin:8096` |

Kurze Namen wie `sonarr` funktionieren, weil alle Apps im **selben Namespace** `media` liegen. Wie das Cluster-DNS
die Namen auflöst, kannst du direkt ausprobieren:

```bash
kubectl exec -n media deploy/prowlarr -- getent hosts qbittorrent
```

```
10.43.156.21    qbittorrent.media.svc.cluster.local
```

Neben der Adresse braucht jede App einen **API-Key**: einen langen Zufallsschlüssel, mit dem sich die Apps gegenseitig
ausweisen. Du findest ihn in jeder App unter **Settings → General → API Key**.

> 💡 Die Tailscale-Adressen (`https://sonarr.<tailnet>.ts.net`) sind für **dich**. Die Apps untereinander benutzen die
> Service-Namen, denn das ist schneller und funktioniert auch, wenn Tailscale einmal hakt.

## ✅ Checkpoint

- [ ] Prowlarr ist über `https://prowlarr.<tailnet>.ts.net` erreichbar und mit Passwort geschützt.
- [ ] Der Indexer **Internet Archive** ist eingetragen und der **Test** war grün.
- [ ] Eine Suche liefert Ergebnisse.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Indexer-Test schlägt fehl | Manche Indexer blockieren Anfragen zeitweise. Später erneut testen oder einen anderen Indexer wählen |
| Einige Indexer brauchen „FlareSolverr“ | Das ist ein Zusatzdienst gegen Bot-Schutz. Für den Anfang: diese Indexer einfach auslassen |
| Seite lädt nicht | `kubectl get pods,ingress -n media -l app=prowlarr` und die Logs: `kubectl logs -n media deploy/prowlarr` |

## 🎓 Was du gelernt hast

- **Indexer** sind Suchquellen. Prowlarr verwaltet sie zentral für alle *arr-Apps.
- Apps im selben Namespace erreichen sich über den **Service-Namen**, das Cluster-DNS übersetzt ihn in eine IP.
- **API-Keys** sind die Ausweise, mit denen sich die Apps gegenseitig vertrauen.

---

⬅️ **Zurück:** [18 – qBittorrent + Proton VPN](18-qbittorrent-vpn.md) · ➡️ **Weiter:** [20 – Sonarr & Radarr](20-sonarr-radarr.md)
