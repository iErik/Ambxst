# Ambxst.Input QML module: exposes zwp_relative_pointer_v1 motion to the shell
# so edge reveals can react to real pressure against the screen edge.
#
# Built from the same `pkgs` as quickshell on purpose: the plugin links
# QtWaylandClient, and a Qt version mismatch would make it fail to load.
{ pkgs, lib, version }:

pkgs.stdenv.mkDerivation {
  pname = "ambxst-input-plugin";
  inherit version;

  src = lib.cleanSource ../../plugins/input;

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    pkg-config
    wayland-scanner
  ];

  buildInputs = with pkgs; [
    qt6.qtbase
    qt6.qtdeclarative
    wayland
    wayland-protocols
  ];

  cmakeFlags = [ "-DAMBXST_QML_DIR=lib/qt-6/qml" ];

  # A QML plugin, not an application: nothing to wrap.
  dontWrapQtApps = true;
}
