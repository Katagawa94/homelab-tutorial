# Die einzige Datei, die du vor der Installation anpassen musst (Kapitel 36, Schritt 2).
{
  # Name des Rechners, im Heimnetz und im Tailnet
  hostName = "thinkpad";

  # Dein Tailnet-Name: Tailscale-Admin-Konsole → DNS → "Tailnet name"
  tailnet = "tail1a2b3c.ts.net";

  # Tag für den Server im Tailnet. Muss in der Tailscale-Policy unter "tagOwners" stehen (Kapitel 36, Schritt 3).
  tailscaleTag = "tag:server";

  # Modell aus https://github.com/NixOS/nixos-hardware/blob/master/flake.nix,
  # z. B. "lenovo-thinkpad-t480" oder "lenovo-thinkpad-t14". Unsicher? "lenovo-thinkpad" passt immer.
  hardwareModule = "lenovo-thinkpad";

  # Die Festplatte, auf die NixOS kommt. ⚠️ Sie wird komplett gelöscht!
  # Mit "lsblk" im Installer nachsehen: NVMe-SSD meist /dev/nvme0n1, SATA-SSD meist /dev/sda
  disk = "/dev/nvme0n1";

  # Dein Benutzer auf dem Server (wie in Kapitel 04)
  user = "homelab";

  # Dein öffentlicher SSH-Schlüssel: Inhalt von ~/.ssh/id_ed25519.pub (Kapitel 01)
  sshKeys = [
    "ssh-ed25519 AAAA-HIER-DEINEN-SCHLUESSEL-EINFUEGEN du@laptop"
  ];

  timeZone = "Europe/Berlin";

  # Akku schonen: nur bis hierhin laden (Prozent). Der Akku bleibt so jahrelang als kleine USV nutzbar.
  batteryStopCharge = 80;

  # Neue Konten in Vaultwarden und Linkwarden erlauben? Nach dem Anlegen deines Kontos auf false setzen
  # und neu ausrollen (Kapitel 36, Schritt 8).
  allowSignups = true;

  # Optional: Der Server holt sich jede Nacht selbst den Stand aus Git, wie Argo CD für den ganzen Rechner.
  # null = aus. Sonst z. B. "github:DEIN-NAME/homelab-tutorial?dir=nixos" (Kapitel 36, Schritt 10).
  gitopsFlake = null;
}
