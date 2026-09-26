# 15 – GPU an die VM durchreichen

> **Was du am Ende hast:** Die RTX 2070 Super gehört exklusiv der VM `k3s`. Dort ist der NVIDIA-Treiber installiert,
> und `nvidia-smi` zeigt die Karte an.
>
> ⏱️ **Zeit:** ca. 1–1,5 Stunden
>
> 🧠 **Neue Begriffe:** [PCIe-Passthrough](glossar.md#homelab--infrastruktur), [IOMMU](glossar.md#homelab--infrastruktur),
> [VFIO](glossar.md#homelab--infrastruktur), Kernel-Parameter, Treiber

---

> ⚠️ **Bevor du anfängst:**
> - **Monitor:** Dein Ryzen hat keine eigene Grafik. Sobald Proxmox die Grafikkarte abgibt, **bleibt der Monitor am
>   Desktop-PC schwarz** (bzw. bleibt nach den ersten Startmeldungen stehen). Das ist gewollt. Proxmox bedienst du
>   ohnehin über den Browser (`https://pve.<tailnet>.ts.net`).
> - **Der IOMMU-Check aus [Kapitel 02](02-proxmox-installieren.md#8-vorab-check-lässt-sich-die-grafikkarte-durchreichen)**
>   sollte erfolgreich gewesen sein.
> - 📸 **Snapshot** der VM anlegen (z. B. `vor-gpu`), bei **ausgeschalteter** VM.

## Wie funktioniert das?

Normalerweise lädt Proxmox beim Start Treiber für alle Geräte, auch für die Grafikkarte. Dann gehört sie Proxmox.
Beim **Passthrough** sagen wir Proxmox: *„Finger weg von der Grafikkarte, gib sie dem Platzhalter-Treiber **VFIO**.“*
VFIO reicht die Karte dann komplett an eine VM weiter, die sie benutzt, als wäre sie direkt eingebaut.

```
 Ohne Passthrough                           Mit Passthrough
┌─────────────────────┐                   ┌─────────────────────┐
│ Proxmox             │                   │ Proxmox             │
│  └─ Treiber: GPU    │                   │  └─ vfio-pci ─────┐ │
│                     │                   │   VM k3s          │ │
│   VM k3s            │                   │    └─ NVIDIA-Treiber ◄┘
│    (keine GPU)      │                   │       → RTX 2070 Super
└─────────────────────┘                   └─────────────────────┘
```

**IOMMU** sorgt dafür, dass die Grafikkarte nur auf den Speicher der VM zugreifen kann und nicht auf den von Proxmox.

## Teil 1: Proxmox vorbereiten

> 🟧 **Auf Proxmox** (`ssh root@pve`)

### 1. Kernel-Parameter setzen

Zwei zusätzliche Startparameter für den Linux-Kernel von Proxmox:

| Parameter | Bedeutung |
|-----------|-----------|
| `iommu=pt` | IOMMU nur für durchgereichte Geräte verwenden, das ist schneller |
| `initcall_blacklist=sysfb_init` | Proxmox soll die Grafikkarte beim Start nicht für die Bildschirmausgabe belegen. Ohne diesen Parameter lässt sich die einzige Grafikkarte im System oft nicht durchreichen |

Welcher Bootloader ist aktiv?

```bash
proxmox-boot-tool status
```

**Fall A: Ausgabe enthält `not configured` bzw. `E: /etc/kernel/proxmox-boot-uuids does not exist`** (Standard bei
ext4-Installation) → Proxmox nutzt **GRUB**:

```bash
nano /etc/default/grub
```

Die Zeile `GRUB_CMDLINE_LINUX_DEFAULT` ändern zu:

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet iommu=pt initcall_blacklist=sysfb_init"
```

Speichern (`Strg+O`, `Enter`, `Strg+X`) und übernehmen:

```bash
update-grub
```

**Fall B: Ausgabe zeigt konfigurierte ESPs mit `systemd-boot`** → Die Parameter gehören ans Ende der (einzigen) Zeile in
`/etc/kernel/cmdline`, danach `proxmox-boot-tool refresh`.

### 2. VFIO-Module laden

```bash
cat >> /etc/modules <<'EOF'
vfio
vfio_iommu_type1
vfio_pci
EOF
```

### 3. Die Grafikkarte für VFIO reservieren

Finde die **IDs** aller Teile der Grafikkarte (die Adresse `0a:00` hast du in Kapitel 02 notiert):

```bash
lspci -nn | grep -i nvidia
```

```
0a:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU104 [GeForce RTX 2070 SUPER] [10de:1e84] (rev a1)
0a:00.1 Audio device [0403]: NVIDIA Corporation TU104 HD Audio Controller [10de:10f8] (rev a1)
0a:00.2 USB controller [0c03]: NVIDIA Corporation TU104 USB 3.1 Host Controller [10de:1ad8] (rev a1)
0a:00.3 Serial bus controller [0c80]: NVIDIA Corporation TU104 USB Type-C UCSI Controller [10de:1ad9] (rev a1)
```

Die IDs stehen in den letzten eckigen Klammern: `10de:1e84`, `10de:10f8`, `10de:1ad8`, `10de:1ad9`.
(`10de` ist der Hersteller NVIDIA, der Rest das Gerät.) **Nimm die IDs aus deiner Ausgabe.**

```bash
cat > /etc/modprobe.d/vfio.conf <<'EOF'
# Die RTX 2070 Super (alle vier Teile) bekommt den Platzhalter-Treiber vfio-pci
options vfio-pci ids=10de:1e84,10de:10f8,10de:1ad8,10de:1ad9 disable_vga=1

# vfio-pci muss VOR den normalen Treibern geladen werden
softdep nouveau pre: vfio-pci
softdep snd_hda_intel pre: vfio-pci
softdep xhci_pci pre: vfio-pci
softdep i2c_nvidia_gpu pre: vfio-pci
EOF

cat > /etc/modprobe.d/blacklist-gpu.conf <<'EOF'
# Proxmox soll keine eigenen Grafiktreiber für die NVIDIA-Karte laden
blacklist nouveau
blacklist nvidiafb
EOF
```

> 💡 `softdep … pre: vfio-pci` heißt: *„Bevor du diesen Treiber lädst, lade vfio-pci.“* So schnappt sich vfio-pci
> die Grafikkarte, bevor es ein anderer Treiber tut. Die USB-Controller des Mainboards sind nicht betroffen, denn
> vfio-pci nimmt nur Geräte mit den oben genannten IDs.

### 4. Übernehmen und neu starten

```bash
update-initramfs -u -k all
reboot
```

Der Monitor zeigt die ersten Startmeldungen und bleibt dann stehen oder wird schwarz. Das ist das erwartete Zeichen. Nach ca. 1–2 Minuten:

```bash
ssh root@pve
lspci -nnk -s 0a:00
```

```
0a:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU104 [GeForce RTX 2070 SUPER] [10de:1e84] (rev a1)
        Kernel driver in use: vfio-pci
        Kernel modules: nvidiafb, nouveau
0a:00.1 Audio device [0403]: NVIDIA Corporation TU104 HD Audio Controller [10de:10f8] (rev a1)
        Kernel driver in use: vfio-pci
        ...
```

**Alle vier Teile** müssen `Kernel driver in use: vfio-pci` zeigen. ✅

## Teil 2: Die Grafikkarte der VM geben

In der Proxmox-Weboberfläche:

1. **100 (k3s)** → **Herunterfahren** und warten, bis die VM aus ist.
2. **Hardware** → **Hinzufügen** → **PCI-Gerät**
3. Ausfüllen (Häkchen **Erweitert** setzen):

| Feld | Wert |
|------|------|
| Typ | **Raw Device** |
| Gerät | `0000:0a:00.0` NVIDIA … TU104 [GeForce RTX 2070 SUPER] |
| Alle Funktionen (All Functions) | ☑ reicht alle vier Teile gemeinsam durch |
| Primäre GPU (Primary GPU) | ☐ so bleibt die Proxmox-Konsole der VM nutzbar |
| ROM-Bar | ☑ |
| PCI-Express | ☑ (geht nur mit Maschinentyp `q35`, deshalb Kapitel 04) |

4. **Hinzufügen** → VM **Starten**.

> 💡 Mit durchgereichter Hardware muss der VM ihr RAM fest zugeteilt sein. Deshalb haben wir in Kapitel 04 das
> Ballooning abgeschaltet. Snapshots legst du ab jetzt am besten bei **ausgeschalteter** VM an.

## Teil 3: Treiber in der VM

> 🐧 **In der VM** (`ssh homelab@k3s`)

Sieht die VM die Karte?

```bash
lspci | grep -i nvidia
```

```
01:00.0 VGA compatible controller: NVIDIA Corporation TU104 [GeForce RTX 2070 SUPER] (rev a1)
01:00.1 Audio device: NVIDIA Corporation TU104 HD Audio Controller (rev a1)
01:00.2 USB controller: NVIDIA Corporation TU104 USB 3.1 Host Controller (rev a1)
01:00.3 Serial bus controller: NVIDIA Corporation TU104 USB Type-C UCSI Controller (rev a1)
```

(Die Adresse ist in der VM eine andere, das ist normal.)

### Den passenden Treiber finden

Ubuntu bietet NVIDIA-Treiber in zwei Geschmacksrichtungen an: für Desktops und als **`-server`**-Variante für Server
(ohne grafische Oberfläche, mit langer Unterstützung). Wir nehmen die Server-Variante:

```bash
sudo apt update
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers list --gpgpu
```

```
nvidia-driver-535-server, (kernel modules provided by linux-modules-nvidia-535-server-generic)
nvidia-driver-570-server, (kernel modules provided by linux-modules-nvidia-570-server-generic)
nvidia-driver-580-server, (kernel modules provided by linux-modules-nvidia-580-server-generic)
...
```

Nimm die **höchste `-server`-Version, mindestens 570**. Jellyfin 12 bringt ein neues FFmpeg mit, das einen aktuellen
Treiber voraussetzt. Im Beispiel ist das `580`:

```bash
sudo ubuntu-drivers install --gpgpu nvidia:580-server
sudo apt install -y nvidia-utils-580-server
sudo reboot
```

> 💡 `--gpgpu` installiert den Treiber ohne grafische Oberfläche, genau richtig für einen Server.
> Die Nummer `580` musst du in **beiden** Befehlen an deine gewählte Version anpassen.

### Der Test

Nach dem Neustart:

```bash
nvidia-smi
```

```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.xx.xx              Driver Version: 580.xx.xx      CUDA Version: 13.0     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 2070 SUPER  Off |   00000000:01:00.0 Off |                  N/A |
|  0%   38C    P8              9W /  215W |       1MiB /   8192MiB |      0%      Default |
+-----------------------------------------+------------------------+----------------------+
```

Die RTX 2070 Super meldet sich in der VM. 🎉

## ✅ Checkpoint

- [ ] Auf Proxmox zeigt `lspci -nnk -s 0a:00` für alle vier Teile `Kernel driver in use: vfio-pci`.
- [ ] Die VM hat unter **Hardware** ein PCI-Gerät mit der Grafikkarte.
- [ ] In der VM zeigt `nvidia-smi` die RTX 2070 SUPER.
- [ ] Jellyfin und alle anderen Apps laufen nach dem Neustart wieder (`kubectl get pods -A`).
- [ ] Snapshot `gpu-ok` (bei ausgeschalteter VM) angelegt.

## 🔧 Wenn etwas schiefgeht

| Problem | Lösung |
|---------|--------|
| Nach dem Neustart zeigt `lspci -nnk` noch `nouveau` statt `vfio-pci` | IDs in `/etc/modprobe.d/vfio.conf` prüfen, `update-initramfs -u -k all` wiederholen, neu starten |
| VM startet nicht: `IOMMU not present` | IOMMU im BIOS aktiv? `dmesg \| grep -i AMD-Vi` (Kapitel 02) |
| VM startet nicht: `BAR … can't reserve` / `Failed to mmap` | `initcall_blacklist=sysfb_init` fehlt. `cat /proc/cmdline` zeigt die aktiven Parameter |
| Proxmox friert beim VM-Start ein | Grafikkarte teilt sich die IOMMU-Gruppe mit anderen Geräten → anderer PCIe-Slot. Notlösung: Kernel-Parameter `pcie_acs_override=downstream,multifunction` (lockert die Isolation, daher nur im Heimnetz vertretbar) |
| `nvidia-smi`: `No devices were found` | `sudo dmesg \| grep -i nvrm` in der VM lesen. Oft hilft in Proxmox beim PCI-Gerät **ROM-Bar** abzuwählen |
| `nvidia-smi`: `command not found` | `nvidia-utils-<version>-server` fehlt |
| `NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver` | Treiber nicht geladen → Neustart. Hilft das nicht: Ist Secure Boot aus (Kapitel 04)? `mokutil --sb-state` |
| Du willst zurück | Snapshot `vor-gpu` zurückspielen und auf Proxmox die beiden Dateien in `/etc/modprobe.d/` löschen, `update-initramfs -u -k all`, Neustart |

## 🎓 Was du gelernt hast

- **PCIe-Passthrough** gibt ein echtes Gerät exklusiv an eine VM. IOMMU schützt dabei den Speicher.
- **VFIO** ist der Platzhalter-Treiber, der das Gerät für die VM reserviert. Kernel-Parameter und `modprobe.d` steuern, welcher Treiber was bekommt.
- Die einzige Grafikkarte im System durchzureichen braucht `initcall_blacklist=sysfb_init`, und der Monitor bleibt danach dunkel.
- In der VM wird der ganz normale NVIDIA-Treiber installiert. `nvidia-smi` ist dein Testwerkzeug.

---

⬅️ **Zurück:** [14 – Secrets im Git](14-sealed-secrets.md) · ➡️ **Weiter:** [16 – GPU in Kubernetes](16-gpu-kubernetes.md)
