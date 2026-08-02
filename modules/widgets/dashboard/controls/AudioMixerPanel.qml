pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    property bool showOutput: true  // true = output, false = input

    // Scrollable content - fills entire width for scroll/drag
    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: contentColumn.implicitHeight
        clip: true

        ColumnLayout {
            id: contentColumn
            width: flickable.width
            spacing: 8

            // Header wrapper
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titlebar.height

                PanelTitlebar {
                    id: titlebar
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    title: "Sound"

                    actions: [
                        {
                            icon: Audio.protectionEnabled ? Icons.shieldCheck : Icons.shield,
                            tooltip: Audio.protectionEnabled ? "Volume protection enabled" : "Volume protection disabled",
                            onClicked: function () {
                                Audio.setProtectionEnabled(!Audio.protectionEnabled);
                            }
                        },
                        {
                            icon: Icons.popOpen,
                            tooltip: "Open PipeWire Volume Control",
                            onClicked: function () {
                                Quickshell.execDetached(["pavucontrol"]);
                            }
                        }
                    ]

                    // Output/Input toggle buttons
                    RowLayout {
                        spacing: 4

                        // Output Button
                        StyledRect {
                            id: outputBtn
                            property bool isSelected: root.showOutput
                            property bool isHovered: false

                            variant: isSelected ? "primary" : (isHovered ? "focus" : "common")
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: outputContent.width + 24
                            radius: isSelected ? Styling.radius(-4) : Styling.radius(0)

                            Row {
                                id: outputContent
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: Icons.speakerHigh
                                    font.family: Icons.font
                                    font.pixelSize: 14
                                    color: outputBtn.item
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "Output"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.Medium
                                    color: outputBtn.item
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: outputBtn.isHovered = true
                                onExited: outputBtn.isHovered = false
                                onClicked: root.showOutput = true
                            }
                        }

                        // Input Button
                        StyledRect {
                            id: inputBtn
                            property bool isSelected: !root.showOutput
                            property bool isHovered: false

                            variant: isSelected ? "primary" : (isHovered ? "focus" : "common")
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: inputContent.width + 24
                            radius: isSelected ? Styling.radius(-4) : Styling.radius(0)

                            Row {
                                id: inputContent
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: Icons.mic
                                    font.family: Icons.font
                                    font.pixelSize: 14
                                    color: inputBtn.item
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "Input"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.Medium
                                    color: inputBtn.item
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: inputBtn.isHovered = true
                                onExited: inputBtn.isHovered = false
                                onClicked: root.showOutput = false
                            }
                        }
                    }
                }
            }

            // Content wrapper - centered
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: innerContent.implicitHeight

                ColumnLayout {
                    id: innerContent
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    // Section: Devices
                    Text {
                        text: root.showOutput ? "Output Device" : "Input Device"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overSurfaceVariant
                    }

                    // Device list
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: root.showOutput ? Audio.outputDevices : Audio.inputDevices

                            delegate: AudioDeviceItem {
                                required property var modelData
                                Layout.fillWidth: true
                                node: modelData
                                isOutput: root.showOutput
                                isSelected: (root.showOutput ? Audio.sink : Audio.source) === modelData
                            }
                        }
                    }

                    // Separator
                    Separator {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 2
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                    }

                    // Section: Volume Mixer
                    Text {
                        text: "Volume Mixer"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overSurfaceVariant
                    }

                    // Over-amplification toggle (output volume above 100%)
                    // Toggle is anchors.right on the pane — RowLayout trailing cells left a large
                    // visual gap even with rightMargin:0 (StyledRect/pane has no content padding).
                    StyledRect {
                        id: overAmpRow
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        variant: "pane"
                        radius: Styling.radius(-4)

                        // Custom pill — absolute right pin (matches AudioDeviceItem / Wifi 12px inset)
                        Item {
                            id: overAmpToggle
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40
                            height: 20

                            readonly property bool checked: Config.audio?.overAmplification ?? false

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: overAmpToggle.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                                border.color: overAmpToggle.checked ? Styling.srItem("overprimary") : Colors.outline

                                Behavior on color {
                                    enabled: Config.animDuration > 0
                                    ColorAnimation {
                                        duration: Config.animDuration / 2
                                    }
                                }

                                Rectangle {
                                    x: overAmpToggle.checked ? parent.width - width - 2 : 2
                                    y: 2
                                    width: parent.height - 4
                                    height: width
                                    radius: width / 2
                                    color: overAmpToggle.checked ? Colors.background : Colors.overSurfaceVariant

                                    Behavior on x {
                                        enabled: Config.animDuration > 0
                                        NumberAnimation {
                                            duration: Config.animDuration / 2
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Audio.setOverAmplification(!overAmpToggle.checked)
                            }
                        }

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.right: overAmpToggle.left
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: "Over-amplification"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overBackground
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Allow output volume up to 150%"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Main volume control
                    AudioVolumeEntry {
                        Layout.fillWidth: true
                        node: root.showOutput ? Audio.sink : Audio.source
                        icon: root.showOutput ? Icons.speakerHigh : Icons.mic
                        isMainDevice: true
                    }

                    // App volume controls
                    Repeater {
                        model: root.showOutput ? Audio.outputAppNodes : Audio.inputAppNodes

                        delegate: AudioVolumeEntry {
                            required property var modelData
                            Layout.fillWidth: true
                            node: modelData
                            isMainDevice: false
                        }
                    }

                    // Empty state for apps
                    Text {
                        visible: (root.showOutput ? Audio.outputAppNodes : Audio.inputAppNodes).length === 0
                        text: "No applications using audio"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.outline
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 16
                    }
                }
            }
        }
    }
}
