import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import qs.modules.theme
import qs.modules.components
import qs.config

StyledRect {
    variant: "bg"
    id: root

    // Hide when no tray items
    visible: hasItems

    topLeftRadius: root.vertical ? root.startRadius : root.startRadius
    topRightRadius: root.vertical ? root.startRadius : root.endRadius
    bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
    bottomRightRadius: root.vertical ? root.endRadius : root.endRadius

    required property var bar

    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    // Orientación derivada de la barra
    property bool vertical: bar.orientation === "vertical"

    // Hide completely when empty - check both orientations
    readonly property bool hasItems: rowRepeater.count > 0 || columnRepeater.count > 0

    readonly property bool collapsed: Config.bar?.trayCollapsed ?? false
    readonly property int toggleSize: 16
    readonly property int contentPadding: 8
    readonly property int contentSpacing: 8

    readonly property real itemsMainExtent: vertical ? columnItems.implicitHeight : rowItems.implicitWidth
    readonly property real itemsCrossExtent: vertical ? columnItems.implicitWidth : rowItems.implicitHeight
    readonly property real mainExtent: toggleSize + (collapsed ? 0 : contentSpacing + itemsMainExtent)
    // Keep pill cross-size from tray icons even while collapsed (items stay laid out, just clipped)
    readonly property real crossExtent: Math.max(toggleSize, itemsCrossExtent)
    readonly property int layoutSpacing: collapsed ? 0 : contentSpacing

    // Ajustes de tamaño dinámicos según orientación
    height: vertical ? implicitHeight : parent.height
    Layout.preferredWidth: hasItems ? (vertical ? crossExtent + contentPadding * 2 : mainExtent + contentPadding * 2) : 0
    Layout.preferredHeight: vertical ? (hasItems ? mainExtent + contentPadding * 2 : 0) : -1
    implicitWidth: hasItems ? (vertical ? crossExtent + contentPadding * 2 : mainExtent + contentPadding * 2) : 0
    implicitHeight: hasItems ? (vertical ? mainExtent + contentPadding * 2 : crossExtent + contentPadding * 2) : 0

    Behavior on Layout.preferredWidth {
        enabled: (Config.animDuration ?? 0) > 0
        NumberAnimation {
            duration: Config.animDuration ?? 0
            easing.type: Easing.OutQuart
        }
    }

    Behavior on Layout.preferredHeight {
        enabled: (Config.animDuration ?? 0) > 0 && root.vertical
        NumberAnimation {
            duration: Config.animDuration ?? 0
            easing.type: Easing.OutQuart
        }
    }

    Behavior on implicitWidth {
        enabled: (Config.animDuration ?? 0) > 0
        NumberAnimation {
            duration: Config.animDuration ?? 0
            easing.type: Easing.OutQuart
        }
    }

    Behavior on implicitHeight {
        enabled: (Config.animDuration ?? 0) > 0 && root.vertical
        NumberAnimation {
            duration: Config.animDuration ?? 0
            easing.type: Easing.OutQuart
        }
    }

    function toggleCollapsed() {
        if (!Config.bar)
            return;
        Config.bar.trayCollapsed = !root.collapsed;
    }

    component TrayToggle: MouseArea {
        id: toggleRoot

        property bool verticalLayout: false

        Layout.preferredWidth: root.toggleSize
        Layout.preferredHeight: root.toggleSize
        Layout.alignment: verticalLayout ? Qt.AlignHCenter : Qt.AlignVCenter
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true

        onClicked: root.toggleCollapsed()

        StyledToolTip {
            show: toggleRoot.containsMouse
            tooltipText: root.collapsed ? "Expand tray" : "Collapse tray"
        }

        Text {
            anchors.centerIn: parent
            text: {
                if (toggleRoot.verticalLayout)
                    return root.collapsed ? Icons.caretDown : Icons.caretUp;
                return root.collapsed ? Icons.caretRight : Icons.caretLeft;
            }
            textFormat: Text.PlainText
            font.family: Icons.font
            font.pixelSize: 12
            color: Styling.srItem("overprimary")
            opacity: toggleRoot.containsMouse ? 1 : 0.75

            Behavior on opacity {
                enabled: (Config.animDuration ?? 0) > 0
                NumberAnimation {
                    duration: (Config.animDuration ?? 0) / 2
                }
            }
        }
    }

    RowLayout {
        id: rowLayout
        visible: !root.vertical
        anchors.fill: parent
        anchors.margins: root.contentPadding
        spacing: root.layoutSpacing

        TrayToggle {
            verticalLayout: false
        }

        Item {
            id: rowItemsClip
            clip: true
            Layout.fillHeight: true
            Layout.preferredWidth: root.collapsed ? 0 : rowItems.implicitWidth
            Layout.maximumWidth: root.collapsed ? 0 : rowItems.implicitWidth
            implicitHeight: rowItems.implicitHeight
            enabled: !root.collapsed

            Behavior on Layout.preferredWidth {
                enabled: (Config.animDuration ?? 0) > 0
                NumberAnimation {
                    duration: Config.animDuration ?? 0
                    easing.type: Easing.OutQuart
                }
            }

            Behavior on Layout.maximumWidth {
                enabled: (Config.animDuration ?? 0) > 0
                NumberAnimation {
                    duration: Config.animDuration ?? 0
                    easing.type: Easing.OutQuart
                }
            }

            RowLayout {
                id: rowItems
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: root.contentSpacing

                Repeater {
                    id: rowRepeater
                    model: SystemTray.items

                    SysTrayItem {
                        required property SystemTrayItem modelData
                        bar: root.bar
                        item: modelData
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: columnLayout
        visible: root.vertical
        anchors.fill: parent
        anchors.margins: root.contentPadding
        spacing: root.layoutSpacing

        TrayToggle {
            verticalLayout: true
        }

        Item {
            id: columnItemsClip
            clip: true
            Layout.fillWidth: true
            Layout.preferredHeight: root.collapsed ? 0 : columnItems.implicitHeight
            Layout.maximumHeight: root.collapsed ? 0 : columnItems.implicitHeight
            implicitWidth: columnItems.implicitWidth
            enabled: !root.collapsed

            Behavior on Layout.preferredHeight {
                enabled: (Config.animDuration ?? 0) > 0
                NumberAnimation {
                    duration: Config.animDuration ?? 0
                    easing.type: Easing.OutQuart
                }
            }

            Behavior on Layout.maximumHeight {
                enabled: (Config.animDuration ?? 0) > 0
                NumberAnimation {
                    duration: Config.animDuration ?? 0
                    easing.type: Easing.OutQuart
                }
            }

            ColumnLayout {
                id: columnItems
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: root.contentSpacing

                Repeater {
                    id: columnRepeater
                    model: SystemTray.items

                    SysTrayItem {
                        required property SystemTrayItem modelData
                        bar: root.bar
                        item: modelData
                    }
                }
            }
        }
    }
}
