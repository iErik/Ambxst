import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.config
import "../../../config/defaults/bar.js" as BarDefaults
import "../../../config/defaults/notch.js" as NotchDefaults
import "../../../config/defaults/dock.js" as DockDefaults
import "../../../config/defaults/theme.js" as ThemeDefaults
import "../../../config/defaults/compositor.js" as CompositorDefaults

// Large preview of the highlighted preset: its screenshot when it has one,
// otherwise a miniature drawn from its settings (PresetMockup).
Item {
    id: root

    // The preset object from PresetsService.presets, or null.
    property var preset: null
    property var targetScreen: null

    readonly property real screenW: targetScreen && targetScreen.width > 0 ? targetScreen.width : 1920
    readonly property real screenH: targetScreen && targetScreen.height > 0 ? targetScreen.height : 1080

    // --- Preset settings, merged over the defaults ----------------------------
    // Parsed files per preset path, so moving back and forth through the list
    // doesn't re-read anything.
    property var configCache: ({})
    property var configs: ({ bar: BarDefaults.data, notch: NotchDefaults.data, dock: DockDefaults.data, theme: ThemeDefaults.data, compositor: CompositorDefaults.data })

    function merged(defaults, overrides) {
        return Object.assign({}, defaults, overrides || {});
    }

    function applyConfigs(raw) {
        configs = {
            bar: merged(BarDefaults.data, raw.bar),
            notch: merged(NotchDefaults.data, raw.notch),
            dock: merged(DockDefaults.data, raw.dock),
            theme: merged(ThemeDefaults.data, raw.theme),
            compositor: merged(CompositorDefaults.data, raw.compositor)
        };
    }

    onPresetChanged: {
        if (!preset || !preset.path) {
            applyConfigs({});
            return;
        }
        const cached = configCache[preset.path];
        if (cached) {
            applyConfigs(cached);
        } else {
            loadDebounce.restart();
        }
    }

    // Arrowing through the list changes the selection quickly; only read the
    // files once it settles.
    Timer {
        id: loadDebounce
        interval: 60
        onTriggered: {
            if (root.preset && root.preset.path)
                root.readConfigs(root.preset.path);
        }
    }

    // One read at a time; the newest request wins once the current one exits.
    property string pendingReadPath: ""
    function readConfigs(path) {
        if (configReader.running) {
            pendingReadPath = path;
            return;
        }
        configReader.presetPath = path;
        configReader.running = true;
    }

    // Prints "<name>\t<json on one line>" for each settings file; a missing or
    // unreadable file prints {}.
    Process {
        id: configReader
        property string presetPath: ""
        running: false
        command: ["sh", "-c", "for f in bar notch dock theme compositor; do printf '%s\\t' \"$f\"; if [ -r \"$1/$f.json\" ]; then tr -d '\\n' < \"$1/$f.json\"; else printf '{}'; fi; echo; done", "sh", presetPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = {};
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    try {
                        raw[line.substring(0, tab)] = JSON.parse(line.substring(tab + 1));
                    } catch (e) {
                        raw[line.substring(0, tab)] = {};
                    }
                }
                const cache = Object.assign({}, root.configCache);
                cache[configReader.presetPath] = raw;
                root.configCache = cache;
                if (root.preset && root.preset.path === configReader.presetPath)
                    root.applyConfigs(raw);
            }
        }
        onExited: {
            const next = root.pendingReadPath;
            root.pendingReadPath = "";
            if (next && !root.configCache[next])
                Qt.callLater(() => root.readConfigs(next));
        }
    }

    // --- Screenshot ---------------------------------------------------------------
    // Only a file the service knows exists, so missing previews log nothing.
    // previewFiles changes after a capture, re-evaluating this.
    readonly property string imagePath: PresetsService.previewSourceFor(preset)
    readonly property bool hasScreenshot: imagePath !== "" && previewImage.status === Image.Ready

    // --- Desktop for the drawn preview ----------------------------------------------
    readonly property string wallpaperSource: {
        const wm = GlobalStates.wallpaperManager;
        if (!wm || !wm.currentWallpaper)
            return "";
        const path = wm.getLockscreenFramePath ? wm.getLockscreenFramePath(wm.currentWallpaper) : wm.currentWallpaper;
        if (!path)
            return "";
        return path.startsWith("file://") ? path : "file://" + path;
    }

    // --- Traits summary -----------------------------------------------------------
    readonly property string traits: {
        const b = configs.bar || {}, n = configs.notch || {}, d = configs.dock || {}, t = configs.theme || {};
        const parts = [];
        parts.push("Bar " + (b.position || "top") + (b.frameEnabled ? (b.containBar ? ", framed" : ", with frame") : ""));
        parts.push("Notch " + (n.theme || "default") + ((n.position || "top") === "bottom" ? ", bottom" : ""));
        if (d.enabled)
            parts.push("Dock " + (d.theme || "default") + (d.theme === "integrated" ? "" : ", " + (d.position || "bottom")));
        else
            parts.push("No dock");
        parts.push(t.lightMode ? "Light" : "Dark");
        return parts.join("  ·  ");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Preview box, fitted to the monitor's aspect ratio.
        Item {
            id: previewArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Nothing drawn for the preview may leave its box.
            clip: true

            readonly property real aspect: root.screenW / root.screenH
            readonly property real boxW: Math.min(width, height * aspect)
            readonly property real boxH: boxW / aspect

            StyledRect {
                id: previewFrame
                variant: "pane"
                anchors.centerIn: parent
                width: previewArea.boxW
                height: previewArea.boxH
                radius: Styling.radius(-2)
                animateRadius: false

                Image {
                    id: previewImage
                    anchors.fill: parent
                    anchors.margins: 4
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                    source: root.imagePath !== "" ? ("file://" + root.imagePath + "?v=" + PresetsService.previewRevision) : ""
                }

                PresetMockup {
                    anchors.fill: parent
                    anchors.margins: 4
                    visible: !root.hasScreenshot && root.preset !== null
                    bar: root.configs.bar
                    notch: root.configs.notch
                    dock: root.configs.dock
                    theme: root.configs.theme
                    compositor: root.configs.compositor
                    wallpaperSource: root.wallpaperSource
                    screenW: root.screenW
                    screenH: root.screenH
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.preset === null
                    text: "Select a preset to preview it"
                    color: Colors.overBackground
                    opacity: 0.6
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                }
            }
        }

        // Caption.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            visible: root.preset !== null

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.preset ? root.preset.name : ""
                    elide: Text.ElideRight
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(2)
                    font.bold: true
                }

                StyledRect {
                    variant: root.hasScreenshot ? "primary" : "common"
                    implicitWidth: tagText.implicitWidth + 16
                    implicitHeight: tagText.implicitHeight + 6
                    radius: Styling.radius(-4)
                    animateRadius: false
                    Text {
                        id: tagText
                        anchors.centerIn: parent
                        text: root.hasScreenshot ? "Screenshot" : "Drawn preview"
                        color: root.hasScreenshot ? Styling.srItem("primary") : Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.preset ? ((root.preset.isOfficial ? "Official" : "Custom") + "  ·  by " + (root.preset.author || "Unknown")) : ""
                elide: Text.ElideRight
                color: Colors.overBackground
                opacity: 0.7
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
            }

            Text {
                Layout.fillWidth: true
                text: root.traits
                elide: Text.ElideRight
                color: Colors.overBackground
                opacity: 0.7
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
            }
        }
    }
}
