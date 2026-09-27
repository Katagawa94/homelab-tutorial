# 29 – Troubleshooting-Handbuch

> **Was du am Ende hast:** Ein Nachschlagewerk für den Fall, dass etwas nicht funktioniert: eine feste
> Vorgehensweise, die wichtigsten Befehle und die häufigsten Fehler mit Lösungen.
>
> ⏱️ **Zeit:** ca. 20 Minuten Lesen, danach zum Nachschlagen

---

## Die Vorgehensweise: von außen nach innen

Wenn „Jellyfin geht nicht“, dann arbeite diese Kette von oben nach unten ab. Der erste Punkt, der nicht stimmt, ist dein Problem:

```
 1. Gerät       Ist Tailscale an? Andere Dienste erreichbar?           → tailscale status
 2. Argo CD     Ist die App Synced & Healthy?                           → Argo-CD-Oberfläche
 3. Pod         Läuft er? READY 1/1?                                    → kubectl get pods -n <ns>
 4. Events      Warum nicht?                                             → kubectl describe pod …
 5. Logs        Was sagt die App selbst?                                 → kubectl logs …
 6. Service     Zeigt er auf den Pod?                                    → kubectl get endpointslices -n <ns>
 7. Node / VM   Genug RAM, Platte, läuft k3s?                            → kubectl describe node k3s, df -h
 8. Proxmox     Läuft die VM? Ist local-lvm voll?                        → Proxmox-Oberfläche
```

## Befehle zum Nachschlagen

| Frage | Befehl |
|-------|--------|
| Was läuft nicht? | `kubectl get pods -A \| grep -v -e Running -e Completed` |
| Warum startet der Pod nicht? | `kubectl describe pod <pod> -n <ns>` → ganz unten **Events** |
| Was sagt die App? | `kubectl logs <pod> -n <ns>` · vorheriger Absturz: `--previous` · live: `-f` |
| Welcher Container? (mehrere im Pod) | `kubectl logs <pod> -n <ns> -c <container>` |
| Alle Ereignisse im Namespace | `kubectl get events -n <ns> --sort-by=.lastTimestamp` |
| Wie voll ist der Node? | `kubectl top node` · `kubectl describe node k3s` → **Conditions** und **Allocated resources** |
| Wer braucht wie viel? | `kubectl top pods -A --sort-by=memory` |
| Hat der Service Ziele? | `kubectl get endpointslices -n <ns>` |
| Im Container nachsehen | `kubectl exec -it <pod> -n <ns> -- sh` |
| App neu starten | `kubectl rollout restart deployment/<name> -n <ns>` |
| Logs mehrerer Pods | `stern -n media .` (aus der `flake.nix`) |
| Alles auf einen Blick | `k9s` |

## Pod-Status und was sie bedeuten

| Status | Bedeutung | Typische Ursache | Lösung |
|--------|-----------|------------------|--------|
| `Pending` | kein Platz zum Starten gefunden | zu wenig RAM/CPU, PVC nicht gebunden, GPU schon vergeben, Node `cordon`ed | `describe pod` → Events: `Insufficient memory`, `unbound PersistentVolumeClaims`, `Insufficient nvidia.com/gpu` |
| `ContainerCreating` (lange) | Image wird geladen oder Volume eingebunden | großes Image, langsames Internet, hostPath fehlt | `describe pod`: `Pulling image …` abwarten, bei `MountVolume.SetUp failed` den Pfad prüfen |
| `Init:0/1` | Init-Container (z. B. Gluetun) noch nicht fertig | VPN baut nicht auf | Logs des Init-Containers: `-c gluetun` |
| `ErrImagePull` / `ImagePullBackOff` | Image nicht ladbar | Tippfehler im Namen oder Tag, Registry nicht erreichbar | Image-Namen prüfen, in der VM: `sudo k3s crictl pull <image>` |
| `CreateContainerConfigError` | Konfiguration unvollständig | Secret oder ConfigMap fehlt | `describe pod` → `secret "…" not found`. SealedSecret vorhanden? App `secrets` synchron? |
| `CrashLoopBackOff` | Container startet und stürzt immer wieder ab | Fehler in der App-Konfiguration, Rechte, Datenbank nicht erreichbar | `kubectl logs --previous`. Die letzte Zeile vor dem Absturz ist der Schlüssel |
| `OOMKilled` | RAM-Limit überschritten | Limit zu niedrig | `limits.memory` im Manifest erhöhen, pushen |
| `Running`, aber `0/1` | Container läuft, aber die readinessProbe schlägt fehl | App fährt noch hoch oder hängt | `describe pod` → `Readiness probe failed` · Logs |
| `Evicted` | vom Node verdrängt | Platte oder RAM des Nodes voll | siehe „Platte voll“ unten, dann `kubectl delete pod --field-selector=status.phase=Failed -A` |
| `Terminating` (ewig) | kann nicht beendet werden | hängender Volume-Mount, Finalizer | ein paar Minuten warten, dann `kubectl delete pod <pod> -n <ns> --grace-period=0 --force` |

## Argo-CD-Zustände

