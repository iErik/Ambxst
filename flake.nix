{
  description = "Ambxst - An Axtremely customizable shell by Axenide";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    axctl = {
      url = "github:iErik/axctl/erik";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, axctl, ... }:
    let
      ambxstLib = import ./nix/lib.nix { inherit nixpkgs; };
      version = nixpkgs.lib.removeSuffix "\n" (builtins.readFile ./version);
    in {
      nixosModules.default = { pkgs, lib, ... }: {
        imports = [ ./nix/modules ];
        programs.ambxst.package = lib.mkDefault self.packages.${pkgs.system}.default;
      };

      homeManagerModules = {
        default = self.homeManagerModules.dots;
        dots = import ./nix/hm self;
      };

      packages = ambxstLib.forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          lib = nixpkgs.lib;

          Ambxst = import ./nix/packages {
            inherit pkgs lib self system axctl version;
          };
        in {
          default = Ambxst;
          Ambxst = Ambxst;
          input-plugin = import ./nix/packages/input-plugin.nix {
            inherit pkgs lib version;
          };
        }
      );

      devShells = ambxstLib.forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          Ambxst = self.packages.${system}.default;
        in {
          default = pkgs.mkShell {
            packages = [ Ambxst ];
            shellHook = ''
              export QML2_IMPORT_PATH="${Ambxst}/lib/qt-6/qml:$QML2_IMPORT_PATH"
              export QML_IMPORT_PATH="$QML2_IMPORT_PATH"
              echo "Ambxst dev environment loaded."
            '';
          };
        }
      );

      apps = ambxstLib.forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = nixpkgs.lib;
          Ambxst = self.packages.${system}.default;

          # GammaRay must be built against the exact Qt quickshell uses, so it
          # comes from the same pinned nixpkgs. The target is the ambxst
          # launcher script, from which GammaRay can't detect the Qt ABI, so
          # the probe is named explicitly (e.g. qt6_12-x86_64).
          qtMajorMinor = lib.versions.majorMinor pkgs.qt6.qtbase.version;
          gammarayProbe = "qt${lib.replaceStrings [ "." ] [ "_" ] qtMajorMinor}-${pkgs.stdenv.hostPlatform.parsed.cpu.name}";

          inspect = pkgs.writeShellScript "ambxst-inspect" ''
            # Only one shell instance may run: stop the current one first.
            ${Ambxst}/bin/ambxst quit >/dev/null 2>&1 || true
            sleep 1
            # Inspect mode: skip pre-building pages (GammaRay tracks every
            # object; the full warm-up overwhelms it).
            export AMBXST_INSPECT=1
            # Preload the probe into quickshell (through the launcher script)
            # and only listen on localhost: the probe can inspect and edit the
            # running shell.
            exec ${pkgs.gammaray}/bin/gammaray \
              --injector preload \
              --probe ${gammarayProbe} \
              --listen tcp://127.0.0.1 \
              ${Ambxst}/bin/ambxst "$@"
          '';
        in {
          default = {
            type = "app";
            program = "${Ambxst}/bin/ambxst";
          };

          # nix run .#inspect — run the shell under GammaRay (object tree,
          # live property editing, Qt Quick scene inspector).
          inspect = {
            type = "app";
            program = "${inspect}";
          };
        }
      );
    };
}
