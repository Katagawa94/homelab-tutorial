# Glossar

Alle Fachbegriffe aus dem Tutorial, kurz und ohne Vorwissen erklärt. Die Kapitel verlinken hierher,
wenn ein Begriff zum ersten Mal auftaucht.

---

## Homelab & Infrastruktur

- **Homelab** – Ein Server (oder mehrere) zu Hause, auf dem man eigene Dienste betreibt und dabei lernt.
- **Hypervisor** – Software, die einen Rechner in mehrere virtuelle Rechner (VMs) aufteilt. Bei uns: Proxmox VE.
- **Proxmox VE** – Kostenloses Betriebssystem für Server, das VMs verwaltet. Bedienung über eine Weboberfläche im Browser.
- **VM (Virtuelle Maschine)** – Ein „Computer im Computer“. Er hat eigene (virtuelle) CPU, RAM, Festplatten und ein eigenes Betriebssystem.
- **Snapshot** – Eine Momentaufnahme einer VM. Geht etwas schief, springt man mit einem Klick zu diesem Zustand zurück.
- **Backup** – Eine Kopie der VM auf einem *anderen* Datenträger. Im Gegensatz zum Snapshot hilft ein Backup auch, wenn die Festplatte kaputtgeht.
- **LVM-Thin** – Die Art, wie Proxmox den Speicher für VM-Festplatten verwaltet. „Thin“ bedeutet: Belegt wird nur, was wirklich beschrieben wurde. Wird der Speicher trotzdem voll, bleiben alle VMs stehen. Deshalb lassen wir Puffer frei.
- **BIOS / UEFI** – Die Firmware des Mainboards. Hier werden grundlegende Funktionen wie die Virtualisierung eingeschaltet.
- **SVM (AMD-V)** – CPU-Funktion für Virtualisierung bei AMD-Prozessoren. Ohne sie laufen keine VMs.
- **IOMMU** – Mainboard-Funktion, mit der man echte Hardware (z. B. die Grafikkarte) exklusiv an eine VM geben kann.
- **VFIO** – Platzhalter-Treiber in Linux, der ein Gerät (z. B. die Grafikkarte) für eine VM reserviert, damit der Host es nicht selbst benutzt.
- **PCIe-Passthrough** – Eine echte PCIe-Karte (bei uns die RTX 2070 Super) wird direkt an eine VM durchgereicht. Die VM benutzt sie, als wäre sie eingebaut.

## Netzwerk

- **IP-Adresse** – Die „Hausnummer“ eines Geräts im Netzwerk, z. B. `192.168.178.10`.
- **Statische IP** – Eine IP-Adresse, die sich nie ändert. Server brauchen eine, damit man sie immer unter derselben Adresse findet.
- **DHCP** – Dienst im Router, der Geräten automatisch IP-Adressen gibt.
- **DNS** – Übersetzt Namen (z. B. `jellyfin.example.ts.net`) in IP-Adressen.
- **Port** – Eine „Tür“ an einer IP-Adresse. Jellyfin wartet z. B. an Port `8096`, die Proxmox-Weboberfläche an Port `8006`.
- **SSH** – Verschlüsselte Verbindung, um auf einem anderen Rechner Befehle einzugeben.
- **SSH-Key** – Ein Schlüsselpaar statt eines Passworts für SSH. Der *öffentliche* Teil kommt auf den Server, der *private* bleibt auf deinem Rechner.
- **VPN** – Verschlüsselter Tunnel zwischen Geräten oder ins Internet.
- **Kill-Switch** – Sperre, die jeden Internetverkehr blockiert, sobald das VPN ausfällt. Bei uns übernimmt das Gluetuns Firewall.
- **Port-Forwarding (VPN)** – Der VPN-Anbieter leitet einen Port von außen zu dir weiter. So können andere Teilnehmer dich erreichen, was Downloads beschleunigt. Bei Proton heißt die Technik *NAT-PMP*.
- **WireGuard** – Modernes, schnelles VPN-Protokoll. Tailscale und Proton VPN nutzen es.
- **Tailscale** – Dienst, der deine Geräte über WireGuard zu einem privaten Netz verbindet, egal wo sie gerade sind. Ports im Router müssen dafür nicht geöffnet werden.
- **Tailnet** – Dein privates Tailscale-Netz, also alle deine Geräte zusammen.
- **Tag (Tailscale)** – Etikett für Geräte im Tailnet, z. B. `tag:k8s`. Getaggte Geräte gehören keiner Person, sondern werden über Regeln verwaltet.
- **OAuth-Client** – Zugangsschlüssel für Programme (z. B. den Tailscale Operator) mit genau festgelegten Rechten (*Scopes*).
- **Personal Access Token (PAT)** – Ein Passwort-Ersatz für GitHub mit begrenzten Rechten, z. B. „dieses eine Repository nur lesen“.
- **MagicDNS** – Tailscale-Funktion: Geräte im Tailnet sind über ihren Namen erreichbar (z. B. `ssh homelab@k3s`).

## Container & Kubernetes

