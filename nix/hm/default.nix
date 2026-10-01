# Home Manager module for Ambxst
self: { pkgs, lib, config, ... }: let

  inherit (lib) mkOption mkIf types optionalString;
  inherit (lib.hm.dag) entryAfter;
  inherit (config.home) homeDirectory;

  cfg = config.dots.ambxst;

  # Where axctl writes the generated compositor configs.
  dataDir = "${homeDirectory}/.local/share/ambxst";

  # The lines below are kept byte-identical to the ones cli.sh writes
  # (`ambxst install niri` / `ambxst install hyprland`), so wiring the shell
  # up declaratively and wiring it up by hand produce the same config.
  niri = {
    generated = "${dataDir}/niri.kdl";
    pull = ''include "~/.local/share/ambxst/niri.kdl"'';
    # Ambxst hosts its own autostart: CompositorTomlWriter emits
    # `exec-once = "ambxst"` into axctl.toml, which axctl renders back into
    # the generated config. Seeding the same entry means the first login
    # starts the shell before it has ever had a chance to write that file.
    seed = ''spawn-at-startup "sh" "-c" "ambxst"'';
  };

  # Hyprland takes one of two config languages, and axctl writes both files.
  hyprlang = {
    generated = "${dataDir}/hyprland.conf";
    pull = "source = ~/.local/share/ambxst/hyprland.conf";
    seed = "exec-once = ambxst";
  };

  lua = {
    generated = "${dataDir}/hyprland.lua";
    pull = ''loadfile(os.getenv("HOME") .. "/.local/share/ambxst/hyprland.lua")()'';
    seed = ''
      hl.on("hyprland.start", function()
          hl.exec_cmd("ambxst")
      end)
    '';
  };

  # Hyprland prefers hyprland.lua and ignores hyprland.conf entirely when it
  # is present, so follow whichever language the Hyprland module is set to
  # emit rather than guessing.
  hyprModule = lib.attrByPath [ "wayland" "windowManager" "hyprland" ] { } config;
  hyprEnabled = hyprModule.enable or false;
  hypr = if (hyprModule.configType or "hyprlang") == "lua" then lua else hyprlang;

  # Drop the autostart entry into the generated config if axctl has not
  # written one yet. Left alone afterwards — the shell owns that file.
  seedGenerated = enable: target: optionalString (enable && cfg.autostart) ''
    if [ ! -e "${target.generated}" ]; then
      run echo ${lib.escapeShellArg target.seed} > "${target.generated}"
    fi
  '';

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
        "startup entry, so Ambxst comes up on the first login rather " +
        "than needing to be started by hand once.";
    };

    niri = {
      enable = mkOption {
        type = types.bool;
        default = lib.attrByPath [ "dots" "niri" "enable" ] true config;
        defaultText = "config.dots.niri.enable, or true";
        description =
          "Whether to wire Ambxst into the Niri config, so a Niri " +
          "session starts the shell. Defaults to following dots.niri.";
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

    hyprland = {
      enable = mkOption {
        type = types.bool;
        default = hyprEnabled;
        defaultText = "config.wayland.windowManager.hyprland.enable";
        description = ''
          Whether to wire Ambxst into the Hyprland config, so a Hyprland
          session starts the shell. Defaults to following the Hyprland
          Home Manager module.

          This appends to `wayland.windowManager.hyprland.extraConfig`,
          which that module renders last — so where a key is bound on both
          sides, Ambxst wins. Bind it from Ambxst's own settings rather
          than from Hyprland if you need the other precedence.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Always written, empty when disabled, so an `include "ambxst.kdl"`
    # in the Niri config resolves either way (same trick dots.niri uses
    # for setup.kdl and wallpaper-keys.kdl).
    home.file."${cfg.niri.directory}/ambxst.kdl".text =
      optionalString cfg.niri.enable "${niri.pull}\n";

    # Hyprland's config is generated wholesale by its own Home Manager
    # module, so there is no fragment to drop beside it — the line goes in
    # through the option that module provides for exactly this.
    wayland.windowManager.hyprland.extraConfig =
      mkIf cfg.hyprland.enable "\n${hypr.pull}\n";

    # Ambxst's own config lives at ~/.config/ambxst/config/*.json and is
    # rewritten by its settings UI, so it is deliberately left unmanaged —
    # cli.sh seeds it from assets/presets with `cp -n`.
    home.activation.ambxstBootstrap = entryAfter [ "writeBoundary" ] ''
      run mkdir -p "${dataDir}"
      ${seedGenerated cfg.niri.enable niri}
      ${seedGenerated cfg.hyprland.enable hypr}
    '';

    warnings =
      lib.optional config.gtk.enable ''
        dots.ambxst: Home Manager owns ~/.config/gtk-{3,4}.0/settings.ini as a
        read-only store symlink, so Ambxst's GtkGenerator cannot recolor GTK
        apps. Set gtk.enable = false to let Ambxst manage GTK theming.
      ''
      ++ lib.optional (cfg.hyprland.enable && !hyprEnabled) ''
        dots.ambxst: hyprland.enable is set but
        wayland.windowManager.hyprland.enable is not, so nothing renders the
        config Ambxst is appending to and a Hyprland session will not start
        the shell. Enable that module, or set dots.ambxst.hyprland.enable =
        false and pull in ${hypr.generated} by hand.
      '';
  };
}
