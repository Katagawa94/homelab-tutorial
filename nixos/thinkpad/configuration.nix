# Das Grundsystem: Benutzer, SSH, Tailscale, Strom sparen, Updates.
{ config, lib, pkgs, settings, ... }:
{
  assertions = [
    {
      assertion = !lib.any (lib.hasInfix "HIER-DEINEN-SCHLUESSEL") settings.sshKeys;
      message = "Trag in nixos/thinkpad/settings.nix deinen echten SSH-Schlüssel ein, sonst sperrst du dich aus.";
    }
  ];

  # ── Start & System ──────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10; # die letzten 10 Stände bleiben im Startmenü wählbar
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = settings.hostName;
  networking.useDHCP = true; # feste Adresse am besten im Router reservieren (FRITZ!Box: "immer dieselbe IP")
  time.timeZone = settings.timeZone;
  i18n.defaultLocale = "de_DE.UTF-8";
  console.keyMap = "de";

  # ── Benutzer & SSH ──────────────────────────────────────────────────────────
  users.mutableUsers = false; # Benutzer gibt es nur, wenn sie hier stehen
  users.users.${settings.user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = settings.sshKeys;
  };
  security.sudo.wheelNeedsPassword = false; # Anmeldung geht nur per SSH-Schlüssel, ein Passwort gibt es nicht

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  environment.systemPackages = with pkgs; [ git htop powertop lm_sensors ];

  # ── Tailscale ───────────────────────────────────────────────────────────────
  # Meldet sich beim ersten Start mit dem Auth-Key aus secrets.yaml an. Kein "tailscale up" von Hand.
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.tailscale-authkey.path;
    extraUpFlags = [ "--hostname=${settings.hostName}" ];
    openFirewall = true;
  };

  # ── Secrets (sops-nix) ──────────────────────────────────────────────────────
  # secrets.yaml liegt verschlüsselt im Git. Entschlüsselt wird beim Start mit dem age-Schlüssel,
  # den nixos-anywhere bei der Installation nach /var/lib/sops-nix/key.txt kopiert.
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.tailscale-authkey = { };
  };

  # ── Laptop als Server ───────────────────────────────────────────────────────
  # Deckel zu heißt nicht schlafen
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };
  boot.kernelParams = [ "consoleblank=60" ]; # Bildschirm nach 60 s aus

  # Strom sparen mit TLP (von nixos-hardware schon eingeschaltet, hier nur angepasst)
  services.tlp.settings = {
    CPU_ENERGY_PERF_POLICY_ON_AC = "balance_power"; # am Netz trotzdem sparsam, nicht volle Leistung
    PLATFORM_PROFILE_ON_AC = "low-power";
    USB_AUTOSUSPEND = 0; # USB-Festplatten und -Netzwerkadapter nicht schlafen legen
    START_CHARGE_THRESH_BAT0 = settings.batteryStopCharge - 5;
    STOP_CHARGE_THRESH_BAT0 = settings.batteryStopCharge;
  };

  # ── Nix selbst ──────────────────────────────────────────────────────────────
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "@wheel" ]; # erlaubt "nixos-rebuild --target-host" von deinem Rechner aus
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Optional: GitOps für den ganzen Server (Kapitel 36, Schritt 10)
  system.autoUpgrade = lib.mkIf (settings.gitopsFlake != null) {
    enable = true;
    flake = "${settings.gitopsFlake}#${settings.hostName}";
    dates = "04:00";
    allowReboot = false;
  };

  # Nicht ändern: die NixOS-Version, mit der installiert wurde (nicht die, die gerade läuft)
  system.stateVersion = "26.05";
}