| Zustand | Bedeutung | Vorgehen |
|---------|-----------|----------|
| **OutOfSync** | Git und Cluster unterscheiden sich | **App Diff** ansehen. Sync läuft automatisch, sonst **Sync** klicken |
| **Degraded** | eine Ressource ist ungesund | rote Kachel anklicken → Events/Logs |
| **Progressing** (lange) | Rollout hängt | meist ein Pod, der nicht bereit wird → siehe oben |
| **Missing** | Objekt fehlt im Cluster | Sync. Bei Fehlern steht der Grund unter **Sync Status** |
| **ComparisonError** | Argo CD kann Git nicht lesen oder rendern | Repository-Zugang (Token abgelaufen?), YAML-Fehler → `scripts/validate.sh` lokal |
| **Unknown** | Argo CD hat keinen Kontakt | `kubectl get pods -n argocd` |

## Die häufigsten Homelab-Probleme

### Platte voll

**Symptome:** Pods werden `Evicted`, Node-Condition `DiskPressure`, Apps können nicht schreiben.

> 🐧 **In der VM:**

```bash
df -h / /data
sudo du -xh --max-depth=1 /var/lib/rancher/k3s | sort -h | tail
```

| Voll ist … | Lösung |
|------------|--------|
| `/` (Systemplatte, 60 GB) | ungenutzte Images löschen: `sudo k3s crictl rmi --prune`. Große PVCs finden: `sudo du -sh /var/lib/rancher/k3s/storage/*`. Langfristig: Kapitel 30 |
| `/data` (Datenplatte) | alte Downloads in qBittorrent samt Dateien entfernen, Filme aussortieren. Qualitätsprofile (Kapitel 20) prüfen |
| `local-lvm` in Proxmox | **alte Snapshots löschen!** Ist das Thin-Pool voll, bleiben *alle* VMs stehen |

### Rechteprobleme auf `/data`

**Symptome:** `Permission denied` in Sonarr/Radarr/qBittorrent, Import schlägt fehl.

```bash
ls -ln /data /data/media /data/downloads
```

Alles muss `1000 1000` gehören. Reparatur in der VM: `sudo chown -R 1000:1000 /data/media /data/downloads`.
Außerdem prüfen: `PUID`/`PGID` in der ConfigMap `media-env` = `1000`.

### GPU weg (nach Neustart oder Treiber-Update)

| Prüfung | Befehl | Wenn nicht OK |
|---------|--------|---------------|
| Proxmox gibt die Karte ab | 🟧 `lspci -nnk -s 0a:00` → `vfio-pci` | Kapitel 15, Teil 1 |
| VM sieht die Karte | 🐧 `nvidia-smi` | Treiber neu installieren, Neustart (Kapitel 15, Teil 3) |
| k3s kennt die Runtime | `kubectl get runtimeclass nvidia` | `sudo systemctl restart k3s` |
| Node-Label gesetzt | `kubectl get node k3s --show-labels \| grep gpu.present` | `kubectl label node k3s nvidia.com/gpu.present=true` |
| Kubernetes sieht die GPU | `kubectl describe node k3s \| grep nvidia.com/gpu` | Device-Plugin-Pods prüfen (Kapitel 16) |

### Tailscale-Adresse geht nicht

- Andere Geräte im Tailnet erreichbar? Dann liegt es an der App, nicht an Tailscale.
- `kubectl get ingress -A`: Hat der Ingress eine `ADDRESS`?
- Proxy-Pod im Namespace `tailscale` läuft? `kubectl get pods -n tailscale`
- Operator-Logs: `kubectl logs -n tailscale deploy/operator`
- In der Admin-Konsole: Steht das Gerät auf *Offline*? Gibt es Duplikate (`jellyfin-1`)?

### Nach dem Neuaufbau der VM

Was **nicht** in Git steht und von Hand wiederholt werden muss:

1. Sealed-Secrets-Schlüssel einspielen, **bevor** der Controller startet (Kapitel 14)
2. `kubectl label node k3s nvidia.com/gpu.present=true` (Kapitel 16)
3. `/data`-Ordner und Rechte (Kapitel 04), `/data/photos` (Kapitel 24)
4. Argo CD per Helm installieren, Repository-Secret, `root.yaml` (Kapitel 13). Alles andere kommt dann von selbst.

### Uhrzeit falsch

Zertifikate und Logins schlagen fehl, wenn die Uhr stark abweicht. In der VM: `timedatectl`. Es muss
`System clock synchronized: yes` dastehen.

## Hilfe suchen

Wenn du nicht weiterkommst:

1. Fehlermeldung **wörtlich** (in Englisch) suchen, meist hatte jemand anders das Problem schon.
2. Dokumentation der App lesen (Links in den Kapiteln).
3. Communities: r/homelab, r/selfhosted, r/kubernetes, die Discord-/Matrix-Server der Apps (Jellyfin, *arr, Immich).

Für eine gute Frage gehören dazu: Was wolltest du tun? Was ist passiert (Befehl + **vollständige** Fehlermeldung)?
Ausgabe von `kubectl describe pod` und `kubectl logs`. **Vorher Passwörter und Schlüssel aus der Ausgabe entfernen!**

## 🎓 Was du gelernt hast

- Fehlersuche immer **von außen nach innen**: Gerät → Argo CD → Pod → Events → Logs → Service → Node → Proxmox.
- `describe` (Events) und `logs` (`--previous`!) lösen die meisten Rätsel.
- Die meisten Homelab-Probleme sind Platzmangel, Rechte, fehlende Secrets oder Tippfehler.

---

⬅️ **Zurück:** [28 – Updates & Wartung](28-updates-wartung.md) · ➡️ **Weiter:** [30 – SSD nachrüsten](30-ssd-nachruesten.md)
