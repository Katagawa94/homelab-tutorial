# 31 – Monitoring mit Prometheus & Grafana

> **Was du am Ende hast:** Prometheus sammelt laufend Messwerte aus dem Cluster, und Grafana zeigt sie als Dashboards:
> CPU, RAM, Platte und Netzwerk für Node, Namespaces und jeden einzelnen Pod, rückblickend für die letzten 7 Tage.
>
> ⏱️ **Zeit:** ca. 45 Minuten
>
> 🧠 **Neue Begriffe:** [Prometheus](glossar.md#container--kubernetes), [Grafana](glossar.md#container--kubernetes),
> Metrik, ServiceMonitor, Exporter

---

> 📸 **Snapshot-Routine:** Snapshot der VM anlegen (bei ausgeschalteter VM).

## Uptime Kuma reicht nicht?

Uptime Kuma (Kapitel 26) beantwortet: **„Läuft es?“** Prometheus und Grafana beantworten: **„Wie geht es ihm, und wie
war es gestern Abend?“** Zum Beispiel:

- Warum hat Jellyfin gestern um 21 Uhr geruckelt? (CPU am Limit? RAM?)
- Welche App frisst seit dem letzten Update doppelt so viel RAM?
- Wann ist die Systemplatte voll, wenn es so weitergeht?

## Wie es funktioniert

```
 node-exporter (DaemonSet)  ─┐   Messwerte zum Abholen (/metrics)
 kube-state-metrics         ─┼──────────────────────► Prometheus ──► Grafana (Dashboards)
 kubelet / cAdvisor (k3s)   ─┘   "Scrape" alle 30 s     speichert      https://grafana.<tailnet>.ts.net
                                                         7 Tage
```

| Baustein | Aufgabe |
|----------|---------|
| **Prometheus** | fragt regelmäßig alle **Exporter** ab (*scrapen*) und speichert die Werte als Zeitreihen |
| **node-exporter** | Messwerte der Maschine: CPU, RAM, Platten, Netzwerk. Ein **DaemonSet**, also ein Pod pro Node |
| **kube-state-metrics** | Zustand der Kubernetes-Objekte: Wie viele Pods laufen? Welche starten neu? |
| **kubelet/cAdvisor** | Verbrauch jedes einzelnen Containers (in k3s eingebaut) |
| **Grafana** | macht aus den Zahlen Diagramme |
| **ServiceMonitor** | eine CRD des Prometheus-Operators: „Diesen Service bitte abfragen“ |

All das bringt das Helm-Chart **kube-prometheus-stack** fertig vorkonfiguriert mit, inklusive Dutzender Dashboards.

## 1. Platz prüfen

Prometheus speichert bis zu 8 GB Messwerte auf der Systemplatte. Prüfe vorher:

```bash
ssh homelab@k3s df -h /
```

Unter 15 GB frei? Dann erst aufräumen (Kapitel 29, „Platte voll“) oder Kapitel 30 (SSD) vorziehen.

## 2. Die Einstellungen

[`kubernetes/infrastructure/monitoring/values.yaml`](../kubernetes/infrastructure/monitoring/values.yaml), die wichtigsten Teile:

```yaml
# k3s bündelt diese Kubernetes-Bausteine in einem einzigen Prozess. Sie lassen sich
# nicht einzeln abfragen, Prometheus würde sonst dauerhaft Fehler melden.
kubeEtcd:
  enabled: false
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false

# Alarme schickt uns bereits Uptime Kuma (Kapitel 26), das spart RAM.
alertmanager:
  enabled: false

prometheus:
  prometheusSpec:
    retention: 7d                 # Messwerte 7 Tage aufheben …
    retentionSize: 8GB            # … aber höchstens 8 GB
    storageSpec:
      volumeClaimTemplate:        # Prometheus läuft als StatefulSet (Kapitel 24)
        ...

grafana:
  admin:
    existingSecret: grafana-admin # Kapitel 31: SealedSecret in kubernetes/secrets/monitoring/
```

Für einen großen Cluster wären das zu wenig Aufbewahrung und zu wenig Ressourcen. Für ein Homelab ist es genau richtig.

## 3. Grafana-Passwort versiegeln

```bash
mkdir -p kubernetes/secrets/monitoring
kubectl create secret generic grafana-admin -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<GRAFANA-PASSWORT>' \
  --dry-run=client -o yaml \
| kubeseal --format yaml > kubernetes/secrets/monitoring/grafana-admin.yaml
```

## 4. Aktivieren

```bash
cp kubernetes/katalog/monitoring.yaml kubernetes/aktiv/
git add kubernetes/aktiv/monitoring.yaml kubernetes/secrets/monitoring/
git commit -m "Monitoring: Prometheus und Grafana"
git push
```

Das Chart ist groß, der erste Sync dauert ein paar Minuten:

```bash
kubectl get pods -n monitoring
```

```
NAME                                                   READY   STATUS    RESTARTS   AGE
monitoring-grafana-6d9f8b7c5d-k2x9m                    3/3     Running   0          3m
monitoring-kube-prometheus-operator-7c8d9f6b5d-q2m4x   1/1     Running   0          3m
monitoring-kube-state-metrics-5b7d9c8f6-9mzq7          1/1     Running   0          3m
monitoring-prometheus-node-exporter-x7k2p              1/1     Running   0          3m
prometheus-monitoring-kube-prometheus-prometheus-0     2/2     Running   0          2m
```

Erkennst du die Muster? `node-exporter` mit Zufallsendung ohne ReplicaSet-Teil: ein **DaemonSet**. `prometheus-…-0`:
ein **StatefulSet**. Grafana hat `3/3` Container: die App und zwei **Sidecars**, die Dashboards aus ConfigMaps nachladen.

## 5. Grafana erkunden

Öffne <https://grafana.tail1a2b3c.ts.net> und melde dich mit `admin` und deinem Passwort an.

**Dashboards → Browse**, empfehlenswerte Einstiege:

| Dashboard | Zeigt |
|-----------|-------|
| **Node Exporter / Nodes** | die VM: CPU, RAM, Platten, Netzwerk |
| **Kubernetes / Compute Resources / Cluster** | Verbrauch pro Namespace |
| **Kubernetes / Compute Resources / Namespace (Pods)** | Namespace `media` wählen: jede App einzeln |
| **Kubernetes / Persistent Volumes** | Belegung der PVCs |

Probier es aus: Starte in Jellyfin eine Wiedergabe mit erzwungenem Transkodieren (Kapitel 16) und schau im Dashboard
**Namespace (Pods)** für `media` zu. Oben rechts lässt sich der Zeitraum einstellen, z. B. „Last 24 hours“.

> 💡 **PromQL:** Jedes Diagramm basiert auf einer Abfrage in der Sprache PromQL. Klick bei einem Diagramm auf **Edit**,
> um sie zu sehen. Unter **Explore** kannst du eigene Abfragen ausprobieren, z. B.
> `topk(5, sum by (pod) (container_memory_working_set_bytes{namespace="media"}))`: die fünf RAM-hungrigsten Pods in `media`.

## 6. Grafana auf Homepage (optional)

Füge in `kubernetes/apps/homepage/config/services.yaml` unter **Werkzeuge** eine Kachel hinzu:

```yaml
    - Grafana:
        icon: grafana.svg
        href: https://grafana.tail1a2b3c.ts.net
        description: Messwerte
        namespace: monitoring
        podSelector: app.kubernetes.io/name=grafana
```

## Ausblick: GPU-Messwerte

Die offizielle NVIDIA-Lösung (*DCGM-Exporter*) ist für Rechenzentrums-GPUs gedacht und unterstützt GeForce-Karten nur
eingeschränkt. Für die RTX 2070 Super eignet sich eher der Community-Exporter
[nvidia_gpu_exporter](https://github.com/utkuozdemir/nvidia_gpu_exporter), der die Werte aus `nvidia-smi` liest. Mit
allem, was du bis hier gelernt hast (DaemonSet, RuntimeClass, GPU-Anfrage, ServiceMonitor), kannst du ihn als eigene
Application ergänzen. Eine gute Abschlussübung!

## ✅ Checkpoint

- [ ] Alle Pods in `monitoring` laufen.
- [ ] `https://grafana.<tailnet>.ts.net` ist erreichbar, Login funktioniert.
- [ ] Das Dashboard **Node Exporter / Nodes** zeigt die VM.
- [ ] Du hast den Verbrauch der Medien-Apps in einem Dashboard gefunden.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Argo CD: `metadata.annotations: Too long` | `ServerSideApply=true` in `katalog/monitoring.yaml` und `aktiv/monitoring.yaml`? |
| Grafana-Login schlägt fehl | Secret `grafana-admin` vorhanden? Schlüssel `admin-user`/`admin-password` exakt so geschrieben? |
| Dashboards leer („No data“) | ein paar Minuten warten. Unter **Explore** die Abfrage `up` ausführen: Welche Ziele sind `1`? |
| Prometheus `OOMKilled` | `limits.memory` in den Values erhöhen oder `retention` verkürzen |
| Systemplatte läuft voll | `retentionSize` verkleinern (z. B. `4GB`) |

## 🎓 Was du gelernt hast

- **Prometheus** holt Messwerte von **Exportern** ab und speichert sie als Zeitreihen. **Grafana** stellt sie dar.
- **kube-prometheus-stack** bündelt alles, und über Values passt man es an k3s und die Homelab-Größe an.
- In einem großen Chart findest du alle bekannten Muster wieder: DaemonSet, StatefulSet, Sidecars, CRDs, ServiceMonitors.

---

⬅️ **Zurück:** [30 – SSD nachrüsten](30-ssd-nachruesten.md) · ➡️ **Weiter:** [32 – Mehr Nodes](32-mehr-nodes.md)
