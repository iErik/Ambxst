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

    property bool popupOpen: btPopup.isOpen
    property string searchQuery: ""
    property string pinInput: ""

    readonly property bool shown: (Config.bar?.showBluetooth ?? true) && BluetoothService.available

    readonly property string buttonIcon: {
        if (!BluetoothService.enabled)
            return Icons.bluetoothOff;
        if (BluetoothService.pairingRequest)
            return Icons.bluetooth;
        if (BluetoothService.connected)
            return Icons.bluetoothConnected;
        return Icons.bluetooth;
    }

    readonly property var filteredDevices: {
        const q = (root.searchQuery || "").trim().toLowerCase();
        const source = BluetoothService.friendlyDeviceList || [];
        if (!q)
            return source;
        return source.filter(d => {
            const name = (d?.name ?? "").toLowerCase();
            const address = (d?.address ?? "").toLowerCase();
            return name.includes(q) || address.includes(q);
        });
    }

    readonly property var pairingRequest: BluetoothService.pairingRequest
    readonly property bool pairingNeedsInput: {
        const req = root.pairingRequest;
        return !!(req && (req.kind === "pin" || req.kind === "passkey") && req.needsReply);
    }
    readonly property bool pairingNeedsConfirm: {
        const req = root.pairingRequest;
        return !!(req && (req.kind === "confirm" || req.kind === "authorize") && req.needsReply);
    }
    readonly property bool pairingDisplayOnly: {
        const req = root.pairingRequest;
        return !!(req && (req.kind === "display_pin" || req.kind === "display_passkey"));
    }

    visible: shown
    opacity: shown ? 1 : 0
    Layout.preferredWidth: shown ? 36 : 0
    Layout.preferredHeight: shown ? 36 : 0
    Layout.maximumWidth: shown ? 36 : 0
    Layout.maximumHeight: shown ? 36 : 0
    Layout.fillWidth: shown && vertical
    Layout.fillHeight: shown && !vertical

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
        BluetoothService.initialize();
        BluetoothService.ensureAgent();
        if (BluetoothService.enabled) {
            BluetoothService.updateDevices();
            BluetoothService.startDiscovery();
        }
        btPopup.open();
        Qt.callLater(() => {
            if (root.pairingNeedsInput)
                pinField.focusInput();
            else
                searchField.focusInput();
        });
    }

    function resetPairingUi() {
        root.pinInput = "";
        pinField.clear();
    }

    function selectDevice(device) {
        if (!device || !BluetoothService.enabled || device.connecting)
            return;

        if (device.connected) {
            device.disconnect();
            return;
        }

        BluetoothService.ensureAgent();
        device.connect();
    }

    function submitPin() {
        const code = root.pinInput || pinField.text || "";
        if (!root.pairingNeedsInput || code.trim().length === 0)
            return;
        BluetoothService.submitPairingCode(code);
        root.resetPairingUi();
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

        // Pairing attention ring
        Rectangle {
            anchors.fill: parent
            radius: parent.radius ?? 0
            color: "transparent"
            border.width: root.pairingRequest && !root.popupOpen ? 1.5 : 0
            border.color: Styling.srItem("overprimary")
            opacity: root.pairingRequest && !root.popupOpen ? 0.7 : 0
        }

        Text {
            anchors.centerIn: parent
            text: root.buttonIcon
            font.family: Icons.font
            font.pixelSize: 18
            color: root.popupOpen ? buttonBg.item : Styling.srItem("overprimary")
            opacity: BluetoothService.enabled ? 1 : 0.55
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    BluetoothService.toggle();
                    return;
                }
                if (btPopup.isOpen)
                    btPopup.close();
                else
                    root.openPopup();
            }
        }

        StyledToolTip {
            show: root.isHovered && !root.popupOpen
            tooltipText: {
                let tip = "Bluetooth · " + BluetoothService.statusSummary;
                if (root.pairingRequest)
                    tip += "\nPairing request pending";
                tip += "\nRight-click to toggle adapter";
                return tip;
            }
        }
    }

    BarPopup {
        id: btPopup
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 12
        contentWidth: 300
        contentHeight: 400

        onClosedExternally: {
            root.searchQuery = "";
            searchField.clear();
            root.resetPairingUi();
            BluetoothService.stopDiscovery();
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
                            if (!BluetoothService.enabled)
                                return "Bluetooth Off";
                            if (root.pairingRequest)
                                return "Pairing...";
                            if (BluetoothService.connected)
                                return "Connected";
                            if (BluetoothService.discovering)
                                return "Scanning...";
                            return "On";
                        }
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(0)
                        font.bold: true
                        color: Colors.overBackground
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: BluetoothService.enabled && (BluetoothService.connectedDevices > 0 || BluetoothService.discovering)
                        text: {
                            if (BluetoothService.discovering)
                                return "Looking for devices...";
                            if (BluetoothService.connectedDevices === 1)
                                return "1 device connected";
                            return BluetoothService.connectedDevices + " devices connected";
                        }
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                // Adapter toggle
                StyledRect {
                    id: radioBtn
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    variant: BluetoothService.enabled ? "primary" : "common"
                    property bool hovered: false

                    Text {
                        anchors.centerIn: parent
                        text: BluetoothService.enabled ? Icons.bluetooth : Icons.bluetoothOff
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
                        onClicked: BluetoothService.toggle()
                    }

                    StyledToolTip {
                        show: radioBtn.hovered
                        tooltipText: BluetoothService.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"
                    }
                }
            }

            // Scan
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledRect {
                    id: scanBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    variant: "common"
                    opacity: (!BluetoothService.enabled || BluetoothService.discovering) ? 0.6 : 1
                    property bool btnHovered: false

                    Text {
                        anchors.centerIn: parent
                        text: BluetoothService.discovering ? "Scanning..." : "Scan for devices"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(0)
                        font.bold: true
                        color: scanBtn.item
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: scanBtn.btnHovered = true
                        onExited: scanBtn.btnHovered = false
                        onClicked: {
                            if (BluetoothService.enabled && !BluetoothService.discovering)
                                BluetoothService.startDiscovery();
                        }
                    }
                }

                StyledRect {
                    id: refreshBtn
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    variant: "common"
                    property bool btnHovered: false
                    opacity: (!BluetoothService.enabled) ? 0.55 : 1

                    Text {
                        anchors.centerIn: parent
                        text: Icons.sync
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: refreshBtn.item
                        opacity: BluetoothService.isUpdating ? 0.55 : 1
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: refreshBtn.btnHovered = true
                        onExited: refreshBtn.btnHovered = false
                        onClicked: {
                            if (BluetoothService.enabled) {
                                BluetoothService.updateDevices();
                                BluetoothService.startDiscovery();
                            }
                        }
                    }

                    StyledToolTip {
                        show: refreshBtn.btnHovered
                        tooltipText: "Refresh / rescan"
                    }
                }
            }

            SearchInput {
                id: searchField
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                iconText: Icons.magnifyingGlass
                placeholderText: "Search devices..."
                onSearchTextChanged: text => {
                    root.searchQuery = text;
                }
            }

            // Pairing agent pane
            StyledRect {
                id: pairingPane
                Layout.fillWidth: true
                Layout.preferredHeight: pairingCol.implicitHeight + 16
                variant: "pane"
                visible: !!root.pairingRequest

                ColumnLayout {
                    id: pairingCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: {
                            const req = root.pairingRequest;
                            if (!req)
                                return "";
                            if (req.kind === "pin")
                                return "Enter PIN for " + (req.name || "device");
                            if (req.kind === "passkey")
                                return "Enter passkey for " + (req.name || "device");
                            if (req.kind === "confirm")
                                return "Confirm passkey for " + (req.name || "device");
                            if (req.kind === "authorize")
                                return "Authorize " + (req.name || "device");
                            if (req.kind === "display_pin")
                                return "Type this PIN on " + (req.name || "the device");
                            if (req.kind === "display_passkey")
                                return "Type this code on " + (req.name || "the keyboard");
                            return "Pairing " + (req.name || "device");
                        }
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        font.bold: true
                        color: Colors.overBackground
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.pairingDisplayOnly || root.pairingNeedsConfirm
                        horizontalAlignment: Text.AlignHCenter
                        text: root.pairingRequest?.code || ""
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(6)
                        font.bold: true
                        color: Styling.srItem("overprimary")
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.pairingDisplayOnly
                        text: root.pairingRequest?.kind === "display_passkey"
                            ? "Enter the code on the device keyboard, then continue pairing there."
                            : "Enter this PIN on the other device."
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        wrapMode: Text.WordWrap
                    }

                    SearchInput {
                        id: pinField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        visible: root.pairingNeedsInput
                        placeholderText: root.pairingRequest?.kind === "passkey" ? "6-digit passkey..." : "PIN code..."
                        passwordMode: false
                        iconText: Icons.lock
                        onSearchTextChanged: text => {
                            root.pinInput = text;
                        }
                        onAccepted: root.submitPin()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.pairingNeedsInput || root.pairingNeedsConfirm || root.pairingDisplayOnly

                        StyledRect {
                            id: rejectBtn
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            variant: "common"
                            visible: root.pairingNeedsInput || root.pairingNeedsConfirm

                            Text {
                                anchors.centerIn: parent
                                text: "Reject"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.bold: true
                                color: rejectBtn.item
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    BluetoothService.rejectPairing();
                                    root.resetPairingUi();
                                }
                            }
                        }

                        StyledRect {
                            id: dismissBtn
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            variant: "common"
                            visible: root.pairingDisplayOnly

                            Text {
                                anchors.centerIn: parent
                                text: "Dismiss"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.bold: true
                                color: dismissBtn.item
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: BluetoothService.dismissPairingDisplay()
                            }
                        }

                        StyledRect {
                            id: confirmBtn
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            variant: "primary"
                            visible: root.pairingNeedsInput || root.pairingNeedsConfirm
                            opacity: root.pairingNeedsInput && (root.pinInput || "").trim().length === 0 ? 0.55 : 1

                            Text {
                                anchors.centerIn: parent
                                text: root.pairingNeedsConfirm ? "Confirm" : "Submit"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                font.bold: true
                                color: confirmBtn.item
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.pairingNeedsConfirm)
                                        BluetoothService.confirmPairing();
                                    else
                                        root.submitPin();
                                }
                            }
                        }
                    }
                }
            }

            // Device list
            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                variant: "pane"
                clip: true

                ListView {
                    id: deviceList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    spacing: 2
                    model: root.filteredDevices
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: StyledRect {
                        id: devItem
                        required property var modelData
                        required property int index

                        width: deviceList.width
                        height: 40
                        variant: {
                            if (modelData?.connected)
                                return "focus";
                            if (devItem.hovered)
                                return "focus";
                            return "common";
                        }
                        property bool hovered: false

                        readonly property var device: modelData
                        readonly property string deviceName: device?.name ?? "Unknown"
                        readonly property bool isConnected: device?.connected ?? false
                        readonly property bool isPaired: device?.paired ?? false
                        readonly property bool isConnecting: device?.connecting ?? false

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: BluetoothService.iconForDevice(devItem.device)
                                font.family: Icons.font
                                font.pixelSize: 16
                                color: devItem.isConnected ? Styling.srItem("overprimary") : Colors.overBackground
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    text: devItem.deviceName
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.bold: devItem.isConnected
                                    color: Colors.overBackground
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (devItem.isConnecting)
                                            return "Connecting...";
                                        if (devItem.isConnected)
                                            return "Connected";
                                        if (devItem.isPaired)
                                            return "Paired";
                                        return "Not paired";
                                    }
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.fontSize(-3)
                                    color: Colors.overSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                visible: device?.batteryAvailable ?? false
                                text: (device?.battery ?? 0) + "%"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-3)
                                color: Colors.overSurfaceVariant
                            }

                            Text {
                                visible: devItem.isConnected
                                text: Icons.circle
                                font.family: Icons.font
                                font.pixelSize: 10
                                color: Styling.srItem("overprimary")
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: (devItem.isConnecting || !BluetoothService.enabled) ? Qt.BusyCursor : Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onEntered: devItem.hovered = true
                            onExited: devItem.hovered = false
                            onClicked: mouse => {
                                if (!BluetoothService.enabled || devItem.isConnecting)
                                    return;
                                if (mouse.button === Qt.RightButton) {
                                    if (devItem.isPaired || devItem.isConnected)
                                        devItem.device.forget();
                                    return;
                                }
                                root.selectDevice(devItem.device);
                            }
                        }

                        StyledToolTip {
                            show: devItem.hovered
                            tooltipText: "Click to " + (devItem.isConnected ? "disconnect" : "connect/pair") + "\nRight-click to forget"
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: deviceList.count === 0
                        text: {
                            if (!BluetoothService.enabled)
                                return "Bluetooth is disabled";
                            if (BluetoothService.discovering)
                                return "Scanning...";
                            if (root.searchQuery)
                                return "No matches";
                            return "No devices found";
                        }
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Click to connect/pair · right-click a device to forget"
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }
    }

    Connections {
        target: btPopup
        function onIsOpenChanged() {
            if (!btPopup.isOpen) {
                root.searchQuery = "";
                searchField.clear();
                root.resetPairingUi();
                BluetoothService.setUiActive(false);
                BluetoothService.stopDiscovery();
            } else {
                BluetoothService.setUiActive(true);
            }
        }
    }

    // Auto-open popup when a pairing agent request arrives
    Connections {
        target: BluetoothService
        function onPairingRequestChanged() {
            if (BluetoothService.pairingRequest && root.shown) {
                if (!btPopup.isOpen)
                    root.openPopup();
                else if (root.pairingNeedsInput)
                    Qt.callLater(() => pinField.focusInput());
            }
        }
    }

    Component.onCompleted: {
        BluetoothService.initialize();
    }
}
