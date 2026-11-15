pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    // Rows are created a couple per frame while the page is shown, behind
    // placeholders, so building the list never blocks a frame for long.
    // ("asynchronous" Loaders still built everything in one go here.)
    property int rowBudget: 0
    readonly property int rowsPerTick: 2

    Timer {
        id: rowTicker
        interval: 16
        repeat: true
        running: root.visible && root.rowBudget < networkList.count
        onTriggered: root.rowBudget += root.rowsPerTick
    }

    // A new model rebuilds every row: start the budget over.
    Connections {
        target: NetworkService
        function onFriendlyWifiNetworksChanged() {
            root.rowBudget = 0;
        }
    }

    // Pages can be built ahead of time while hidden (Control Center warm-up):
    // scan when the page is actually shown, not when it is created.
    Component.onCompleted: {
        if (visible)
            initialScanTimer.start();
    }
    onVisibleChanged: {
        if (visible)
            initialScanTimer.start();
    }

    Timer {
        id: initialScanTimer
        interval: 300
        repeat: false
        onTriggered: NetworkService.rescanWifi()
    }

    // Network list - fills entire width for scroll/drag
    ListView {
        id: networkList
        anchors.fill: parent
        clip: true
        spacing: 6
        // Rows are built as they scroll into view, not all up front.
        cacheBuffer: 200
        reuseItems: true

        model: NetworkService.friendlyWifiNetworks

        header: Item {
            width: networkList.width
            height: titlebar.height + 8

            PanelTitlebar {
                id: titlebar
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                title: "Wi-Fi"
                statusText: NetworkService.wifiConnecting ? "Connecting..." : (NetworkService.wifiStatus === "limited" ? "Limited" : "")
                statusColor: NetworkService.wifiStatus === "limited" ? Colors.warning : Styling.srItem("overprimary")
                showToggle: true
                toggleChecked: NetworkService.wifiStatus !== "disabled"

                actions: [
                    {
                        icon: Icons.globe,
                        tooltip: "Open captive portal",
                        enabled: NetworkService.wifiStatus === "limited",
                        onClicked: function () {
                            NetworkService.openPublicWifiPortal();
                        }
                    },
                    {
                        icon: Icons.popOpen,
                        tooltip: "Network settings",
                        onClicked: function () {
                            Quickshell.execDetached(["nm-connection-editor"]);
                        }
                    },
                    {
                        icon: Icons.sync,
                        tooltip: "Rescan networks",
                        enabled: NetworkService.wifiEnabled,
                        loading: NetworkService.wifiScanning || NetworkService.isUpdating,
                        onClicked: function () {
                            NetworkService.rescanWifi();
                        }
                    }
                ]

                onToggleChanged: checked => {
                    NetworkService.enableWifi(checked);
                    if (checked) {
                        NetworkService.rescanWifi();
                    }
                }
            }
        }

        // Rows are built asynchronously (spread over frames) behind a
        // placeholder of the collapsed row height: building them all in one
        // frame froze the shell for most of a second.
        delegate: Item {
            id: networkRow
            required property var modelData
            required property int index
            width: networkList.width
            height: networkLoader.item ? networkLoader.item.height : 48

            Loader {
                id: networkLoader
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                // Built a couple per frame (see rowTicker), not all at once.
                active: networkRow.index < root.rowBudget
                sourceComponent: WifiNetworkItem {
                    network: networkRow.modelData
                }
            }
        }

        // Empty state
        Text {
            anchors.centerIn: parent
            visible: networkList.count === 0 && !NetworkService.wifiScanning
            text: NetworkService.wifiEnabled ? "No networks found" : "Wi-Fi is disabled"
            font.family: Config.theme.font
            font.pixelSize: Styling.settingsFontSize(0)
            color: Colors.overSurfaceVariant
        }
    }
}
