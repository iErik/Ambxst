# Home Manager module for Ambxst
self: { pkgs, lib, config, ... }: let

  inherit (lib) mkOption mkIf types optionalString;
  inherit (lib.hm.dag) entryAfter;
  inherit (config.home) homeDirectory;

  cfg = config.dots.ambxst;

  # Where axctl writes the generated compositor config, and the literal
  # include line cli.sh uses (`ambxst install niri`) - kept identical so
  # both routes produce the same config.
  generatedKdl = "${homeDirectory}/.local/share/ambxst/niri.kdl";
  includeLine = ''include "~/.local/share/ambxst/niri.kdl"'';

  # Ambxst hosts its own autostart: CompositorTomlWriter emits
  # `exec-once = "ambxst"` into axctl.toml, which axctl renders back into
  # the generated KDL. Seeding the same line means the first login starts
  # the shell before it has ever had a chance to write that file.
  seedKdl = ''spawn-at-startup "sh" "-c" "ambxst"'';

in {
  options.dots.ambxst = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable the Ambxst shell";
    };

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.system}.default;
      defaultText = "self.packages.\${pkgs.system}.default";
      description = "The Ambxst package to use";
    };

    autostart = mkOption {
      type = types.bool;
      default = true;
      description =
        "Whether to seed the generated compositor config with a " +
        "spawn-at-startup entry, so Ambxst comes up on the first " +
        "login rather than needing to be started by hand once.";
    };

    niri = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description =
          "Whether to emit the KDL fragment that pulls Ambxst's " +
          "axctl-generated config into the Niri config.";
      };

      directory = mkOption {
        type = types.str;
        default = lib.attrByPath [ "dots" "niri" "directory" ] ".config/niri" config;
        defaultText = "config.dots.niri.directory, or \".config/niri\"";
        description =
          "Directory the ambxst.kdl fragment is written to, relative " +
          "to the user's home directory. Defaults to the dots.niri " +
          "checkout so the fragment lands next to setup.kdl instead " +
          "of going through the ~/.config/niri symlink.";
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Always written, empty when disabled, so an `include "ambxst.kdl"`
    # in the Niri config resolves either way (same trick dots.niri uses
    # for setup.kdl and wallpaper-keys.kdl).
    home.file."${cfg.niri.directory}/ambxst.kdl".text =
      optionalString cfg.niri.enable "${includeLine}\n";

    # Ambxst's config lives at ~/.config/ambxst/config/*.json and is
    # rewritten by its own settings UI, so it is deliberately left
    # unmanaged - cli.sh seeds it from assets/presets with `cp -n`.
    home.activation.ambxstBootstrap = mkIf cfg.niri.enable
      (entryAfter [ "writeBoundary" ] ''
        run mkdir -p "${homeDirectory}/.local/share/ambxst"

        if [ ! -e "${generatedKdl}" ]; then
          run echo ${lib.escapeShellArg (optionalString cfg.autostart seedKdl)} \
            > "${generatedKdl}"
        fi
      '');

    warnings = lib.optional config.gtk.enable ''
      dots.ambxst: Home Manager owns ~/.config/gtk-{3,4}.0/settings.ini as a
      read-only store symlink, so Ambxst's GtkGenerator cannot recolor GTK
      apps. Set gtk.enable = false to let Ambxst manage GTK theming.
    '';
  };
}
