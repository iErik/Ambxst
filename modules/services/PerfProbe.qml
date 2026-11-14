pragma Singleton
import QtQuick
import Quickshell

// Frame-time probe. Enabled with AMBXST_PERF=1 in the environment:
// logs frames longer than `slowFrameMs` with the current phase, and the
// duration of marked phases. Costs nothing when disabled.
Singleton {
    id: root

    readonly property bool enabled: Quickshell.env("AMBXST_PERF") === "1"
    readonly property real slowFrameMs: 24

    property string phase: "idle"
    property var _starts: ({})
    property real _hotUntil: 0

    function mark(name) {
        if (!enabled)
            return;
        _starts[name] = Date.now();
        phase = name;
        _hotUntil = Date.now() + 3000;
        frames.running = true;
        console.log("PERF start", name);
    }

    function done(name) {
        if (!enabled)
            return;
        const t = _starts[name];
        if (t !== undefined) {
            console.log("PERF done", name, (Date.now() - t) + "ms");
            delete _starts[name];
        }
    }

    // Keep watching while a module is open or for a while after a mark.
    FrameAnimation {
        id: frames
        running: false
        onTriggered: {
            const ms = frameTime * 1000;
            if (ms > root.slowFrameMs)
                console.log("PERF slow frame", ms.toFixed(1) + "ms", "[" + root.phase + "]");
            if (Date.now() > root._hotUntil && Visibilities.currentActiveModule === "") {
                running = false;
                root.phase = "idle";
            }
        }
    }

    Connections {
        target: Visibilities
        enabled: root.enabled
        function onCurrentActiveModuleChanged() {
            root.mark("module " + (Visibilities.currentActiveModule || "closed"));
        }
    }
}
