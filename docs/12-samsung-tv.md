# 12 – Jellyfin auf dem Samsung-TV

> **Was du am Ende hast:** Die Jellyfin-App läuft auf deinem Samsung-TV und spielt deine Filme ab. Du weißt, wann
> der Server Videos umwandeln muss und warum.
>
> ⏱️ **Zeit:** ca. 30 Minuten
>
> 🧠 **Neue Begriffe:** [Direct Play](glossar.md#medien), [Transcoding](glossar.md#medien), [Codec](glossar.md#medien)

---

## Warum über das Heimnetz?

Samsung-TVs laufen mit **Tizen**, und dafür gibt es **keine Tailscale-App**. Das ist aber kein Problem: Der TV steht
zu Hause, und dort erreicht er Jellyfin direkt über das Heimnetz, unter der festen IP der VM und dem Port des
`LoadBalancer`-Services aus Kapitel 11:

```
Samsung-TV ──Heimnetz──► http://192.168.178.11:8096 ──► ServiceLB ──► Service jellyfin ──► Jellyfin-Pod
```

## 1. Die Jellyfin-App installieren

Seit 2026 gibt es eine **offizielle Jellyfin-App im Samsung-App-Store** für Fernseher ab Modelljahr **2021**.

1. Am TV auf **Apps** (Lupe) gehen und nach **Jellyfin** suchen.
2. **Installieren** und öffnen.

> 💡 **Die App wird nicht gefunden?** Samsung verteilt sie schrittweise nach Modell und Region. Für ältere Modelle
> (vor 2021) gibt es nur den Weg über **Sideloading** mit dem Entwickler-Modus des TVs. Anleitungen dazu findest du im
> Projekt [jellyfin-tizen](https://github.com/jellyfin/jellyfin-tizen). Das ist deutlich aufwendiger und wird hier nicht
> Schritt für Schritt behandelt.

## 2. Mit dem Server verbinden

Beim ersten Start sucht die App nach Servern. **Unser Server wird dabei nicht automatisch gefunden.** Die automatische
Suche funktioniert über einen *Broadcast* ins Heimnetz (UDP-Port 7359), und solche Rundrufe leitet Kubernetes nicht in
Pods weiter.

Deshalb trägst du die Adresse von Hand ein:

1. **Server hinzufügen** bzw. **Manuell verbinden**
2. Adresse: **`http://192.168.178.11:8096`** (deine VM-IP vom Spickzettel)
3. Mit deinem Jellyfin-Benutzer anmelden

> 💡 **Tipp: Eigener Benutzer für den TV.** Lege in Jellyfin unter **Dashboard → Benutzer** einen zweiten Benutzer
> ohne Admin-Rechte an, z. B. `wohnzimmer`, und melde dich damit am TV an. So kann niemand vom Sofa aus Einstellungen am Server ändern.

Wähle **Big Buck Bunny** und drück ▶️. 🍿

## 3. Direct Play oder Transcoding?

Das ist das wichtigste Konzept für einen flüssigen Filmabend.

| | **Direct Play** | **Transcoding** |
|--|-----------------|-----------------|
| Was passiert | Der TV bekommt die Originaldatei und spielt sie selbst ab | Der Server wandelt die Datei in Echtzeit in ein Format um, das der TV versteht |
| Last auf dem Server | fast keine | hoch (ohne Grafikkarte: CPU auf Anschlag) |
| Bildqualität | Original | leicht schlechter |

Ob umgewandelt werden muss, hängt davon ab, welche **Codecs** (Kompressionsverfahren) die Datei nutzt und welche der TV beherrscht.

### Was Samsung-TVs können (neuere Modelle)

| Bereich | ✅ Direkt abspielbar | ❌ Muss umgewandelt werden |
|---------|----------------------|----------------------------|
| Video | H.264, HEVC (H.265), VP9, meist auch AV1 | ältere/exotische Formate (z. B. MPEG-2, VC-1 teilweise) |
| Audio | AAC, AC3 (Dolby Digital), E-AC3 (Dolby Digital Plus) | **DTS** (Samsung hat die DTS-Unterstützung 2018 entfernt), **TrueHD** |
| Untertitel | SRT, eingebettete Text-Untertitel | **Bild-Untertitel (PGS/VOBSUB)** von Blu-rays werden ins Bild „eingebrannt“ |

Typischer Fall: Ein Film mit DTS-Tonspur wird abgespielt, das Video läuft direkt, **nur der Ton wird umgewandelt**.
Das schafft auch die CPU mühelos. Teuer wird es, wenn das **Video** umgewandelt werden muss, z. B. bei Bild-Untertiteln
oder 4K-HDR-Material auf einem Gerät, das HDR nicht kann.

### Nachsehen, was gerade passiert

Starte am TV einen Film und öffne am Laptop Jellyfin → **Dashboard**. Unter **Aktive Geräte** siehst du die Wiedergabe:

- **Direktwiedergabe**: alles gut, keine Last
- **Transkodierung** mit Angabe des Grundes, z. B. *„Der Audiocodec wird nicht unterstützt“* oder *„Untertitel-Codec nicht unterstützt“*

Die Last auf dem Server zeigt dir:

```bash
kubectl top pod -n media
```

```
NAME                        CPU(cores)   MEMORY(bytes)
jellyfin-5f7d8c9b6f-xk2lp   5712m        1480Mi       ← 5,7 CPU-Kerne: da wird Video umgewandelt!
```

> 💡 **Deshalb Kapitel 15 und 16:** Der Ryzen 5 schafft eine Videoumwandlung in 1080p, bei 4K-HDR geht ihm die Luft aus.
> Die RTX 2070 Super macht das mit eigenen Chips (NVENC/NVDEC) nebenbei. Mehrere Streams gleichzeitig sind dann kein Problem.

## 4. Empfohlene Einstellungen

In der Jellyfin-App am TV (Zahnrad bzw. Benutzermenü → **Einstellungen → Wiedergabe**):

| Einstellung | Wert | Warum |
|-------------|------|-------|
| Maximale Streaming-Qualität (Heimnetz) | **Auto** oder höchster Wert | Im Heimnetz ist genug Bandbreite, sonst wird unnötig umgewandelt |
| Bevorzugte Untertitel | Text-Untertitel (SRT), wenn vorhanden | vermeidet eingebrannte Untertitel |

## ✅ Checkpoint

- [ ] Die Jellyfin-App ist auf dem Samsung-TV installiert.
- [ ] Der TV ist mit `http://192.168.178.11:8096` verbunden.
- [ ] Ein Film läuft auf dem TV.
- [ ] Im Jellyfin-Dashboard hast du gesehen, ob **Direktwiedergabe** oder **Transkodierung** läuft.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| „Server nicht erreichbar“ | Ist der TV im **selben** Netz? (Nicht im Gäste-WLAN!) Funktioniert `http://192.168.178.11:8096` im Browser am Laptop? Adresse mit `http://` und `:8096` eingegeben? |
| Der Server wird nicht automatisch gefunden | Normal (siehe oben), Adresse von Hand eintragen |
| Film ruckelt oder bricht ab | Im Dashboard nachsehen, ob umgewandelt wird. `kubectl top pod -n media`: Ist die CPU am Limit? → Kapitel 15/16, oder eine Version der Datei ohne DTS/PGS verwenden |
| „Wiedergabefehler“ nur bei bestimmten Filmen | Meist ein seltener Codec. Das Jellyfin-Log zeigt den Grund: **Dashboard → Protokolle** bzw. `kubectl logs -n media deploy/jellyfin` |
| App nicht im Store | Modell älter als 2021 oder noch nicht freigeschaltet → Sideloading (siehe oben) oder Streaming-Stick (Fire TV, Google TV) mit Jellyfin-App |

## 🎓 Was du gelernt hast

- Geräte ohne Tailscale erreichen Jellyfin über den **LoadBalancer-Service** im Heimnetz.
- Die automatische Serversuche funktioniert in Kubernetes nicht, deshalb wird die Adresse von Hand eingetragen.
- **Direct Play** ist ideal. **Transcoding** entsteht, wenn der TV einen Codec nicht kann (bei Samsung oft DTS-Ton oder Bild-Untertitel).
- Das Jellyfin-Dashboard zeigt, ob und warum umgewandelt wird.

---

⬅️ **Zurück:** [11 – Jellyfin](11-jellyfin.md) · ➡️ **Weiter:** [13 – GitOps mit Argo CD](13-argocd.md)
