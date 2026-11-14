# Ambxst.Input

A small QML plugin that exposes `zwp_relative_pointer_v1` motion to the shell as the
`RelativePointer` singleton (`available`, `moved(dx, dy, unaccelDx, unaccelDy)`).

Once the compositor clamps the cursor at a screen edge, absolute motion stops but
relative motion keeps arriving. `modules/components/EdgePressureGate.qml` uses that to
reveal the bar, notch and dock only after a deliberate push against the edge.

The plugin is optional. Without it, `RelativePointerService.available` is false and the
gates fall back to a dwell timer ("Reveal Delay" in settings).

## Building

Nix builds and installs it as part of the Ambxst package (`nix/packages/input-plugin.nix`),
or on its own with `nix build .#input-plugin`.

Elsewhere, it needs Qt 6.5+ (Core, Gui, Qml, WaylandClient), wayland-protocols and
pkg-config. **It must be built against the same Qt as Quickshell**, or it will fail to load.

```sh
cmake -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DAMBXST_QML_DIR=lib/qt6/qml
cmake --build build
sudo cmake --install build
```

Point `AMBXST_QML_DIR` at a directory on Quickshell's QML import path (or add the install
location to `QML_IMPORT_PATH`).
