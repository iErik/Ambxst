pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import qs.modules.widgets.dashboard.widgets
import qs.modules.widgets.dashboard.controls
import qs.config

// The Control Center page: quick toggles, sliders, sound devices, power, and
// shortcuts. Wi-Fi, Bluetooth, NordVPN and pCloud open a detail view that
// slides over the page.
Item {
    id: root

    required property var screen

    // "", "wifi", "bluetooth", "nordvpn" or "pcloud"
    property string detail: ""

    function openDetail(name) {
        root.detail = name;
    }

    function closeDetail() {
        if (detailLoader.item && detailLoader.item.reset)
            detailLoader.item.reset();
        root.detail = "";
    }

    // Leaving the Control Center returns to the overview next time.
    function reset() {
        closeDetail();
        overview.contentY = 0;
    }

    readonly property var detailTitles: ({
            "wifi": "Wi-Fi",
            "bluetooth": "Bluetooth",
            "nordvpn": "NordVPN",
            "pcloud": "pCloud"
        })

    Component.onCompleted: BluetoothService.initialize()

    // Card helper: a pane with a small title.
    component Card: StyledRect {
        id: card
        property string title: ""
        default property alias content: cardColumn.data
        variant: "pane"
        radius: Styling.radius(4)
        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + 24

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                visible: card.title !== ""
                text: card.title
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-1)
                font.weight: Font.Medium
                color: Colors.overSurfaceVariant
            }
        }
    }

    // A toggle tile; a chevron (or right-click) opens its detail view.
    component Tile: ColumnLayout {
        id: tile
        required property string iconName
        required property bool isActive
        required property string label
        property string detailName: ""
        signal toggled
        spacing: 4

        ControlButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 56
            Layout.preferredHeight: 56
            iconName: tile.iconName
            isActive: tile.isActive
            tooltipText: tile.detailName !== "" ? tile.label + " · right-click for details" : tile.label
            onClicked: tile.toggled()
            onRightClicked: if (tile.detailName !== "")
                root.openDetail(tile.detailName)
            onLongPressed: if (tile.detailName !== "")
                root.openDetail(tile.detailName)
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 2

            Text {
                text: tile.label
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overBackground
                elide: Text.ElideRight
                Layout.maximumWidth: 72
            }

            Text {
                visible: tile.detailName !== ""
                text: Icons.caretRight
                font.family: Icons.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDetail(tile.detailName)
                }
            }
        }
    }

    // ── Overview ────────────────────────────────────────────────────────
    Flickable {
        id: overview
        anchors.fill: parent
        contentHeight: overviewColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: contentHeight > height

        opacity: root.detail === "" ? 1 : 0
        visible: opacity > 0
        transform: Translate {
            x: root.detail === "" ? 0 : -24
            Behavior on x {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration / 2
                easing.type: Easing.OutCubic
            }
        }

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: overviewColumn
            width: overview.width
            spacing: 8

            Card {
                title: "Quick Settings"

                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    rowSpacing: 10
                    columnSpacing: 4

                    Tile {
                        Layout.fillWidth: true
                        label: "Wi-Fi"
                        detailName: "wifi"
                        iconName: {
                            if (!NetworkService.wifiEnabled)
                                return Icons.wifiOff;
                            const strength = NetworkService.networkStrength;
                            if (strength === 0)
                                return Icons.wifiHigh;
                            if (strength < 25)
                                return Icons.wifiNone;
                            if (strength < 50)
                                return Icons.wifiLow;
                            if (strength < 75)
                                return Icons.wifiMedium;
                            return Icons.wifiHigh;
                        }
                        isActive: NetworkService.wifiEnabled
                        onToggled: NetworkService.toggleWifi()
                    }

                    Tile {
                        Layout.fillWidth: true
                        label: "Bluetooth"
                        detailName: "bluetooth"
                        iconName: {
                            if (!BluetoothService.enabled)
                                return Icons.bluetoothOff;
                            if (BluetoothService.connected)
                                return Icons.bluetoothConnected;
                            return Icons.bluetooth;
                        }
                        isActive: BluetoothService.enabled
                        onToggled: BluetoothService.toggle()
                    }

                    Tile {
                        Layout.fillWidth: true
                        visible: NordVpn.available
                        label: "NordVPN"
                        detailName: "nordvpn"
                        iconName: NordVpn.connected ? Icons.shieldCheck : Icons.shield
                        isActive: NordVpn.connected
                        onToggled: NordVpn.toggleConnection()
                    }

                    Tile {
                        Layout.fillWidth: true
                        visible: Pcloud.available
                        label: "pCloud"
                        detailName: "pcloud"
                        iconName: Pcloud.syncing ? Icons.cloudArrowUp : Icons.cloud
                        isActive: Pcloud.syncing
                        onToggled: root.openDetail("pcloud")
                    }

                    Tile {
                        Layout.fillWidth: true
                        label: "Night Light"
                        iconName: Icons.nightLight
                        isActive: NightLightService.active
                        onToggled: NightLightService.toggle()
                    }

                    Tile {
                        Layout.fillWidth: true
                        label: "Caffeine"
                        iconName: Icons.caffeine
                        isActive: CaffeineService.inhibit
                        onToggled: CaffeineService.toggleInhibit()
                    }

                    Tile {
                        Layout.fillWidth: true
                        label: "Game Mode"
                        iconName: Icons.gameMode
                        isActive: GameModeService.toggled
                        onToggled: GameModeService.toggle()
                    }
                }
            }

            Card {
                title: "Levels"

                SlidersSection {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    screen: root.screen
                }
            }

            Card {
                SoundSection {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                }
            }

            Card {
                title: "Power"

                PowerSection {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                }
            }

            Card {
                title: "Shortcuts"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            {
                                icon: Icons.magicWand,
                                label: "Presets",
                                module: "presets"
                            },
                            {
                                icon: Icons.toolbox,
                                label: "Tools",
                                module: "tools"
                            }
                        ]

                        StyledRect {
                            id: shortcut
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            variant: shortcutArea.containsMouse ? "focus" : "common"
                            radius: Styling.radius(0)

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: shortcut.modelData.icon
                                    font.family: Icons.font
                                    font.pixelSize: 18
                                    color: shortcut.item
                                }

                                Text {
                                    text: shortcut.modelData.label
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(0)
                                    color: shortcut.item
                                }
                            }

                            MouseArea {
                                id: shortcutArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Visibilities.setActiveModule(shortcut.modelData.module)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Detail view ─────────────────────────────────────────────────────
    Item {
        id: detailView
        anchors.fill: parent
        opacity: root.detail !== "" ? 1 : 0
        visible: opacity > 0
        transform: Translate {
            x: root.detail !== "" ? 0 : 24
            Behavior on x {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration / 2
                easing.type: Easing.OutCubic
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledRect {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    variant: backArea.containsMouse ? "focus" : "common"
                    radius: Styling.radius(-2)

                    Text {
                        anchors.centerIn: parent
                        text: Icons.caretLeft
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: parent.item
                    }

                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeDetail()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.detailTitles[root.detail] ?? ""
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(1)
                    font.bold: true
                    color: Colors.overBackground
                    elide: Text.ElideRight
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                variant: "pane"
                radius: Styling.radius(4)
                clip: true

                Loader {
                    id: detailLoader
                    anchors.fill: parent
                    anchors.margins: 12
                    active: root.detail !== ""
                    sourceComponent: {
                        switch (root.detail) {
                        case "wifi":
                            return wifiComponent;
                        case "bluetooth":
                            return bluetoothComponent;
                        case "nordvpn":
                            return nordVpnComponent;
                        case "pcloud":
                            return pcloudComponent;
                        default:
                            return null;
                        }
                    }
                    onLoaded: {
                        if (item && item.activate)
                            item.activate();
                    }
                }
            }
        }
    }

    Component {
        id: wifiComponent
        WifiPanel {}
    }

    Component {
        id: bluetoothComponent
        BluetoothPanel {}
    }

    Component {
        id: nordVpnComponent
        NordVpnPanel {}
    }

    Component {
        id: pcloudComponent
        PcloudPanel {}
    }
}
