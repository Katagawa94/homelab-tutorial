# Die drei Apps. Jede hört nur auf 127.0.0.1, also nicht im Heimnetz.
# Von außen erreichbar sind sie nur über "tailscale serve" (ganz unten), mit echtem HTTPS-Zertifikat.
{ config, lib, pkgs, settings, ... }:
let
  fqdn = "${settings.hostName}.${settings.tailnet}";

  # Interner Port → Port im Tailnet
  ports = {
    nextcloud = { local = 8080; tailnet = 443; };
    vaultwarden = { local = 8222; tailnet = 8443; };
    linkwarden = { local = 3000; tailnet = 8444; };
  };
  url = app: "https://${fqdn}" + lib.optionalString (ports.${app}.tailnet != 443) ":${toString ports.${app}.tailnet}";
in
{
  sops.secrets = {
    nextcloud-admin-password.owner = "nextcloud";
    linkwarden-nextauth-secret.owner = "linkwarden";
  };

  # ── Vaultwarden: https://thinkpad.<tailnet>.ts.net:8443 ─────────────────────
  services.vaultwarden = {
    enable = true;
    backupDir = "/var/backup/vaultwarden"; # tägliche Kopie der Datenbank
    config = {
      DOMAIN = url "vaultwarden";
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = ports.vaultwarden.local;
      SIGNUPS_ALLOWED = settings.allowSignups;
    };
  };

  # ── Linkwarden: https://thinkpad.<tailnet>.ts.net:8444 ──────────────────────
  services.linkwarden = {
    enable = true;
    host = "127.0.0.1";
    port = ports.linkwarden.local;
    enableRegistration = settings.allowSignups;
    environment.NEXTAUTH_URL = "${url "linkwarden"}/api/v1/auth";
    secretFiles.NEXTAUTH_SECRET = config.sops.secrets.linkwarden-nextauth-secret.path;
    # Datenbank: legt das Modul selbst in PostgreSQL an
  };

  # ── Nextcloud: https://thinkpad.<tailnet>.ts.net ────────────────────────────
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud34; # Upgrades immer nur eine Hauptversion auf einmal (34 → 35)
    hostName = fqdn;
    https = true;
    database.createLocally = true;
    configureRedis = true;
    maxUploadSize = "10G";
    config = {
      dbtype = "pgsql";
      adminuser = "admin";
      adminpassFile = config.sops.secrets.nextcloud-admin-password.path;
    };
    settings = {
      trusted_proxies = [ "127.0.0.1" "::1" ];
      overwritehost = fqdn;
      overwriteprotocol = "https";
      default_phone_region = "DE";
      maintenance_window_start = 2; # Hintergrundjobs nachts (UTC)
    };
  };
  # Nextcloud bringt nginx mit. Der soll nur lokal lauschen, tailscale serve sitzt davor.
  services.nginx.virtualHosts.${fqdn}.listen = [
    { addr = "127.0.0.1"; port = ports.nextcloud.local; }
  ];

  # ── Tailscale serve: HTTPS im Tailnet ───────────────────────────────────────
  # Wird bei jedem Start und nach jeder Änderung neu gesetzt. Was hier nicht steht, wird entfernt.
  systemd.services.tailscale-serve-apps = {
    description = "Apps per tailscale serve im Tailnet veröffentlichen";
    after = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
    wants = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.services.tailscale.package ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 120;
    };
    script = ''
      tailscale serve reset
    '' + lib.concatMapStrings (app: ''
      tailscale serve --bg --https=${toString ports.${app}.tailnet} http://127.0.0.1:${toString ports.${app}.local}
    '') (lib.attrNames ports);
  };
}
