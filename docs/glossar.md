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
- **WireGuard** – Modernes, schnelles VPN-Protokoll. Tailscale und Proton VPN nutzen es.
- **Tailscale** – Dienst, der deine Geräte über WireGuard zu einem privaten Netz verbindet, egal wo sie gerade sind. Ports im Router müssen dafür nicht geöffnet werden.
- **Tailnet** – Dein privates Tailscale-Netz, also alle deine Geräte zusammen.
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
- **DaemonSet** – Startet einen Pod auf *jedem* Node, z. B. für Treiber-Plugins.
- **Service** – Feste Adresse für eine Gruppe von Pods. Pods kommen und gehen, der Service bleibt.
- **LoadBalancer** – Service-Typ, der die App unter der IP des Nodes im Heimnetz erreichbar macht (bei k3s über *ServiceLB*).
- **Ingress** – Regel, die Anfragen anhand des Namens (z. B. `jellyfin.…`) an den richtigen Service weiterleitet.
- **PersistentVolume (PV)** – Ein Stück Speicher, das Kubernetes zur Verfügung steht, z. B. ein Ordner auf der Festplatte.
- **PersistentVolumeClaim (PVC)** – Die „Bestellung“ einer App: „Ich brauche 5 GB Speicher.“ Kubernetes verbindet sie mit einem passenden PV.
- **StorageClass** – Beschreibt, *wie* Speicher automatisch angelegt wird. k3s bringt `local-path` mit.
- **ConfigMap** – Konfigurationswerte (keine Geheimnisse), die in Pods als Datei oder Umgebungsvariable landen.
- **Secret** – Wie eine ConfigMap, aber für Passwörter und Schlüssel.
- **Helm** – Paketmanager für Kubernetes. Ein *Chart* ist ein Paket, *Values* sind deine Einstellungen dazu, ein *Release* ist ein installiertes Chart.
- **Operator** – Programm im Cluster, das eine bestimmte Aufgabe automatisiert, z. B. der Tailscale Operator, der Apps ins Tailnet bringt.
- **CRD (Custom Resource Definition)** – Erweiterung von Kubernetes um neue Objekttypen, meist von einem Operator mitgebracht.
- **Sidecar** – Ein zusätzlicher Container im selben Pod, der der Haupt-App hilft, z. B. Gluetun als VPN für qBittorrent.
- **GitOps** – Arbeitsweise, bei der der Soll-Zustand des Clusters in einem Git-Repository steht. Ein Werkzeug gleicht den Cluster automatisch daran an.
- **Argo CD** – Das GitOps-Werkzeug in diesem Tutorial, mit Weboberfläche.
- **Sealed Secrets** – Verschlüsselt Secrets so, dass sie gefahrlos ins Git-Repository dürfen. Nur der Cluster kann sie entschlüsseln.

## Medien

- **Jellyfin** – Freier Medienserver, quasi ein eigenes Netflix für deine Filme und Serien.
- **Direct Play** – Das Abspielgerät kann die Datei direkt abspielen. Das kostet den Server fast keine Leistung.
- **Transcoding** – Der Server wandelt ein Video in ein Format um, das das Gerät versteht. Ohne GPU ist das sehr CPU-lastig.
- **NVENC / NVDEC** – Die Video-Encoder und -Decoder in NVIDIA-Grafikkarten. Sie machen Transcoding schnell und sparsam.
- **Codec** – Verfahren zur Kompression von Video (H.264, HEVC …) oder Audio (AAC, DTS …).
- ***arr-Stack** – Sammelname für Sonarr, Radarr, Prowlarr, Bazarr & Co. Sie verwalten und organisieren Serien und Filme automatisch.
- **Hardlink** – Zwei Dateinamen, die auf *dieselben* Daten auf der Platte zeigen. So belegt eine Datei in `downloads/` und `media/` nur einmal Platz.
- **PUID / PGID** – Benutzer- und Gruppen-Nummer, unter der eine App Dateien anlegt. Sie muss zu den Rechten auf `/data` passen.