- **Container** – Ein Programm samt allem, was es zum Laufen braucht, verpackt und vom Rest des Systems abgeschottet.
- **Image** – Die „Vorlage“ für einen Container, z. B. `jellyfin/jellyfin:10.10`. Aus einem Image können beliebig viele Container gestartet werden.
- **Registry** – Online-Lager für Images, z. B. Docker Hub oder GitHub Container Registry.
- **Kubernetes (K8s)** – System, das Container auf einem oder vielen Rechnern startet, überwacht und bei Problemen neu startet. Man beschreibt, *was* laufen soll, und Kubernetes sorgt dafür, dass es so ist.
- **k3s** – Eine schlanke, vollwertige Kubernetes-Variante. Sie ist mit einem Befehl installiert und ideal für Homelabs.
- **Cluster** – Alle Rechner (Nodes), die zusammen ein Kubernetes bilden. Bei uns zunächst nur einer.
- **Node** – Ein Rechner im Cluster. Bei uns ist das die VM `k3s`.
- **Control Plane** – Das „Gehirn“ von Kubernetes. Es nimmt Befehle entgegen, merkt sich den Soll-Zustand und verteilt die Arbeit.
- **kubectl** – Das Kommandozeilen-Werkzeug, mit dem du Kubernetes steuerst.
- **kubeconfig** – Datei (meist `~/.kube/config`), in der steht, wo dein Cluster ist und wie `kubectl` sich anmeldet.
- **Context** – Ein Eintrag in der kubeconfig (Cluster + Benutzer). Damit kann `kubectl` zwischen mehreren Clustern wechseln.
- **Manifest** – Eine YAML-Datei, die beschreibt, was in Kubernetes existieren soll.
- **YAML** – Textformat für Konfigurationsdateien. Die Einrückung (Leerzeichen, keine Tabs!) ist wichtig.
- **Namespace** – Ein „Ordner“ im Cluster, um Dinge zu gruppieren, z. B. `media` für Jellyfin und den *arr-Stack.
- **Pod** – Die kleinste Einheit in Kubernetes: ein oder mehrere Container, die zusammen laufen und sich Netzwerk und Speicher teilen.
- **Deployment** – Beschreibt, welcher Pod wie oft laufen soll. Stirbt ein Pod, startet das Deployment einen neuen.
- **ReplicaSet** – Hilfsobjekt eines Deployments, das die gewünschte Anzahl Pods sicherstellt. Man fasst es selten direkt an.
- **StatefulSet** – Wie ein Deployment, aber mit festen Pod-Namen (`name-0`, `name-1` …) und eigenem Speicher pro Pod (`volumeClaimTemplates`). Typisch für Datenbanken.
- **DaemonSet** – Startet einen Pod auf *jedem* Node, z. B. für Treiber-Plugins.
- **Service** – Feste Adresse für eine Gruppe von Pods. Pods kommen und gehen, der Service bleibt.
- **Extended Resource** – Zusätzliche Ressource neben CPU und RAM, die ein Plugin meldet, z. B. `nvidia.com/gpu`.
- **Node-Label** – Label an einem Node, z. B. `nvidia.com/gpu.present=true`. Damit lässt sich steuern, welche Pods auf welchem Node laufen.
- **LoadBalancer** – Service-Typ, der die App unter der IP des Nodes im Heimnetz erreichbar macht (bei k3s über *ServiceLB*).
- **IngressClass** – Legt fest, welches Programm einen Ingress umsetzt: `traefik` (bei k3s dabei) oder `tailscale` (Tailscale Operator).
- **Ingress** – Regel, die Anfragen anhand des Namens (z. B. `jellyfin.…`) an den richtigen Service weiterleitet.
- **PersistentVolume (PV)** – Ein Stück Speicher, das Kubernetes zur Verfügung steht, z. B. ein Ordner auf der Festplatte.
- **PersistentVolumeClaim (PVC)** – Die „Bestellung“ einer App: „Ich brauche 5 GB Speicher.“ Kubernetes verbindet sie mit einem passenden PV.
- **hostPath** – Volume, das einfach einen Ordner des Nodes in den Pod einbindet, bei uns `/data` für die Medien.
- **emptyDir** – Leeres Volume, das mit dem Pod entsteht und mit ihm verschwindet. Gut für Zwischenspeicher.
- **Reclaim Policy** – Was mit den Daten passiert, wenn der PVC gelöscht wird: `Delete` (weg) oder `Retain` (bleiben).
- **StorageClass** – Beschreibt, *wie* Speicher automatisch angelegt wird. k3s bringt `local-path` mit.
- **ConfigMap** – Konfigurationswerte (keine Geheimnisse), die in Pods als Datei oder Umgebungsvariable landen.
- **Secret** – Wie eine ConfigMap, aber für Passwörter und Schlüssel.
- **Probe** – Regelmäßige Gesundheitsprüfung eines Containers: *startup* (hochgefahren?), *readiness* (bereit für Anfragen?), *liveness* (lebt noch?).
- **securityContext** – Legt fest, mit welchen Rechten ein Container läuft, z. B. als Benutzer `1000`.
- **configMapGenerator** – Kustomize-Funktion, die aus normalen Dateien eine ConfigMap erzeugt. Ein Hash im Namen sorgt dafür, dass Pods bei Änderungen automatisch neu starten.
- **RBAC** – *Role-Based Access Control*: legt fest, wer im Cluster was darf.
- **ServiceAccount** – Die Identität, unter der ein Pod mit der Kubernetes-API spricht.
- **Role / ClusterRole** – Eine Liste von Rechten (z. B. „Pods lesen“), gültig in einem Namespace bzw. im ganzen Cluster. Ein **(Cluster)RoleBinding** gibt sie einem ServiceAccount oder Benutzer.
- **Kustomize** – In `kubectl` eingebautes Werkzeug (`kubectl apply -k`), das Manifeste aus einer `kustomization.yaml` zusammensetzt und per *Patch* ergänzen kann.
- **Helm** – Paketmanager für Kubernetes. Ein *Chart* ist ein Paket, *Values* sind deine Einstellungen dazu, ein *Release* ist ein installiertes Chart.
- **Operator** – Programm im Cluster, das eine bestimmte Aufgabe automatisiert, z. B. der Tailscale Operator, der Apps ins Tailnet bringt.
- **CRD (Custom Resource Definition)** – Erweiterung von Kubernetes um neue Objekttypen, meist von einem Operator mitgebracht.
- **RuntimeClass** – Name für eine Art, Container zu starten. `nvidia` startet Container mit Zugriff auf die GPU.
- **Container Toolkit (NVIDIA)** – Software auf dem Node, die Treiber und GPU-Geräte in Container bringt.
- **Time-Slicing** – Eine GPU wird als mehrere gemeldet, und die Pods teilen sich ihre Rechenzeit. So können Jellyfin und Immich eine Karte gemeinsam nutzen.
- **Device Plugin** – Programm (meist als DaemonSet), das Kubernetes spezielle Hardware wie GPUs als Ressource meldet.
- **Nativer Sidecar** – Ein Sidecar, der als `initContainer` mit `restartPolicy: Always` definiert ist. Er startet **vor** der Haupt-App und läuft die ganze Zeit mit.
- **Sidecar** – Ein zusätzlicher Container im selben Pod, der der Haupt-App hilft, z. B. Gluetun als VPN für qBittorrent.
- **GitOps** – Arbeitsweise, bei der der Soll-Zustand des Clusters in einem Git-Repository steht. Ein Werkzeug gleicht den Cluster automatisch daran an.
- **Argo CD** – Das GitOps-Werkzeug in diesem Tutorial, mit Weboberfläche.
- **Application (Argo CD)** – Beschreibt für Argo CD: *diese Quelle* (Git-Ordner oder Helm-Chart) *in dieses Ziel* (Namespace im Cluster) ausrollen.
- **App-of-Apps** – Eine Application, die selbst nur andere Applications enthält. Bei uns: `root` → alles in `kubernetes/aktiv/`.
- **Sync / Prune / Self-Heal** – *Sync*: Git-Stand ausrollen. *Prune*: aus Git Entferntes löschen. *Self-Heal*: Änderungen am Git vorbei zurücksetzen.
- **kubeseal** – Kommandozeilenwerkzeug, das ein Secret mit dem öffentlichen Schlüssel des Clusters zu einem SealedSecret verschlüsselt.
- **Sealed Secrets** – Verschlüsselt Secrets so, dass sie gefahrlos ins Git-Repository dürfen. Nur der Cluster kann sie entschlüsseln.

