# 32 – Mehr Nodes

> **Was du am Ende hast:** Du weißt, wie ein zweiter Rechner (oder eine zweite VM) als **Worker** in den Cluster kommt,
> welche Stolperfallen dein bisheriges Setup dabei hat und wie der Weg zu echter Ausfallsicherheit aussieht.
>
> ⏱️ **Zeit:** ca. 30 Minuten Lesen, 1 Stunde zum Ausprobieren
>
> 🧠 **Neue Begriffe:** Worker/Agent, [Scheduling](glossar.md#container--kubernetes), `nodeSelector`, Affinity,
> [Taint & Toleration](glossar.md#container--kubernetes), Hochverfügbarkeit (HA)

---

## Wozu mehrere Nodes?

Bisher läuft alles auf einem Node, der VM `k3s`. Mehrere Nodes bringen:

| Ziel | Was es braucht |
|------|----------------|
| **Mehr Leistung**: z. B. ein alter Laptop für Immich-ML | ein zusätzlicher **Worker** |
| **Wartung ohne Ausfall**: Apps ziehen beim `drain` auf einen anderen Node um | Worker + Speicher, der auf beiden Nodes verfügbar ist |
| **Ausfallsicherheit (HA)**: Ein Rechner darf sterben | 3 Control-Plane-Nodes + replizierter Speicher |

Mit dem Wissen aus diesem Tutorial ist der erste Schritt, ein Worker, schnell gemacht.

## 1. Einen Worker hinzufügen

Als Übung reicht eine **zweite, kleine VM** in Proxmox (z. B. `k3s-worker`, 2 Kerne, 4 GB RAM, Ubuntu wie in Kapitel 04,
ohne Datenplatte, IP `192.168.178.12`). Echte Vorteile bringt natürlich erst ein zweiter Rechner.

### Den Beitritts-Token holen

> 🐧 **Auf dem bestehenden Node** (`ssh homelab@k3s`):

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

### k3s als Agent installieren

> 🐧 **Auf dem neuen Rechner** (Tailscale wie in Kapitel 05 einrichten, dann):

```bash
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.178.11:6443 K3S_TOKEN='<TOKEN>' sh -
```

`K3S_URL` sagt: *„Du bist kein eigener Cluster, sondern trittst diesem hier bei.“* Das Skript installiert k3s im
**Agent-Modus**: nur Kubelet und Container-Runtime, ohne eigene Control Plane.

> 💻 **Auf deinem Rechner:**

```bash
kubectl get nodes
```

```
NAME         STATUS   ROLES           AGE   VERSION
k3s          Ready    control-plane   40d   v1.35.3+k3s1
k3s-worker   Ready    <none>          1m    v1.35.3+k3s1
```

## 2. Die Stolperfalle: Daten kleben am Node

Jetzt wird es spannend: Der **Scheduler** (Kapitel 06) darf Pods auf beide Nodes verteilen. Aber:

| Speicher | Problem auf dem zweiten Node |
|----------|------------------------------|
| `local-path`-PVCs (Einstellungen aller Apps) | ✅ unkritisch: `local-path` merkt sich den Node (*nodeAffinity*), Pods mit solchen PVCs landen automatisch auf `k3s` |
| `hostPath`-PVs (`/data` für Medien, `/data/photos`) | ⚠️ **gefährlich**: hostPath kennt keinen Node. Ein Pod auf `k3s-worker` würde dort einen **leeren** oder fehlenden `/data`-Ordner sehen |
| GPU | ✅ unkritisch: Pods mit `nvidia.com/gpu` passen nur auf den Node mit Karte |

### Lösung: Pods an den Node binden

Der einfachste Weg ist ein **`nodeSelector`**. Er sagt: *„Dieser Pod darf nur auf Nodes mit diesem Label laufen.“*
Jeder Node hat automatisch das Label `kubernetes.io/hostname`:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: k3s    # nur auf dem Node mit der Datenplatte
```

Sauberer ist es, das PV selbst an den Node zu binden. Statt `hostPath` nimmt man dann ein **`local`-PV** mit
`nodeAffinity`. Dann wählt Kubernetes den richtigen Node automatisch für jeden Pod, der den PVC nutzt:

```yaml
# Variante für kubernetes/apps/media/basis/pv-data.yaml bei mehreren Nodes
spec:
  local:
    path: /data
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values: ["k3s"]
```

> 💡 **Übung:** Stell `media-data` und `immich-library` auf `local` + `nodeAffinity` um. Achtung: Die `spec` eines
> bestehenden PVs lässt sich nicht ändern. PV und PVC müssen neu angelegt werden, die Daten auf `/data` bleiben dank
> `Retain` aber erhalten.

### Taints: Nodes für bestimmte Pods reservieren

Das Gegenstück zum `nodeSelector` ist ein **Taint** („Makel“) am Node: *„Hier darf nur hin, wer das ausdrücklich
verträgt (**Toleration**).“* Beispiel: Ein schwacher Worker soll nur Immich-ML bekommen:

```bash
kubectl taint node k3s-worker nur-ml=true:NoSchedule
```

```yaml
# im Immich-ML-Deployment
      tolerations:
        - key: nur-ml
          operator: Equal
          value: "true"
          effect: NoSchedule
      nodeSelector:
        kubernetes.io/hostname: k3s-worker
```

| Mechanismus | Wirkung |
|-------------|---------|
| `nodeSelector` / Affinity | Pod sagt: *„Ich will dorthin.“* |
| Taint + Toleration | Node sagt: *„Nur wer mich verträgt, darf her.“* |

## 3. Der Weg zur Hochverfügbarkeit

Echte Ausfallsicherheit ist ein großes Projekt. Die Bausteine:

| Baustein | Warum | Werkzeug |
|----------|-------|----------|
| **3 Control-Plane-Nodes** | Die Cluster-Datenbank (etcd) braucht eine Mehrheit: Von 3 darf 1 ausfallen | k3s mit `--cluster-init` und eingebettetem etcd |
| **Replizierter Speicher** | Daten liegen auf mehreren Nodes, ein Ausfall kostet nichts | [Longhorn](https://longhorn.io) (von den k3s-Machern), braucht idealerweise 3 Nodes mit SSDs |
| **Mehrere Proxmox-Hosts** | eine VM kann auf einen anderen Host umziehen | Proxmox-Cluster (auch ab 3 Hosts sinnvoll) |
| **Unabhängige Stromversorgung** | Stromausfall = alles aus | USV (unterbrechungsfreie Stromversorgung) |

Für ein Heim-Setup ist ehrlich gesagt ein **einzelner, gut gesicherter Node** (Kapitel 27) oft die vernünftigere Wahl
als ein halbherziger Cluster. Wichtiger als Hochverfügbarkeit ist, dass du im Ernstfall schnell wiederherstellen kannst.

## 4. Weitere Ideen

Wenn du weitermachen willst, sind hier Themen, die auf diesem Tutorial aufbauen:

| Thema | Worum geht's |
|-------|--------------|
| **NetworkPolicies** | Firewall-Regeln zwischen Pods: „Nur Sonarr darf mit qBittorrent reden“ |
| **ResourceQuotas / LimitRanges** | Obergrenzen pro Namespace, damit keine App den Node leer frisst |
| **Talos Linux** | ein Betriebssystem nur für Kubernetes, ohne SSH und komplett per API verwaltet |
| **Gateway API** | der Nachfolger von Ingress |
| **Home Assistant** | Smart Home im Cluster (Sonderfall: `hostNetwork`, weil viele Geräte Broadcasts nutzen) |
| **Eigene Helm-Charts** | deine Manifeste als wiederverwendbares Paket |

## 🎉 Geschafft!

Du hast in 33 Kapiteln

- einen alten PC in einen **Proxmox-Hypervisor** verwandelt,
- **Kubernetes** von Pod bis Operator verstanden und selbst betrieben,
- **Jellyfin** mit GPU-Transcoding auf den Samsung-TV gebracht,
- den ***arr-Stack** sicher hinter Proton VPN aufgebaut,
- **Passwörter, Fotos und Dokumente** in eigene Hände genommen,
- alles per **GitOps** in einem Repository beschrieben, **verschlüsselt**, **überwacht**, **gesichert** und **wartbar** gemacht.

Das ist eine Menge. Viel Spaß mit deinem Homelab! 🏠

## 🎓 Was du gelernt hast

- Ein **Worker** tritt mit `K3S_URL` und Token einem bestehenden Cluster bei.
- `local-path` ist node-gebunden, `hostPath` nicht. Bei mehreren Nodes braucht man `nodeSelector` oder `local`-PVs mit `nodeAffinity`.
- **Taints/Tolerations** und **nodeSelector/Affinity** steuern, wo Pods laufen.
- Hochverfügbarkeit braucht 3 Control-Plane-Nodes und replizierten Speicher. Im Homelab ist ein gutes Backup oft wichtiger.

---

⬅️ **Zurück:** [31 – Monitoring](31-monitoring.md) · 🏠 **Zum Anfang:** [00 – Einführung](00-einfuehrung.md)
