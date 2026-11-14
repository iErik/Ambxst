import QtQuick
import qs.modules.services

// Decides when a hidden edge panel (bar, notch, dock) should reveal.
//
// The owner sets `armed` while the pointer sits at its screen edge and the
// panel is hidden and allowed to reveal. With relative pointer motion
// available, the gate adds up how far the pointer keeps pushing outward
// against the edge (unaccelerated units) and fires once that passes
// `threshold`. Pauses longer than `idleResetMs` reset the total, so a flick's
// overshoot can't add up across separate touches. Without relative motion it
// falls back to firing after resting at the edge for `dwellMs`.
QtObject {
    id: gate

    property bool armed: false
    // Which screen edge the panel hides behind: "top", "bottom", "left" or "right".
    property string edge: "top"
    // Raw push needed when relative motion is available. 0 fires on touch.
    property real threshold: 250
    // Fallback dwell when relative motion is unavailable. 0 fires on touch.
    property int dwellMs: 250
    property int idleResetMs: 150

    readonly property bool pressureMode: RelativePointerService.available
    property real accumulated: 0

    signal triggered()

    function fire() {
        accumulated = 0;
        idleTimer.stop();
        dwellTimer.stop();
        triggered();
    }

    function rearm() {
        accumulated = 0;
        idleTimer.stop();
        dwellTimer.stop();
        if (!armed)
            return;
        if (pressureMode ? threshold <= 0 : dwellMs <= 0) {
            fire();
            return;
        }
        if (!pressureMode)
            dwellTimer.start();
    }

    onArmedChanged: rearm()
    onPressureModeChanged: rearm()

    property Timer dwellTimer: Timer {
        interval: Math.max(gate.dwellMs, 1)
        repeat: false
        onTriggered: {
            if (gate.armed && !gate.pressureMode)
                gate.fire();
        }
    }

    property Timer idleTimer: Timer {
        interval: gate.idleResetMs
        repeat: false
        onTriggered: gate.accumulated = 0
    }

    property Connections motionConnections: Connections {
        target: RelativePointerService
        enabled: gate.armed && gate.pressureMode
        function onMoved(dx, dy, unaccelDx, unaccelDy) {
            let push;
            switch (gate.edge) {
            case "bottom":
                push = unaccelDy;
                break;
            case "left":
                push = -unaccelDx;
                break;
            case "right":
                push = unaccelDx;
                break;
            default:
                push = -unaccelDy;
            }
            if (push <= 0)
                return;
            gate.accumulated += push;
            if (gate.accumulated >= gate.threshold)
                gate.fire();
            else
                gate.idleTimer.restart();
        }
    }
}
