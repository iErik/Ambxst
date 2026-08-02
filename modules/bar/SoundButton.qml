pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.widgets.dashboard.controls
import qs.config

Item {
    id: root

    required property var bar

    property bool vertical: bar.orientation === "vertical"
    property bool isHovered: false
    property bool layerEnabled: true

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    property bool popupOpen: soundPopup.isOpen

    readonly property bool shown: (Config.bar?.showSound ?? true) && Audio.available
    property bool clusterVisible: true
    readonly property bool inBar: shown && clusterVisible

    readonly property string buttonIcon: {
        const muted = Audio.sink?.audio?.muted ?? false;
        const vol = Audio.sink?.audio?.volume ?? 0;
        if (muted)
            return Icons.speakerSlash;
        if (vol <= 0)
            return Icons.speakerX;
        if (vol < 0.01)
            return Icons.speakerX;
        if (vol < 0.19)
            return Icons.speakerNone;
        if (vol < 0.49)
            return Icons.speakerLow;
        return Icons.speakerHigh;
    }

    readonly property string currentOutputName: Audio.friendlyDeviceName(Audio.sink)
    readonly property string currentInputName: Audio.friendlyDeviceName(Audio.source)
    readonly property string volumeLabel: {
        if (Audio.sink?.audio?.muted)
            return "Muted";
        const vol = Audio.sink?.audio?.volume ?? 0;
        return Math.round(vol * 100) + "%";
    }

    visible: inBar
    opacity: inBar ? 1 : 0
    Layout.preferredWidth: inBar ? 36 : 0
    Layout.preferredHeight: inBar ? 36 : 0
    Layout.maximumWidth: inBar ? 36 : 0
    Layout.maximumHeight: inBar ? 36 : 0
    Layout.fillWidth: inBar && vertical
    Layout.fillHeight: inBar && !vertical

    Behavior on opacity {
        enabled: (Config.animDuration ?? 0) > 0
        NumberAnimation {
            duration: Config.animDuration ?? 0
            easing.type: Easing.OutQuart
        }
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    function openPopup() {
        soundPopup.open();
    }

    function closePopup() {
        if (soundPopup.isOpen)
            soundPopup.close();
    }

    onClusterVisibleChanged: {
        if (!clusterVisible)
            closePopup();
    }

    StyledRect {
        id: buttonBg
        variant: root.popupOpen ? "primary" : "bg"
        anchors.fill: parent
        enableShadow: root.layerEnabled
        visible: root.shown

        topLeftRadius: root.vertical ? root.startRadius : root.startRadius
        topRightRadius: root.vertical ? root.startRadius : root.endRadius
        bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
        bottomRightRadius: root.vertical ? root.endRadius : root.endRadius

        Rectangle {
            anchors.fill: parent
            color: Styling.srItem("overprimary")
            opacity: root.popupOpen ? 0 : (root.isHovered ? 0.25 : 0)
            radius: parent.radius ?? 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: root.buttonIcon
            font.family: Icons.font
            font.pixelSize: 18
            color: root.popupOpen ? buttonBg.item : Styling.srItem("overprimary")
            opacity: (Audio.sink?.audio?.muted ?? false) ? 0.55 : 1
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    Quickshell.execDetached(["pavucontrol"]);
                    return;
                }
                if (soundPopup.isOpen)
                    soundPopup.close();
                else
                    root.openPopup();
            }
        }

        StyledToolTip {
            show: root.isHovered && !root.popupOpen
            tooltipText: "Sound · " + root.currentOutputName + " · " + root.volumeLabel + "\nRight-click to open pavucontrol"
        }
    }

    BarPopup {
        id: soundPopup
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 12
        contentWidth: 300
        contentHeight: Math.min(420, popupColumn.implicitHeight + popupPadding * 2)

        ColumnLayout {
            id: popupColumn
            anchors.fill: parent
            spacing: 8

            // Status header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: root.buttonIcon
                    font.family: Icons.font
                    font.pixelSize: 18
                    color: Styling.srItem("overprimary")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: "Sound"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(0)
                        font.bold: true
                        color: Colors.overBackground
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.currentOutputName + " · " + root.volumeLabel
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            // Output devices
            Text {
                text: "Output"
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-1)
                font.weight: Font.Medium
                color: Colors.overSurfaceVariant
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(160, Math.max(40, outputList.contentHeight + 8))
                variant: "pane"
                clip: true

                ListView {
                    id: outputList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    spacing: 2
                    model: Audio.outputDevices
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: AudioDeviceItem {
                        required property var modelData
                        width: outputList.width
                        node: modelData
                        isOutput: true
                        isSelected: Audio.sink === modelData
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: outputList.count === 0
                        text: "No output devices"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            // Input devices
            Text {
                text: "Input"
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-1)
                font.weight: Font.Medium
                color: Colors.overSurfaceVariant
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(160, Math.max(40, inputList.contentHeight + 8))
                variant: "pane"
                clip: true

                ListView {
                    id: inputList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    spacing: 2
                    model: Audio.inputDevices
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: AudioDeviceItem {
                        required property var modelData
                        width: inputList.width
                        node: modelData
                        isOutput: false
                        isSelected: Audio.source === modelData
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: inputList.count === 0
                        text: "No input devices"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Click a device to switch · Right-click opens pavucontrol"
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }
    }
}
