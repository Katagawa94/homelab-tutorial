{
  description = "Homelab auf einem ThinkPad mit NixOS (Kapitel 36)";

  inputs = {
    # Stabile NixOS-Version für den Server. Wechsel auf eine neue Version = diese Zeile ändern.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Hardware-Feinschliff für ThinkPads (TrackPoint, TLP, …)
    nixos-hardware.url = "github:NixOS/nixos-hardware";

    # Partitionen als Code: ersetzt das Klicken im Installer
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Verschlüsselte Secrets im Git (wie Sealed Secrets in Kapitel 12)
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nixos-hardware, disko, sops-nix, ... }:
    let
      settings = import ./thinkpad/settings.nix;
    in
    {
      nixosConfigurations.${settings.hostName} = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit settings; };
        modules = [
          nixos-hardware.nixosModules.${settings.hardwareModule}
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./thinkpad/hardware-configuration.nix
          ./thinkpad/disko.nix
          ./thinkpad/configuration.nix
          ./thinkpad/apps.nix
        ];
      };
    };
}
