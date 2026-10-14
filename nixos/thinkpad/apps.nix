# Die drei Apps. Jede hört nur auf 127.0.0.1, also nicht im Heimnetz.
# Ins Tailnet bringt sie "tailscale serve" (ganz unten) als Tailscale Service: Jede App bekommt einen
# eigenen Namen wie https://nextcloud.<tailnet>.ts.net, mit echtem HTTPS-Zertifikat.
{ config, lib, pkgs, settings, ... }:
let
  # App → Port, auf dem sie lokal lauscht. Der Name ist zugleich der Tailscale Service (svc:<name>).
  ports = {
    nextcloud = 8080;
    vaultwarden = 8222;
    linkwarden = 3000;
  };
  fqdn = app: "${app}.${settings.tailnet}";
  url = app: "https://${fqdn app}";
in
{
  sops.secrets = {
    nextcloud-admin-password.owner = "nextcloud";
    linkwarden-nextauth-secret.owner = "linkwarden";
  };

  # ── Vaultwarden: https://vaultwarden.<tailnet>.ts.net ───────────────────────
  services.vaultwarden = {
    enable = true;
    backupDir = "/var/backup/vaultwarden"; # tägliche Kopie der Datenbank
    config = {
      DOMAIN = url "vaultwarden";
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = ports.vaultwarden;
      SIGNUPS_ALLOWED = settings.allowSignups;
    };
  };

  # ── Linkwarden: https://linkwarden.<tailnet>.ts.net ─────────────────────────
  services.linkwarden = {
    enable = true;
    host = "127.0.0.1";
    port = ports.linkwarden;
    enableRegistration = settings.allowSignups;
    environment.NEXTAUTH_URL = "${url "linkwarden"}/api/v1/auth";
    secretFiles.NEXTAUTH_SECRET = config.sops.secrets.linkwarden-nextauth-secret.path;
    # Datenbank: legt das Modul selbst in PostgreSQL an
  };

  # ── Nextcloud: https://nextcloud.<tailnet>.ts.net ───────────────────────────
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud34; # Upgrades immer nur eine Hauptversion auf einmal (34 → 35)
    hostName = fqdn "nextcloud";
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
      overwritehost = fqdn "nextcloud";
      overwriteprotocol = "https";
      default_phone_region = "DE";
      maintenance_window_start = 2; # Hintergrundjobs nachts (UTC)
    };
  };
  # Nextcloud bringt nginx mit. Der soll nur lokal lauschen, tailscale serve sitzt davor.
  services.nginx.virtualHosts.${fqdn "nextcloud"}.listen = [
    { addr = "127.0.0.1"; port = ports.nextcloud; }
  ];

  # ── Tailscale Services: ein Name pro App ────────────────────────────────────
  # Wird bei jedem Start und nach jeder Änderung neu gesetzt. Was hier nicht steht, wird entfernt.
  # Voraussetzung (einmalig in der Admin-Konsole, Kapitel 36, Schritt 3): der ThinkPad ist getaggt,
  # und es gibt die Services svc:nextcloud, svc:vaultwarden und svc:linkwarden.
  systemd.services.tailscale-serve-apps = {
    description = "Apps als Tailscale Services im Tailnet veröffentlichen";
    after = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
    wants = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.services.tailscale.package ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 120;
    };
    # HTTPS nach außen, einfaches HTTP zur App auf 127.0.0.1
    script = ''
      tailscale serve reset
    '' + lib.concatMapStrings (app: ''
      tailscale serve --service=svc:${app} --https=443 http://127.0.0.1:${toString ports.${app}}
    '') (lib.attrNames ports);
  };
}
