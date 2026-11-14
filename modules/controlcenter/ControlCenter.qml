pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.modules.services
import qs.modules.components
import qs.modules.corners
import qs.modules.theme
import qs.modules.globals
import qs.modules.widgets.dashboard.controls
import qs.config

// Control Center: a panel attached to the right edge of the screen, styled
// like the notch (a styled surface masked by a body plus concave corner
// flares where it meets an edge). Holds the control center page and Settings.
Item {
    id: root

    required property var targetScreen

    readonly property var screenVisibilities: Visibilities.getForScreen(targetScreen.name)
    readonly property bool active: screenVisibilities ? screenVisibilities.controlcenter : false

    // Input region for the shell panel's mask.
    property alias hitbox: panel

    // ── Placement ───────────────────────────────────────────────────────
    readonly property var screenBar: Visibilities.bars[targetScreen.name] ?? null
    readonly property string barPosition: screenBar ? (screenBar.barPosition ?? "top") : "top"
    readonly property bool barShown: screenBar !== null && screenBar.visible && (screenBar.reveal ?? false)
    readonly property bool barFloating: Config.bar?.floating ?? true
    readonly property bool barContained: (Config.bar?.frameEnabled ?? false) && (Config.bar?.containBar ?? false)
    readonly property int frameInset: (Config.bar?.frameEnabled ?? false) ? (Config.bar?.frameThickness ?? 6) : 0
    readonly property int barExtent: barShown ? (screenBar.totalBarHeight ?? 0) : 0

    // The top of the panel meets an edge (a flush bar, the frame or the screen
    // edge) and curves out of it; below a floating bar it is a rounded corner.
    readonly property bool topAttached: !(barShown && barPosition === "top" && barFloating && !barContained)
    readonly property int topInset: {
        if (barShown && barPosition === "top")
            return barExtent + (topAttached ? 0 : 4);
        return frameInset;
    }
    readonly property bool bottomAttached: !(barShown && barPosition === "bottom")
    readonly property int bottomInset: {
        if (barShown && barPosition === "bottom")
            return barExtent + 4;
        return frameInset;
    }
    readonly property int rightInset: (barShown && barPosition === "right") ? barExtent : frameInset

    // Blend into a flush bar it hangs from; otherwise look like the notch.
    readonly property bool blendWithBar: barShown && barPosition === "top" && !barFloating && !barContained

    // ── Size ────────────────────────────────────────────────────────────
    readonly property bool onSettings: GlobalStates.controlCenterPage === "settings"
    property bool settingsVisited: onSettings
    onOnSettingsChanged: if (onSettings)
        settingsVisited = true
    readonly property int bodyWidth: onSettings ? 880 : 420
    readonly property int flareSize: Config.roundness > 0 ? Config.roundness + 4 : 0
    readonly property int cornerRadius: Config.roundness > 0 ? Config.roundness + 20 : 0

    onActiveChanged: {
        if (active) {
            panelFocus.forceActiveFocus();
        } else {
            controlsPage.reset();
        }
    }

    Item {
        id: panel
        width: root.bodyWidth + root.flareSize
        y: root.topInset
        height: Math.max(0, parent.height - root.topInset - root.bottomInset)
        x: root.active ? parent.width - root.rightInset - width : parent.width + 16
        visible: root.active || slideAnimation.running

        Behavior on x {
            enabled: Config.animDuration > 0
            NumberAnimation {
                id: slideAnimation
                duration: Config.animDuration
                easing.type: Easing.OutCubic
            }
        }

        Behavior on width {
            enabled: Config.animDuration > 0 && root.active
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutCubic
            }
        }

        // Clicks on the panel never reach the click-outside backdrop.
        MouseArea {
            anchors.fill: body
            acceptedButtons: Qt.AllButtons
            onPressed: mouse => {
                panelFocus.forceActiveFocus();
                mouse.accepted = true;
            }
        }

        // Surface, masked to body + flares.
        StyledRect {
            anchors.fill: parent
            variant: root.blendWithBar ? "barbg" : "bg"
            enableBorder: false
            animateRadius: false
            radius: 0
            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: panelMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }

        Item {
            id: panelMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.smooth: true

            // Flare curving out of the top edge (or the bar) into the body.
            RoundCorner {
                x: 0
                y: 0
                width: root.flareSize
                height: root.flareSize
                size: Math.max(1, root.flareSize)
                // opacity, not visible: inside the hidden mask layer a
                // RoundCorner that starts invisible never gets painted.
                opacity: root.topAttached ? 1 : 0
                corner: RoundCorner.CornerEnum.TopRight
                color: "white"
            }

            Rectangle {
                id: bodyMask
                x: root.flareSize
                width: parent.width - root.flareSize
                height: parent.height
                color: "white"
                topLeftRadius: root.topAttached ? 0 : root.cornerRadius
                bottomLeftRadius: root.bottomAttached ? 0 : root.cornerRadius
            }

            // Flare curving out of the bottom edge into the body.
            RoundCorner {
                x: 0
                y: parent.height - height
                width: root.flareSize
                height: root.flareSize
                size: Math.max(1, root.flareSize)
                opacity: root.bottomAttached ? 1 : 0
                corner: RoundCorner.CornerEnum.BottomRight
                color: "white"
            }
        }

        // ── Content ─────────────────────────────────────────────────────
        FocusScope {
            id: panelFocus
            anchors.fill: body
            focus: root.active

            Keys.onEscapePressed: event => {
                Visibilities.setActiveModule("");
                event.accepted = true;
            }
        }

        Item {
            id: body
            x: root.flareSize
            width: parent.width - root.flareSize
            height: parent.height

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                anchors.topMargin: root.topAttached ? 12 : 16
                anchors.bottomMargin: root.bottomAttached ? 12 : 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    SegmentedSwitch {
                        options: [
                            {
                                icon: Icons.faders,
                                label: "Control Center"
                            },
                            {
                                icon: Icons.gear,
                                label: "Settings"
                            }
                        ]
                        currentIndex: root.onSettings ? 1 : 0
                        buttonSize: 32
                        onIndexChanged: index => GlobalStates.controlCenterPage = index === 1 ? "settings" : "controls"
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledRect {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        variant: closeArea.containsMouse ? "focus" : "common"
                        radius: Styling.radius(-2)

                        Text {
                            anchors.centerIn: parent
                            text: Icons.cancel
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: parent.item
                        }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Visibilities.setActiveModule("")
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ControlCenterPage {
                        id: controlsPage
                        anchors.fill: parent
                        screen: root.targetScreen
                        visible: !root.onSettings
                    }

                    // Settings stays loaded once opened, so its state and
                    // search index survive switching pages.
                    Loader {
                        id: settingsLoader
                        anchors.fill: parent
                        active: root.settingsVisited
                        visible: root.onSettings
                        sourceComponent: SettingsTab {}
                        onVisibleChanged: {
                            if (visible && item && item.focusSearchInput)
                                Qt.callLater(() => item.focusSearchInput());
                        }
                        onLoaded: {
                            if (visible && item.focusSearchInput)
                                Qt.callLater(() => item.focusSearchInput());
                        }
                    }
                }
            }
        }
    }
}
