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

    property bool popupOpen: vpnPopup.isOpen
    property string searchQuery: ""

    readonly property bool shown: (Config.bar?.showNordVpn ?? true) && NordVpn.available
    property bool clusterVisible: true
    readonly property bool inBar: shown && clusterVisible

    readonly property var filteredLocations: {
        const q = (root.searchQuery || "").trim().toLowerCase();
        const browsingCities = NordVpn.selectedCountry && NordVpn.selectedCountry.length > 0;
        const source = browsingCities ? (NordVpn.cities || []) : (NordVpn.countries || []);
        const groups = (!browsingCities && !q) ? [] : ((NordVpn.groups || []).filter(g => {
                    if (browsingCities)
                        return false;
                    if (!q)
                        return false;
                    return NordVpn.displayName(g).toLowerCase().includes(q) || String(g).toLowerCase().includes(q);
                }));

        let list = source.filter(item => {
            if (!q)
                return true;
            const display = NordVpn.displayName(item).toLowerCase();
            return display.includes(q) || String(item).toLowerCase().includes(q);
        });

        // When searching top-level, include matching groups at the top
        if (!browsingCities && q && groups.length > 0) {
            const seen = {};
            const merged = [];
            for (let i = 0; i < groups.length; i++) {
                const key = String(groups[i]).toLowerCase();
                if (!seen[key]) {
                    seen[key] = true;
                    merged.push({
                        "kind": "group",
                        "value": groups[i]
                    });
                }
            }
            for (let j = 0; j < list.length; j++) {
                const key = String(list[j]).toLowerCase();
                if (!seen[key]) {
                    seen[key] = true;
                    merged.push({
                        "kind": "country",
                        "value": list[j]
                    });
                }
            }
            return merged;
        }

        return list.map(item => ({
                    "kind": browsingCities ? "city" : "country",
                    "value": item
                }));
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
        NordVpn.ensureCountries();
        NordVpn.ensureGroups();
        NordVpn.refreshStatus();
        vpnPopup.open();
        Qt.callLater(() => searchField.focusInput());
    }

    function closePopup() {
        if (vpnPopup.isOpen)
            vpnPopup.close();
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

        // Connected indicator ring
        Rectangle {
            anchors.centerIn: parent
            width: 28
            height: 28
            radius: width / 2
            color: "transparent"
            border.width: NordVpn.connected ? 1.5 : 0
            border.color: Styling.srItem("overprimary")
            opacity: NordVpn.connected && !root.popupOpen ? 0.55 : 0
        }

        Text {
            anchors.centerIn: parent
            text: NordVpn.connected ? Icons.shieldCheck : Icons.shield
            font.family: Icons.font
            font.pixelSize: 18
            color: root.popupOpen ? buttonBg.item : Styling.srItem("overprimary")
            opacity: NordVpn.busy ? 0.55 : 1
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    NordVpn.toggleConnection();
                    return;
                }
                if (vpnPopup.isOpen)
                    vpnPopup.close();
                else
                    root.openPopup();
            }
        }

        StyledToolTip {
            show: root.isHovered && !root.popupOpen
            tooltipText: "NordVPN · " + NordVpn.statusSummary + "\nRight-click to toggle"
        }
    }

    BarPopup {
        id: vpnPopup
        anchorItem: buttonBg
        bar: root.bar
        popupPadding: 12
        contentWidth: 280
        contentHeight: 360

        onClosedExternally: {
            root.searchQuery = "";
            searchField.clear();
            NordVpn.clearCityBrowse();
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            // Status header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: NordVpn.connected ? Icons.shieldCheck : Icons.shield
                    font.family: Icons.font
                    font.pixelSize: 18
                    color: Styling.srItem("overprimary")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: NordVpn.connected ? "Connected" : (NordVpn.statusText || "Disconnected")
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(0)
                        font.bold: true
                        color: Colors.overBackground
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: NordVpn.displayLocation.length > 0 || NordVpn.ip.length > 0
                        text: {
                            if (NordVpn.displayLocation && NordVpn.ip)
                                return NordVpn.displayLocation + " · " + NordVpn.ip;
                            return NordVpn.displayLocation || NordVpn.ip;
                        }
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            // Connect / Disconnect
            StyledRect {
                id: actionBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                variant: NordVpn.connected ? "common" : "primary"
                property bool btnHovered: false
                opacity: NordVpn.busy ? 0.6 : 1

                Rectangle {
                    anchors.fill: parent
                    color: Styling.srItem("overprimary")
                    opacity: actionBtn.btnHovered && !NordVpn.busy ? 0.15 : 0
                    radius: parent.radius ?? 0
                }

                Text {
                    anchors.centerIn: parent
                    text: {
                        if (NordVpn.busy)
                            return NordVpn.connected ? "Disconnecting..." : "Connecting...";
                        return NordVpn.connected ? "Disconnect" : "Connect";
                    }
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(0)
                    font.bold: true
                    color: actionBtn.item
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: NordVpn.busy ? Qt.BusyCursor : Qt.PointingHandCursor
                    onEntered: actionBtn.btnHovered = true
                    onExited: actionBtn.btnHovered = false
                    onClicked: {
                        if (!NordVpn.busy)
                            NordVpn.toggleConnection();
                    }
                }
            }

            // Breadcrumb when browsing cities
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: NordVpn.selectedCountry.length > 0

                StyledRect {
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: backLabel.implicitWidth + 16
                    variant: "common"
                    property bool hovered: false

                    Text {
                        id: backLabel
                        anchors.centerIn: parent
                        text: "← Countries"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        color: parent.item
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.hovered = true
                        onExited: parent.hovered = false
                        onClicked: {
                            NordVpn.clearCityBrowse();
                            root.searchQuery = "";
                            searchField.clear();
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: NordVpn.displayName(NordVpn.selectedCountry)
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-1)
                    font.bold: true
                    color: Colors.overBackground
                    elide: Text.ElideRight
                }
            }

            SearchInput {
                id: searchField
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                iconText: Icons.magnifyingGlass
                placeholderText: NordVpn.selectedCountry ? "Search cities..." : "Search countries..."
                onSearchTextChanged: text => {
                    root.searchQuery = text;
                }
            }

            // Location list
            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                variant: "pane"
                clip: true

                ListView {
                    id: locationList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    spacing: 2
                    model: root.filteredLocations
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: StyledRect {
                        id: locItem
                        required property var modelData
                        required property int index

                        width: locationList.width
                        height: 34
                        variant: locItem.hovered ? "focus" : "common"
                        property bool hovered: false

                        readonly property string kind: modelData?.kind ?? "country"
                        readonly property string value: modelData?.value ?? ""
                        readonly property string label: NordVpn.displayName(value)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 4
                            spacing: 6

                            Text {
                                text: {
                                    if (locItem.kind === "group")
                                        return Icons.vpn;
                                    if (locItem.kind === "city")
                                        return Icons.mapPin;
                                    return Icons.globe;
                                }
                                font.family: Icons.font
                                font.pixelSize: 14
                                color: Styling.srItem("overprimary")
                            }

                            Text {
                                Layout.fillWidth: true
                                text: locItem.label
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overBackground
                                elide: Text.ElideRight
                            }

                            // Browse cities for a country
                            Item {
                                id: citiesBtn
                                visible: locItem.kind === "country"
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                z: 2

                                Text {
                                    anchors.centerIn: parent
                                    text: Icons.caretRight
                                    font.family: Icons.font
                                    font.pixelSize: 12
                                    color: Colors.overSurfaceVariant
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: locItem.hovered = true
                                    onExited: locItem.hovered = false
                                    onClicked: {
                                        root.searchQuery = "";
                                        searchField.clear();
                                        NordVpn.loadCities(locItem.value);
                                    }

                                    StyledToolTip {
                                        show: parent.containsMouse
                                        tooltipText: "Cities"
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: locItem.kind === "country" ? 32 : 0
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            z: 1
                            onEntered: locItem.hovered = true
                            onExited: locItem.hovered = false
                            onClicked: {
                                if (locItem.kind === "group")
                                    NordVpn.connectToGroup(locItem.value);
                                else if (locItem.kind === "city")
                                    NordVpn.connectToCity(NordVpn.selectedCountry, locItem.value);
                                else
                                    NordVpn.connectToCountry(locItem.value);
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: locationList.count === 0
                        text: {
                            if (NordVpn.citiesLoading)
                                return "Loading cities...";
                            if (NordVpn.selectedCountry)
                                return "No cities found";
                            if (!NordVpn.countriesLoaded)
                                return "Loading countries...";
                            return root.searchQuery ? "No matches" : "No locations";
                        }
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !NordVpn.selectedCountry
                text: "Click to connect · › for cities"
                font.family: Styling.defaultFont
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }
    }

    Connections {
        target: vpnPopup
        function onIsOpenChanged() {
            if (!vpnPopup.isOpen) {
                root.searchQuery = "";
                searchField.clear();
            }
        }
    }
}
