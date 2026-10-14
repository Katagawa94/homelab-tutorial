# Partitionen als Code. nixos-anywhere legt sie bei der Installation genau so an.
{ settings, ... }:
{
  disko.devices.disk.main = {
    type = "disk";
    device = settings.disk;
    content = {
      type = "gpt";
      partitions = {
        # Startpartition für UEFI
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        # Der ganze Rest: System und alle App-Daten unter /var/lib
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