## Medien

- **Jellyfin** – Freier Medienserver, quasi ein eigenes Netflix für deine Filme und Serien.
- **Direct Play** – Das Abspielgerät kann die Datei direkt abspielen. Das kostet den Server fast keine Leistung.
- **Transcoding** – Der Server wandelt ein Video in ein Format um, das das Gerät versteht. Ohne GPU ist das sehr CPU-lastig.
- **NVENC / NVDEC** – Die Video-Encoder und -Decoder in NVIDIA-Grafikkarten. Sie machen Transcoding schnell und sparsam.
- **Codec** – Verfahren zur Kompression von Video (H.264, HEVC …) oder Audio (AAC, DTS …).
- ***arr-Stack** – Sammelname für Sonarr, Radarr, Prowlarr, Bazarr & Co. Sie verwalten und organisieren Serien und Filme automatisch.
- **Indexer** – Eine Suchquelle für Downloads. Prowlarr verwaltet sie zentral für Sonarr und Radarr.
- **Seeding** – Eine fertig geladene Datei weiter mit anderen teilen. Dafür muss sie in `/data/downloads` liegen bleiben.
- **Hardlink** – Zwei Dateinamen, die auf *dieselben* Daten auf der Platte zeigen. So belegt eine Datei in `downloads/` und `media/` nur einmal Platz.
- **PUID / PGID** – Benutzer- und Gruppen-Nummer, unter der eine App Dateien anlegt. Sie muss zu den Rechten auf `/data` passen.
