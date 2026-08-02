pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.services
import qs.modules.components
import qs.modules.theme
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

    property bool popupOpen: wifiPopup.isOpen
    property string searchQuery: ""
    property var passwordTarget: null

    readonly property bool shown: (Config.bar?.showWifi ?? true) && NetworkService.available
    property bool clusterVisible: true
    readonly property bool inBar: shown && clusterVisible

    readonly property string buttonIcon: {
        if (!NetworkService.wifiEnabled)
            return Icons.wifiOff;
        if (NetworkService.wifiConnecting)
            return Icons.wifiMedium;
        if (NetworkService.wifi || NetworkService.wifiStatus === "connected" || NetworkService.wifiStatus === "limited")
            return NetworkService.wifiIconForStrength(NetworkService.networkStrength || 100);
        return Icons.wifiNone;
    }

    readonly property var filteredNetworks: {
        const q = (root.searchQuery || "").trim().toLowerCase();
        const source = NetworkService.friendlyWifiNetworks || [];
        if (!q)
            return source;
        return source.filter(n => {
            const ssid = (n?.ssid ?? "").toLowerCase();
            return ssid.includes(q);
        });
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
        NetworkService.rescanWifi();
        wifiPopup.open();
        Qt.callLater(() => searchField.focusInput());
    }

    function closePopup() {
        if (wifiPopup.isOpen)
            wifiPopup.close();
    }

    onClusterVisibleChanged: {
        if (!clusterVisible)
            closePopup();
    }

    function resetPasswordUi() {
        root.passwordTarget = null;
        passwordField.clear();
        NetworkService.clearPasswordPrompts();
    }

    function selectNetwork(network) {
        if (!network || NetworkService.wifiConnectTarget)
            return;

        if (network.active) {
            root.passwordTarget = null;
            passwordField.clear();
            return;
        }

        root.passwordTarget = network;
        if (network.askingPassword) {
            Qt.callLater(() => passwordField.focusInput());
            return;
        }

        passwordField.clear();
        NetworkService.connectToWifiNetwork(network);
    }

    function submitPassword() {
        const network = root.passwordTarget;
        const pass = passwordField.text || "";
        if (!network || pass.length === 0 || NetworkService.wifiConnecting)
            return;
        NetworkService.connectWithPassword(network, pass);
        passwordField.clear();
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
            opacity: NetworkService.wifiConnecting ? 0.55 : (NetworkService.wifiEnabled ? 1 : 0.55)
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    NetworkService.toggleWifi();
                    return;
                }
                if (wifiPopup.isOpen)
                    wifiPopup.close();
                else
                    root.openPopup();
            }
        }

        StyledToolTip {
            show: root.isHovered && !root.popupOpen
            tooltipText: "Wi-Fi · " + NetworkService.statusSummary + "\nRight-click to toggle radio"
        }
    }

    BarPopup {
        id: wifiPopup
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 12
        contentWidth: 300
        contentHeight: 380

        onClosedExternally: {
            root.searchQuery = "";
            searchField.clear();
            root.resetPasswordUi();
        }

        ColumnLayout {
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
                        text: {
                            if (!NetworkService.wifiEnabled)
                                return "Wi-Fi Off";
                            if (NetworkService.wifiConnecting)
                                return "Connecting...";
                            if (NetworkService.wifiStatus === "limited")
                                return "Limited";
                            if (NetworkService.wifi || NetworkService.wifiStatus === "connected")
                                return "Connected";
                            return "Disconnected";
                        }
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(0)
                        font.bold: true
                        color: Colors.overBackground
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: (NetworkService.networkName || "").length > 0 && NetworkService.wifiEnabled
                        text: NetworkService.networkName
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                // Radio toggle
                StyledRect {
                    id: radioBtn
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    variant: NetworkService.wifiEnabled ? "primary" : "common"
                    property bool hovered: false

                    Text {
                        anchors.centerIn: parent
                        text: NetworkService.wifiEnabled ? Icons.wifiHigh : Icons.wifiOff
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: radioBtn.item
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: radioBtn.hovered = true
                        onExited: radioBtn.hovered = false
                        onClicked: NetworkService.toggleWifi()
                    }

                    StyledToolTip {
                        show: radioBtn.hovered
                        tooltipText: NetworkService.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
                    }
                }
            }

            // Disconnect / Refresh
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledRect {
                    id: disconnectBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    variant: "common"
                    visible: !!(NetworkService.active || NetworkService.wifi || NetworkService.wifiStatus === "connected")
                    property bool btnHovered: false
                    opacity: NetworkService.wifiConnecting ? 0.6 : 1

                    Text {
                        anchors.centerIn: parent
                        text: NetworkService.wifiConnecting ? "Working..." : "Disconnect"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(0)
                        font.bold: true
                        color: disconnectBtn.item
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: NetworkService.wifiConnecting ? Qt.BusyCursor : Qt.PointingHandCursor
                        onEntered: disconnectBtn.btnHovered = true
                        onExited: disconnectBtn.btnHovered = false
                        onClicked: {
                            if (!NetworkService.wifiConnecting)
                                NetworkService.disconnectWifiNetwork();
                        }
                    }
                }

                StyledRect {
                    id: refreshBtn
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    variant: "common"
                    property bool btnHovered: false
                    opacity: (NetworkService.wifiScanning || !NetworkService.wifiEnabled) ? 0.55 : 1

                    Text {
                        anchors.centerIn: parent
                        text: Icons.sync
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: refreshBtn.item
                        opacity: NetworkService.wifiScanning ? 0.55 : 1
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: refreshBtn.btnHovered = true
                        onExited: refreshBtn.btnHovered = false
                        onClicked: {
                            if (NetworkService.wifiEnabled)
                                NetworkService.rescanWifi();
                        }
                    }

                    StyledToolTip {
                        show: refreshBtn.btnHovered
                        tooltipText: "Rescan networks"
                    }
                }
            }

            SearchInput {
                id: searchField
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                iconText: Icons.magnifyingGlass
                placeholderText: "Search networks..."
                onSearchTextChanged: text => {
                    root.searchQuery = text;
                }
            }

            // Password / connecting status for the selected network
            StyledRect {
                id: passwordPane
                Layout.fillWidth: true
                Layout.preferredHeight: passwordCol.implicitHeight + 16
                variant: "pane"
                visible: {
                    const target = root.passwordTarget;
                    if (!target)
                        return false;
                    if (target.askingPassword)
                        return true;
                    return NetworkService.wifiConnectTarget === target;
                }

                readonly property bool needsPassword: !!(root.passwordTarget?.askingPassword)

                ColumnLayout {
                    id: passwordCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: {
                            const ssid = root.passwordTarget?.ssid || "network";
                            if (passwordPane.needsPassword)
                                return "Password for " + ssid;
                            return "Connecting to " + ssid;
                        }
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        font.bold: true
                        color: Colors.overBackground
                        elide: Text.ElideRight
                    }

                    SearchInput {
                        id: passwordField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        visible: passwordPane.needsPassword
                        placeholderText: "Enter password..."
                        passwordMode: true
                        iconText: Icons.lock
                        onAccepted: root.submitPassword()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: passwordField.visible

                        Item {
                            Layout.fillWidth: true
                        }

                        StyledRect {
                            id: connectPassBtn
                            Layout.preferredWidth: 96
                            Layout.preferredHeight: 32
                            variant: "primary"
                            opacity: NetworkService.wifiConnectTarget || (passwordField.text || "").length === 0 ? 0.55 : 1

                            Text {
                                anchors.centerIn: parent
                                text: NetworkService.wifiConnectTarget ? "..." : "Connect"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.bold: true
                                color: connectPassBtn.item
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.submitPassword()
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !passwordField.visible
                        text: "Using saved credentials if available..."
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            // Network list
            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                variant: "pane"
                clip: true

                ListView {
                    id: networkList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    spacing: 2
                    model: root.filteredNetworks
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: StyledRect {
                        id: netItem
                        required property var modelData
                        required property int index

                        width: networkList.width
                        height: 36
                        variant: {
                            if (modelData?.active)
                                return "focus";
                            if (netItem.hovered || root.passwordTarget === modelData)
                                return "focus";
                            return "common";
                        }
                        property bool hovered: false

                        readonly property var network: modelData
                        readonly property string ssid: network?.ssid ?? ""
                        readonly property bool isActive: network?.active ?? false
                        readonly property bool isSecure: network?.isSecure ?? false
                        readonly property int strength: network?.strength ?? 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 8

                            Item {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22

                                Text {
                                    anchors.centerIn: parent
                                    text: NetworkService.wifiIconForStrength(netItem.strength)
                                    font.family: Icons.font
                                    font.pixelSize: 16
                                    color: netItem.isActive ? Styling.srItem("overprimary") : Colors.overBackground
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: -2
                                    visible: netItem.isSecure
                                    text: Icons.lock
                                    font.family: Icons.font
                                    font.pixelSize: 9
                                    color: Colors.overSurfaceVariant
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: netItem.ssid || "Hidden"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.bold: netItem.isActive
                                color: Colors.overBackground
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: network?.is5GHz ?? false
                                text: "5G"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-3)
                                font.bold: true
                                color: Colors.overSurfaceVariant
                            }

                            Text {
                                visible: netItem.isActive
                                text: Icons.circle
                                font.family: Icons.font
                                font.pixelSize: 10
                                color: Styling.srItem("overprimary")
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: NetworkService.wifiConnecting ? Qt.BusyCursor : Qt.PointingHandCursor
                            onEntered: netItem.hovered = true
                            onExited: netItem.hovered = false
                            onClicked: {
                                if (!NetworkService.wifiEnabled || NetworkService.wifiConnecting)
                                    return;
                                if (netItem.isActive) {
                                    NetworkService.disconnectWifiNetwork();
                                    return;
                                }
                                root.selectNetwork(netItem.network);
                                if (netItem.network?.askingPassword)
                                    Qt.callLater(() => passwordField.focusInput());
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: networkList.count === 0
                        text: {
                            if (!NetworkService.wifiEnabled)
                                return "Wi-Fi is disabled";
                            if (NetworkService.wifiScanning)
                                return "Scanning...";
                            if (root.searchQuery)
                                return "No matches";
                            return "No networks found";
                        }
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Click to connect · secured networks may ask for a password"
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }
    }

    Connections {
        target: wifiPopup
        function onIsOpenChanged() {
            if (!wifiPopup.isOpen) {
                root.searchQuery = "";
                searchField.clear();
                root.resetPasswordUi();
            }
        }
    }

    Connections {
        target: NetworkService
        function onWifiConnectTargetChanged() {
            if (NetworkService.wifiConnectTarget)
                root.passwordTarget = NetworkService.wifiConnectTarget;
        }
        function onActiveChanged() {
            const active = NetworkService.active;
            if (active && root.passwordTarget && active.ssid === root.passwordTarget.ssid)
                root.resetPasswordUi();
        }
    }

    // Reveal password field when NM reports secrets are required
    Connections {
        target: root.passwordTarget
        enabled: root.passwordTarget !== null
        function onAskingPasswordChanged() {
            if (root.passwordTarget?.askingPassword)
                Qt.callLater(() => passwordField.focusInput());
        }
    }
}
