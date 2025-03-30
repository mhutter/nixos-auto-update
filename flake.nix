{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      pkg = pkgs.writeShellApplication {
        name = "nixos-auto-update";
        runtimeInputs = with pkgs; [
          cachix
          git
          nix
          uutils-findutils
        ];
        text = ''
          set -x

          # Clone the repository
          git clone --depth 1 -- https://github.com/mhutter/nix.git .

          # Populate fake secrets
          find . -type f -name '*.fake.nix' | \
          while read -r fake; do
            target="''${fake/%.fake.nix/.nix}"
            cp -v "$fake" "$target"
          done

          rm -vf ./result*

          for host in tera nxzt; do
            nix build .#nixosConfigurations."''${host}".config.system.build.toplevel --out-link "result-''${host}"
          done

          realpath ./result-*
        '';
      };

      containerArgs = {
        name = "nau";
        tag = "latest";
        contents = with pkgs; [
          bash
          uutils-coreutils-noprefix
          dockerTools.caCertificates

          (writeTextDir "etc/nix/nix.conf" ''
            #
            # Upstream settings
            #
            build-users-group = nixbld
            # sandbox = false
            # trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=

            #
            # Own settings
            #
            auto-optimise-store = false

            max-jobs = auto
            cores = 0
            download-buffer-size = 1073741824  # 1 GiB

            experimental-features = nix-command flakes
            require-sigs = true

            sandbox = true
            sandbox-fallback = false

            substituters = https://cache.nixos.org/
            trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= mhu.cachix.org-1:GFzDWQDpycEzXVNVk/ROC/vMu2Wl6AYTzDuiUq85OB0=
            trusted-substituters = https://mhu.cachix.org
          '')
        ];

        config = {
          Cmd = [ "${pkg}/bin/nixos-auto-update" ];
          WorkingDir = "/work";
          Volumes = { "/work" = { }; };
        };
      };
    in
    {
      packages."${system}" = {
        default = pkg;
        container = pkgs.dockerTools.buildLayeredImage containerArgs;
        containerStream = pkgs.dockerTools.streamLayeredImage containerArgs;
      };
    };
}
