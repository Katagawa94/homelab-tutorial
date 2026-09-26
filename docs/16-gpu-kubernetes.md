# 16 – GPU in Kubernetes

> **Was du am Ende hast:** Kubernetes kennt die Grafikkarte als Ressource `nvidia.com/gpu`, und Jellyfin wandelt
> Videos mit NVENC/NVDEC auf der RTX 2070 Super um statt auf der CPU.
>
> ⏱️ **Zeit:** ca. 1 Stunde
>
> 🧠 **Neue Begriffe:** [Container Toolkit](glossar.md#container--kubernetes), [RuntimeClass](glossar.md#container--kubernetes),
> [Device Plugin](glossar.md#container--kubernetes), [DaemonSet](glossar.md#container--kubernetes),
> Node-Label, Extended Resource, Kustomize-Patch

---

> 📸 **Snapshot-Routine:** Snapshot der VM anlegen (bei ausgeschalteter VM, siehe Kapitel 15).

## Was fehlt noch?

Nach Kapitel 15 sieht die **VM** die Grafikkarte. Ein **Container** sieht sie aber noch nicht, und **Kubernetes** weiß
nichts von ihr. Drei Bausteine schließen die Lücke:

| Baustein | Aufgabe | Wo |
|----------|---------|-----|
| **NVIDIA Container Toolkit** | bringt Treiber und GPU-Gerätedateien in Container | VM (per `apt`) |
| **RuntimeClass `nvidia`** | Pods können sagen: „Starte mich mit der NVIDIA-Runtime“ | legt k3s automatisch an |
| **NVIDIA Device Plugin** | meldet Kubernetes: „Dieser Node hat 1 × `nvidia.com/gpu`“ | Cluster (Argo CD) |

```
 Pod jellyfin
   runtimeClassName: nvidia ─────────► containerd startet den Container mit der NVIDIA-Runtime
   limits: nvidia.com/gpu: 1 ────────► Scheduler: "Node k3s hat noch 1 GPU frei" (vom Device Plugin gemeldet)
```

## 1. NVIDIA Container Toolkit

> 🐧 **In der VM** (`ssh homelab@k3s`)

Paketquelle von NVIDIA hinzufügen und das Toolkit installieren (so steht es in der NVIDIA-Dokumentation):

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update
sudo apt install -y nvidia-container-toolkit
```

k3s erkennt das Toolkit beim Start automatisch. Also neu starten:

```bash
sudo systemctl restart k3s
```

Prüfen, ob k3s die NVIDIA-Runtime eingetragen hat:

```bash
sudo grep -i nvidia /var/lib/rancher/k3s/agent/etc/containerd/config.toml
```

```
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.'nvidia']
  BinaryName = "/usr/bin/nvidia-container-runtime"
...
```

> 💻 **Auf deinem Rechner:**

```bash
kubectl get runtimeclass
```

```
NAME                  HANDLER               AGE
crun                  crun                  5d
nvidia                nvidia                5d
nvidia-experimental   nvidia-experimental   5d
...
```

Eine **RuntimeClass** ist ein Name für eine Art, Container zu starten. Standard ist `runc`. Pods mit
`runtimeClassName: nvidia` werden stattdessen mit der NVIDIA-Runtime gestartet, und die gibt ihnen Zugriff auf die GPU.

## 2. Node-Label setzen

Das Device Plugin soll nur auf Nodes laufen, die wirklich eine NVIDIA-Karte haben. Es erkennt sie an einem **Label**
am Node, genau wie ein Service seine Pods an Labels erkennt:

```bash
kubectl label node k3s nvidia.com/gpu.present=true
kubectl get node k3s --show-labels | tr ',' '\n' | grep nvidia
```

```
nvidia.com/gpu.present=true
```

> 💡 Node-Labels sind Eigenschaften der Maschine, nicht einer App. Deshalb setzen wir sie ausnahmsweise per `kubectl`
> und nicht über Git. Bei einem Neuaufbau musst du diesen Befehl wiederholen. Er steht auch im Troubleshooting-Kapitel.

## 3. Device Plugin aktivieren

Die Einstellungen in [`kubernetes/infrastructure/nvidia-device-plugin/values.yaml`](../kubernetes/infrastructure/nvidia-device-plugin/values.yaml):

```yaml
# Das Plugin selbst muss mit der NVIDIA-Runtime laufen, um die GPU zu sehen.
runtimeClassName: nvidia
```

Wie gewohnt per Git:

```bash
cp kubernetes/katalog/nvidia-device-plugin.yaml kubernetes/aktiv/
git add kubernetes/aktiv/nvidia-device-plugin.yaml
git commit -m "NVIDIA Device Plugin aktivieren"
git push
```

Nach dem Sync:

```bash
kubectl get daemonset,pods -n nvidia-device-plugin
```

```
NAME                                  DESIRED   CURRENT   READY   ...   NODE SELECTOR   AGE
daemonset.apps/nvidia-device-plugin   1         1         1       ...   <none>          1m

NAME                             READY   STATUS    RESTARTS   AGE
pod/nvidia-device-plugin-x7k2p   1/1     Running   0          1m
```

Ein **DaemonSet** ist wie ein Deployment, nur mit einer anderen Regel: *„Genau ein Pod auf jedem passenden Node.“*
Das ist ideal für Treiber und Agenten, die auf jeder Maschine laufen müssen.

Der Beweis, dass Kubernetes die GPU jetzt kennt:

```bash
kubectl describe node k3s | grep -i "nvidia.com/gpu"
```

```
  nvidia.com/gpu:     1       ← Capacity: vorhanden
  nvidia.com/gpu:     1       ← Allocatable: verteilbar
  nvidia.com/gpu     0           0         ← Allocated: noch von niemandem belegt
```

`nvidia.com/gpu` ist eine **Extended Resource**: eine Ressource wie `cpu` und `memory`, nur von einem Plugin gemeldet.

## 4. Test-Pod

Bevor Jellyfin die GPU bekommt, ein schneller Test mit
[`examples/16-gpu/gpu-test.yaml`](../examples/16-gpu/gpu-test.yaml):

```yaml
spec:
  restartPolicy: Never            # nur einmal ausführen
  runtimeClassName: nvidia
  containers:
    - name: test
      image: ubuntu:24.04
      command: ["nvidia-smi"]     # wird von der NVIDIA-Runtime in den Container gebracht
      resources:
        limits:
          nvidia.com/gpu: 1
```

```bash
kubectl apply -f examples/16-gpu/gpu-test.yaml
kubectl get pod gpu-test -w       # warten bis "Completed", dann Strg+C
kubectl logs gpu-test
```

Du siehst dieselbe `nvidia-smi`-Tabelle wie in Kapitel 15, diesmal aus einem **ganz normalen Ubuntu-Container**. 🎉

Wichtig, aufräumen! Solange der Pod existiert, gilt die GPU als belegt:

```bash
kubectl delete -f examples/16-gpu/gpu-test.yaml
```

## 5. Jellyfin bekommt die GPU

Das Jellyfin-Deployment soll ergänzt werden, **ohne** die Originaldatei umzuschreiben. Dafür gibt es in Kustomize
**Patches**. Die Ergänzung liegt fertig in
[`kubernetes/apps/media/jellyfin/gpu-patch.yaml`](../kubernetes/apps/media/jellyfin/gpu-patch.yaml):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jellyfin
spec:
  template:
    spec:
      runtimeClassName: nvidia    # Container mit der NVIDIA-Runtime starten
      containers:
        - name: jellyfin
          env:
            - name: NVIDIA_DRIVER_CAPABILITIES
              value: compute,video,utility   # "video" = NVENC/NVDEC
          resources:
            limits:
              nvidia.com/gpu: 1   # eine GPU anfordern (vom Device Plugin bereitgestellt)
```

Ein Patch sieht aus wie ein unvollständiges Manifest: Er enthält nur, was **dazukommt**. Kustomize legt ihn über das
Original. Die Umgebungsvariable `TZ` und das RAM-Limit bleiben erhalten, die neuen Felder kommen hinzu.

Öffne [`kubernetes/apps/media/jellyfin/kustomization.yaml`](../kubernetes/apps/media/jellyfin/kustomization.yaml) und
entferne die `#` vor den letzten beiden Zeilen:

```yaml
# Kapitel 16: Die beiden Zeilen unten einkommentieren (die "#" entfernen),
# damit Jellyfin die NVIDIA-GPU zum Transcoding nutzt.
patches:
  - path: gpu-patch.yaml
```

Vorher prüfen, was herauskommt:

```bash
kubectl kustomize kubernetes/apps/media/jellyfin | grep -B2 -A2 nvidia
```

Und ausrollen:

```bash
git commit -am "Jellyfin: NVIDIA-GPU für Transcoding"
git push
```

Nach dem Sync startet Jellyfin neu. Prüfen, ob der Container die GPU sieht:

```bash
kubectl exec -n media deploy/jellyfin -- nvidia-smi -L
```

```
GPU 0: NVIDIA GeForce RTX 2070 SUPER (UUID: GPU-3f2a9c1e-…)
```

## 6. Hardware-Transcoding in Jellyfin einschalten

Jellyfin → **Dashboard → Wiedergabe → Transkodierung**:

| Einstellung | Wert |
|-------------|------|
| Hardwarebeschleunigung | **Nvidia NVENC** |
| Hardware-Dekodierung aktivieren für | ☑ H264 · ☑ HEVC · ☑ MPEG2 · ☑ VC1 · ☑ VP8 · ☑ VP9 · ☑ HEVC 10bit · ☑ VP9 10bit · ☐ **AV1** (kann die RTX 2070 nicht) |
| Hardware-Kodierung aktivieren | ☑ |
| Kodierung im HEVC-Format erlauben | ☑ (die RTX 2070 kann HEVC gut) |
| Tone-Mapping aktivieren | ☑ (wandelt HDR in SDR um, wenn das Gerät kein HDR kann) |

**Speichern** (ganz unten).

## 7. Der Test

Erzwinge eine Umwandlung: Spiel **Big Buck Bunny** im Browser ab, klick im Player auf das **Zahnrad → Qualität** und
wähle **720p – 2 Mbit/s**. Jetzt muss der Server umrechnen.

**Im Jellyfin-Dashboard** steht bei der Wiedergabe *Transkodierung*, und in den Details taucht `(HW)` auf.

> 🐧 **In der VM:**

```bash
nvidia-smi
```

Unten unter **Processes** erscheint jetzt Jellyfins FFmpeg:

```
| Processes:                                                                              |
|  GPU   GI   CI        PID   Type   Process name                              GPU Memory |
|=========================================================================================|
|    0   N/A  N/A     48213      C   /usr/lib/jellyfin-ffmpeg/ffmpeg              312MiB  |
```

Live-Auslastung von Encoder und Decoder:

```bash
nvidia-smi dmon -s u
```

```
# gpu     sm    mem    enc    dec    jpg    ofa
# Idx      %      %      %      %      %      %
    0      3      1     11      7      0      0
```

Die Spalten `enc` und `dec` arbeiten, und `kubectl top pod -n media` zeigt, dass die CPU fast nichts mehr tut.
Vergleiche das mit Kapitel 12! 🚀

Für den Samsung-TV bedeutet das: Filme mit DTS-Ton, Bild-Untertiteln oder 4K-HDR laufen jetzt flüssig, auch mehrere gleichzeitig.

## ✅ Checkpoint

- [ ] `kubectl get runtimeclass` zeigt `nvidia`.
- [ ] `kubectl describe node k3s` zeigt `nvidia.com/gpu: 1` unter Capacity und Allocatable.
- [ ] Der Test-Pod hat `nvidia-smi` ausgegeben und ist wieder gelöscht.
- [ ] `kubectl exec -n media deploy/jellyfin -- nvidia-smi -L` zeigt die RTX 2070 SUPER.
- [ ] Beim Transkodieren taucht FFmpeg in `nvidia-smi` auf.
- [ ] Argo CD zeigt alle Apps als **Synced** und **Healthy**.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Pod `Pending`: `Insufficient nvidia.com/gpu` | Die GPU ist schon vergeben (Test-Pod noch da?) oder das Device Plugin läuft nicht → `kubectl get pods -A \| grep -e gpu -e nvidia` |
| Device-Plugin-DaemonSet hat `DESIRED 0` | Node-Label fehlt → Schritt 2 |
| Device Plugin: `could not load NVML library` | Toolkit nicht installiert oder k3s nicht neu gestartet (Schritt 1), oder `runtimeClassName: nvidia` fehlt in den Values |
| `kubectl get runtimeclass` zeigt kein `nvidia` | `sudo systemctl restart k3s` nach der Toolkit-Installation vergessen |
| Jellyfin: Wiedergabe bricht mit HW-Beschleunigung ab | **Dashboard → Protokolle** → neuestes `FFmpeg.Transcode-…`-Log lesen. Treiber mindestens 570 (Kapitel 15)? Testweise einzelne Decoder (z. B. HEVC 10bit) abschalten |
| `nvidia-smi` im Jellyfin-Container: `executable file not found` | `NVIDIA_DRIVER_CAPABILITIES` enthält kein `utility` → Patch prüfen |

## 🎓 Was du gelernt hast

- Das **NVIDIA Container Toolkit** bringt die GPU in Container. k3s bindet es automatisch ein und legt die **RuntimeClass** `nvidia` an.
- Ein **Device Plugin** meldet Hardware als **Extended Resource** (`nvidia.com/gpu`). Pods fordern sie über `limits` an.
- Ein **DaemonSet** startet einen Pod auf jedem passenden Node. **Node-Labels** steuern, welche Nodes passen.
- **Kustomize-Patches** ergänzen Manifeste, ohne die Originaldatei umzuschreiben.
- NVENC/NVDEC nehmen der CPU die Videoumwandlung komplett ab.

---

## 🎉 Teil C geschafft!

Dein Homelab ist jetzt **produktiv**:

- Jellyfin mit GPU-Transcoding, auf dem Samsung-TV und von überall per Tailscale
- Alles in Git: Apps, Einstellungen und verschlüsselte Zugangsdaten
- Argo CD hält den Cluster automatisch auf dem Stand des Repositories

In **Teil D** kommt der *arr-Stack dazu, mit qBittorrent hinter Proton VPN.

---

⬅️ **Zurück:** [15 – GPU an die VM durchreichen](15-gpu-passthrough.md) · ➡️ **Weiter:** [17 – Wie der *arr-Stack zusammenspielt](17-arr-ueberblick.md)
