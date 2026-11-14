// The only file that imports the Ambxst.Input C++ plugin. It is loaded by URL
// from RelativePointerService so that a missing plugin (non-Nix installs, or a
// dev run without the plugin on the QML import path) fails this component
// alone instead of taking the shell down with it.
import QtQuick
import Ambxst.Input

QtObject {
    id: bridge

    signal moved(real dx, real dy, real unaccelDx, real unaccelDy)
    readonly property bool available: RelativePointer.available

    property Connections pointerConnections: Connections {
        target: RelativePointer
        function onMoved(dx, dy, unaccelDx, unaccelDy) {
            bridge.moved(dx, dy, unaccelDx, unaccelDy);
        }
    }
}
