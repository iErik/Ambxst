pragma Singleton
import QtQuick
import Quickshell

// Relative pointer motion from the compositor (zwp_relative_pointer_v1), via
// the Ambxst.Input plugin. Unlike absolute motion, it keeps arriving while the
// cursor is clamped at a screen edge, which is what lets EdgePressureGate
// measure a push against the edge.
//
// When the plugin isn't installed, `available` stays false and consumers fall
// back to their dwell timers.
Singleton {
    id: root

    readonly property bool available: bridge !== null && bridge.available
    signal moved(real dx, real dy, real unaccelDx, real unaccelDy)

    property var bridge: null

    onAvailableChanged: console.info("RelativePointerService: relative pointer", available ? "available" : "unavailable")

    Component.onCompleted: {
        const component = Qt.createComponent(Qt.resolvedUrl("input/RelativePointerBridge.qml"));
        if (component.status !== Component.Ready) {
            console.info("RelativePointerService: Ambxst.Input plugin not loaded, edge reveals use the dwell timer.", component.errorString().trim());
            return;
        }
        const obj = component.createObject(root);
        if (!obj)
            return;
        obj.moved.connect(root.moved);
        root.bridge = obj;
    }
}
