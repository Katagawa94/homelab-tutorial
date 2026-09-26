# 05 – k3s installieren

> **Was du am Ende hast:** Ein laufender Kubernetes-Cluster in der VM, den du von deinem Rechner aus mit `kubectl`
> steuerst, zu Hause und unterwegs über Tailscale.
>
> ⏱️ **Zeit:** ca. 30 Minuten
>
> 🧠 **Neue Begriffe:** [k3s](glossar.md#container--kubernetes), [Cluster](glossar.md#container--kubernetes),
> [Node](glossar.md#container--kubernetes), [Control Plane](glossar.md#container--kubernetes),
> [kubectl](glossar.md#container--kubernetes), [kubeconfig](glossar.md#container--kubernetes),
> [Context](glossar.md#container--kubernetes), [Namespace](glossar.md#container--kubernetes), [Pod](glossar.md#container--kubernetes)

---

> 📸 **Snapshot-Routine:** Bevor du loslegst, lege in Proxmox einen Snapshot der VM an (z. B. `vor-k3s`).

## Was ist k3s?

**k3s** ist ein vollwertiges, offiziell zertifiziertes Kubernetes, nur schlanker verpackt: ein einziges Programm, ein
Installationsbefehl. Mitgeliefert werden praktische Bausteine, die wir im Tutorial nutzen:

| Baustein | Aufgabe |
|----------|---------|
| **containerd** | startet die Container |
| **CoreDNS** | Namensauflösung im Cluster (Apps finden sich gegenseitig über Namen) |
| **local-path-provisioner** | legt automatisch Speicher für Apps auf der Festplatte der VM an |
| **ServiceLB** | macht Apps unter der IP der VM im Heimnetz erreichbar (wichtig für den Samsung-TV!) |
| **Traefik** | Ingress-Controller: leitet Anfragen anhand des Namens an Apps weiter |
| **metrics-server** | misst CPU- und RAM-Verbrauch |

## 1. Tailscale in der VM

Damit du den Cluster auch unterwegs steuern kannst, kommt die VM ins Tailnet, genau wie Proxmox in Kapitel 03.

> 🐧 **In der VM** (`ssh homelab@192.168.178.11`)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Link öffnen, anmelden, **Connect**. Danach die Tailscale-IP der VM notieren:

```bash
tailscale ip -4
```

```
100.101.102.104
```

Und wie bei Proxmox: In der [Admin-Konsole](https://login.tailscale.com/admin/machines) beim Gerät **k3s** auf
**⋯ → Disable key expiry** klicken.

> 💻 **Auf deinem Rechner:** Ab jetzt reicht der Name:
>
> ```bash
> ssh homelab@k3s
> ```

## 2. k3s vorkonfigurieren

Der Kubernetes-API-Server, mit dem `kubectl` spricht, weist sich mit einem Zertifikat aus. Das Zertifikat gilt nur für
die Namen und Adressen, die beim Start bekannt sind. Damit `kubectl` später auch über den Tailscale-Namen `k3s`
funktioniert, tragen wir alle Namen vorab in die Konfigurationsdatei von k3s ein.

> 🐧 **In der VM** – ersetze Tailnet-Name und Tailscale-IP durch deine Werte:

```bash
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/config.yaml > /dev/null <<'EOF'
# Namen und Adressen, unter denen der Kubernetes-API-Server erreichbar sein soll.
tls-san:
  - k3s                      # Tailscale-Kurzname (MagicDNS)
  - k3s.tail1a2b3c.ts.net    # Tailscale-Langname
  - 100.101.102.104          # Tailscale-IP
  - 192.168.178.11           # IP im Heimnetz
EOF
```

Kontrolle:

```bash
cat /etc/rancher/k3s/config.yaml
```

> 💡 **YAML-Regel Nr. 1:** Einrückung nur mit **Leerzeichen**, niemals mit Tabs. Die Striche vor den Einträgen machen daraus eine Liste.
> Diese Datei ist dein erstes selbst geschriebenes YAML. In Kubernetes wirst du noch sehr viel YAML sehen.

## 3. k3s installieren

```bash
curl -sfL https://get.k3s.io | sh -
```

Nach etwa einer Minute endet die Ausgabe mit:

```
[INFO]  systemd: Enabling k3s unit
Created symlink /etc/systemd/system/multi-user.target.wants/k3s.service → /etc/systemd/system/k3s.service.
[INFO]  systemd: Starting k3s
```

Das war's, Kubernetes läuft. 🎉 Kurzer Test direkt in der VM:

```bash
sudo k3s kubectl get nodes
```

```
NAME   STATUS   ROLES           AGE   VERSION
k3s    Ready    control-plane   42s   v1.34.1+k3s1
```

(Rolle und Versionsnummer können bei dir etwas anders aussehen.)

> 💡 **Was ist gerade passiert?** Das Skript hat k3s als **systemd-Dienst** eingerichtet. k3s startet also automatisch
> mit der VM. Status ansehen: `sudo systemctl status k3s`. Logs ansehen: `sudo journalctl -u k3s -f` (Beenden mit `Strg+C`).

## 4. `kubectl` auf deinem Rechner einrichten

In der VM liegt die Datei `/etc/rancher/k3s/k3s.yaml`, die **kubeconfig**. Sie enthält die Adresse des Clusters und
einen Zugangsschlüssel. Wer sie hat, hat volle Kontrolle über den Cluster. Behandle sie wie ein Passwort.

### Datei holen

> 🐧 **In der VM** – die Datei gehört `root`, also erst eine Kopie für `homelab` anlegen:

```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~/k3s.yaml
sudo chown homelab:homelab ~/k3s.yaml
```

> 💻 **Auf deinem Rechner**

Prüfe zuerst, ob du schon eine kubeconfig hast:

```bash
ls ~/.kube/config
```

**Fall A: „No such file or directory“** (der Normalfall):

```bash
mkdir -p ~/.kube
scp homelab@k3s:k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config
```

**Fall B: Die Datei existiert schon** (du nutzt bereits einen anderen Cluster). Dann nicht überschreiben, sondern daneben legen:

```bash
scp homelab@k3s:k3s.yaml ~/.kube/homelab.yaml
chmod 600 ~/.kube/homelab.yaml
export KUBECONFIG=~/.kube/homelab.yaml   # gilt für dieses Terminal
```

(Im Folgenden ersetzt du dann `~/.kube/config` durch `~/.kube/homelab.yaml`.)

Und die Kopie in der VM wieder löschen:

```bash
ssh homelab@k3s rm k3s.yaml
```

### Adresse anpassen

In der Datei steht als Serveradresse `https://127.0.0.1:6443`, also „dieser Rechner selbst“. Das stimmt nur in der VM.
Wir ersetzen es durch den Tailscale-Namen:

```bash
sed -i 's/127.0.0.1/k3s/' ~/.kube/config
grep server ~/.kube/config
```

```
    server: https://k3s:6443
```

### Context umbenennen

Eine kubeconfig kann mehrere Cluster kennen. Jeder Eintrag heißt **Context**. k3s nennt seinen Context `default`,
wir geben ihm einen sprechenden Namen:

```bash
kubectl config rename-context default homelab
kubectl config get-contexts
```

```
CURRENT   NAME      CLUSTER   AUTHINFO   NAMESPACE
*         homelab   default   default
```

## 5. Der erste Blick in den Cluster

> 💻 **Auf deinem Rechner**

```bash
kubectl get nodes -o wide
```

```
NAME   STATUS   ROLES           AGE   VERSION        INTERNAL-IP      OS-IMAGE             ...
k3s    Ready    control-plane   5m    v1.34.1+k3s1   192.168.178.11   Ubuntu 24.04.3 LTS   ...
```

Du steuerst den Cluster jetzt von deinem Rechner aus. Die Verbindung läuft über Tailscale, funktioniert also auch aus dem Café.

### Was läuft da schon?

```bash
kubectl get pods --all-namespaces
```

```
NAMESPACE     NAME                                      READY   STATUS      RESTARTS   AGE
kube-system   coredns-64fd4b4794-x7k2p                  1/1     Running     0          5m
kube-system   helm-install-traefik-crd-9vzl4            0/1     Completed   0          5m
kube-system   helm-install-traefik-xk8wq                0/1     Completed   1          5m
kube-system   local-path-provisioner-774c6665dc-2lq5d   1/1     Running     0          5m
kube-system   metrics-server-7bfffcd44-fz8r6            1/1     Running     0          5m
kube-system   svclb-traefik-4a7c1d2e-8hx6n              2/2     Running     0          4m
kube-system   traefik-c98fdf6fb-5wq7z                   1/1     Running     0          4m
```

Jede Zeile ist ein **Pod**, also eine laufende App. Sie alle stecken im **Namespace** `kube-system`, dem „Ordner“ für
Kubernetes' eigene Bausteine. Du erkennst die Bausteine aus der Tabelle oben wieder:

| Pod | Aufgabe |
|-----|---------|
| `coredns-…` | Namensauflösung im Cluster |
| `local-path-provisioner-…` | Speicher für Apps |
| `metrics-server-…` | Verbrauchsmessung |
| `traefik-…` | Ingress-Controller |
| `svclb-traefik-…` | ServiceLB: macht Traefik unter `192.168.178.11` erreichbar |
| `helm-install-…` | einmalige Installationsaufträge, daher `Completed` |

Die zufälligen Endungen (`-x7k2p`) vergibt Kubernetes automatisch, deshalb sehen sie bei dir anders aus.

Der **metrics-server** zeigt den Verbrauch:

```bash
kubectl top node
```

```
NAME   CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k3s    98m          1%       1245Mi          10%
```

`98m` heißt 98 „Milli-CPUs“, also knapp ein Zehntel eines CPU-Kerns. Kubernetes selbst ist genügsam.

## 6. Snapshot „frischer Cluster“

In Proxmox: **100 (k3s)** → **Snapshots** → **Snapshot erstellen** → Name `k3s-frisch` → **OK**.

Diesen Snapshot solltest du länger aufbewahren. Egal was du in Teil B anstellst, von hier kannst du immer neu starten.

## ✅ Checkpoint

- [ ] `ssh homelab@k3s` funktioniert.
- [ ] In der Tailscale-Admin-Konsole steht **k3s** mit **Expiry disabled**.
- [ ] `kubectl config current-context` gibt `homelab` aus.
- [ ] `kubectl get nodes` zeigt `k3s` mit Status `Ready`.
- [ ] Alle Pods in `kube-system` sind `Running` oder `Completed`.
- [ ] `kubectl top node` zeigt Werte (kann nach der Installation 1–2 Minuten dauern).
- [ ] Der Snapshot `k3s-frisch` existiert.
- [ ] Bonus: Im Handy-Hotspot funktioniert `kubectl get nodes` ebenfalls.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| `x509: certificate is valid for …, not k3s` | Der Name fehlt unter `tls-san`. In der VM `/etc/rancher/k3s/config.yaml` ergänzen, dann `sudo systemctl restart k3s` |
| `dial tcp: lookup k3s … no such host` | Tailscale läuft auf deinem Rechner nicht, oder MagicDNS ist aus → `tailscale status` |
| `The connection to the server k3s:6443 was refused` | k3s läuft nicht: in der VM `sudo systemctl status k3s` und `sudo journalctl -u k3s -n 50` |
| `error: open /home/…/.kube/config: permission denied` | `chmod 600 ~/.kube/config` und prüfen, dass die Datei dir gehört |
| `kubectl top node` → `metrics not available yet` | 1–2 Minuten warten |
| Pods hängen in `ContainerCreating` | Hat die VM Internet? In der VM `curl -sI https://ghcr.io | head -1` ausführen, das sollte eine `HTTP`-Zeile ausgeben |
| Du hast `ufw` aktiviert und nichts geht mehr | Für dieses Tutorial `sudo ufw disable`. Im Heimnetz schützt dich der Router, und von außen ist nur Tailscale erreichbar |

**Komplett neu anfangen?** Snapshot `vor-k3s` zurückspielen, oder in der VM `/usr/local/bin/k3s-uninstall.sh` ausführen.

## 🎓 Was du gelernt hast

- k3s ist ein vollständiges Kubernetes und läuft als systemd-Dienst in der VM.
- `kubectl` spricht mit dem **API-Server** des Clusters. Wohin und mit welchem Schlüssel, steht in der **kubeconfig**.
- Das Zertifikat des API-Servers muss alle Namen kennen, unter denen du ihn ansprichst (`tls-san`).
- Ein **Context** ist ein benannter Eintrag in der kubeconfig.
- Kubernetes besteht selbst aus Pods, die im Namespace `kube-system` laufen.

**Teil A ist geschafft!** 🎉 Du hast einen Hypervisor, eine VM und einen Kubernetes-Cluster, alles fernsteuerbar über
Tailscale. In **Teil B** lernst du, wie man eigene Apps in diesen Cluster bringt.

---

⬅️ **Zurück:** [04 – Die Kubernetes-VM](04-kubernetes-vm.md) · ➡️ **Weiter:** 06 – Erster Pod *(folgt in Phase 2)*
