import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.theme
import qs.config

Item {
    id: root

    property bool hasFullscreenWindow: false
    // Edge a flush bar covers ("top", "bottom", "left", "right" or ""): its two
    // corners are left to the bar.
    property string flushBarEdge: ""

    readonly property bool frameEnabled: Config.bar?.frameEnabled ?? false
    readonly property int thickness: {
        const value = Config.bar?.frameThickness;
        if (typeof value !== "number")
            return 6;
        return Math.max(1, Math.min(Math.round(value), 40));
    }

    readonly property int cornerSize: Styling.radius(4) + (frameEnabled ? thickness : 0)

    RoundCorner {
        id: topLeft
        visible: !root.hasFullscreenWindow && root.flushBarEdge !== "top" && root.flushBarEdge !== "left"
        size: root.cornerSize
        anchors.left: root.left
        anchors.top: root.top
        corner: RoundCorner.CornerEnum.TopLeft
    }

    RoundCorner {
        id: topRight
        visible: !root.hasFullscreenWindow && root.flushBarEdge !== "top" && root.flushBarEdge !== "right"
        size: root.cornerSize
        anchors.right: root.right
        anchors.top: root.top
        corner: RoundCorner.CornerEnum.TopRight
    }

    RoundCorner {
        id: bottomLeft
        visible: !root.hasFullscreenWindow && root.flushBarEdge !== "bottom" && root.flushBarEdge !== "left"
        size: root.cornerSize
        anchors.left: root.left
        anchors.bottom: root.bottom
        corner: RoundCorner.CornerEnum.BottomLeft
    }

    RoundCorner {
        id: bottomRight
        visible: !root.hasFullscreenWindow && root.flushBarEdge !== "bottom" && root.flushBarEdge !== "right"
        size: root.cornerSize
        anchors.right: root.right
        anchors.bottom: root.bottom
        corner: RoundCorner.CornerEnum.BottomRight
    }
}
