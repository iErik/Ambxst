pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.widgets.dashboard.controls
import qs.modules.bar
import qs.modules.globals
import qs.config

// Output and input device pickers (formerly the bar Sound popup).
Item {
    id: root

    implicitHeight: popupColumn.implicitHeight

    readonly property string currentOutputName: Audio.friendlyDeviceName(Audio.sink)

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

    readonly property string volumeLabel: {
        if (Audio.sink?.audio?.muted)
            return "Muted";
        const vol = Audio.sink?.audio?.volume ?? 0;
        return Math.round(vol * 100) + "%";
    }
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
