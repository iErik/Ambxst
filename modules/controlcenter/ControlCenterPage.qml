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
        const loader = detailLoaderFor(root.detail);
        if (loader && loader.item && loader.item.reset)
            loader.item.reset();
        root.detail = "";
    }

    readonly property var detailNames: ["wifi", "bluetooth", "nordvpn", "pcloud"]

    function detailLoaderFor(name) {
        const i = root.detailNames.indexOf(name);
        return i >= 0 ? detailRepeater.itemAt(i) : null;
    }

    // Warm-up: build detail view `name` hidden; returns its Loader.
    function warmDetail(name) {
        const loader = detailLoaderFor(name);
        if (loader)
            loader.visited = true;
        return loader;
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

    // A toggle tile. Tiles with a detail view carry a small chevron badge on
    // the button's corner (click it, or right-click the tile, to open it).
    component Tile: ColumnLayout {
        id: tile
        required property string iconName
        required property bool isActive
        required property string label
        property string detailName: ""
        signal toggled
        spacing: 4
        Layout.fillWidth: true
        Layout.preferredWidth: 1

        ControlButton {
            id: tileButton
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            iconName: tile.iconName
            isActive: tile.isActive
            tooltipText: tile.detailName !== "" ? tile.label + " · right-click for details" : tile.label
            onClicked: tile.toggled()
            onRightClicked: if (tile.detailName !== "")
                root.openDetail(tile.detailName)
            onLongPressed: if (tile.detailName !== "")
                root.openDetail(tile.detailName)

            StyledRect {
                id: detailBadge
                visible: tile.detailName !== ""
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: -3
                width: 18
                height: 18
                radius: 9
                variant: badgeArea.containsMouse ? "focus" : "common"

                Text {
                    anchors.centerIn: parent
                    text: Icons.caretRight
                    font.family: Icons.font
                    font.pixelSize: 10
                    color: detailBadge.item
                }

                MouseArea {
                    id: badgeArea
                    anchors.fill: parent
                    anchors.margins: -3
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDetail(tile.detailName)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: tile.label
            font.family: Styling.defaultFont
            font.pixelSize: Styling.fontSize(-3)
            color: Colors.overBackground
            elide: Text.ElideRight
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

                // One row; tiles share the width equally.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Tile {
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
                        visible: NordVpn.available
                        label: "NordVPN"
                        detailName: "nordvpn"
                        iconName: NordVpn.connected ? Icons.shieldCheck : Icons.shield
                        isActive: NordVpn.connected
                        onToggled: NordVpn.toggleConnection()
                    }

                    Tile {
                        visible: Pcloud.available
                        label: "pCloud"
                        detailName: "pcloud"
                        iconName: Pcloud.syncing ? Icons.cloudArrowUp : Icons.cloud
                        isActive: Pcloud.syncing
                        onToggled: root.openDetail("pcloud")
                    }

                    Tile {
                        label: "Night Light"
                        iconName: Icons.nightLight
                        isActive: NightLightService.active
                        onToggled: NightLightService.toggle()
                    }

                    Tile {
                        label: "Caffeine"
                        iconName: Icons.caffeine
                        isActive: CaffeineService.inhibit
                        onToggled: CaffeineService.toggleInhibit()
                    }

                    Tile {
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
                    id: backButton
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    variant: backArea.containsMouse ? "focus" : "common"
                    radius: Styling.radius(-2)

                    Text {
                        anchors.centerIn: parent
                        text: Icons.caretLeft
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: backButton.item
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

                // One Loader per detail view, built once (by warm-up or on
                // first open) and then kept: opening a view only shows it.
                Repeater {
                    id: detailRepeater
                    model: root.detailNames

                    Loader {
                        id: detailLoader
                        required property string modelData
                        readonly property bool current: root.detail === modelData
                        property bool visited: current
                        onCurrentChanged: {
                            if (current) {
                                visited = true;
                                if (item && item.activate)
                                    item.activate();
                            }
                        }

                        anchors.fill: parent
                        anchors.margins: 12
                        active: visited
                        asynchronous: true
                        visible: current
                        sourceComponent: {
                            switch (modelData) {
                            case "wifi":
                                return wifiComponent;
                            case "bluetooth":
                                return bluetoothComponent;
                            case "nordvpn":
                                return nordVpnComponent;
                            default:
                                return pcloudComponent;
                            }
                        }
                        onLoaded: {
                            if (current && item && item.activate)
                                item.activate();
                        }
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
