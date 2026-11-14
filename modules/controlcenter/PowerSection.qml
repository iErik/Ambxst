pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.bar
import qs.modules.globals
import qs.config

// Battery status and power profiles (formerly the bar battery popup).
Item {
    id: root

    implicitHeight: (Battery.available ? 64 : 0) + 36

    function getBatteryColor() {
        if (!Battery.available)
            return Colors.overBackground;

        const pct = Battery.percentage;
        if (pct <= 15)
            return Colors.red;
        if (pct >= 85)
            return Colors.green;

        // Linear interpolation between red (15%) and green (85%)
        const ratio = (pct - 15) / (85 - 15);
        return Qt.rgba(Colors.red.r + (Colors.green.r - Colors.red.r) * ratio, Colors.red.g + (Colors.green.g - Colors.red.g) * ratio, Colors.red.b + (Colors.green.b - Colors.red.b) * ratio, 1);
    }
    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        spacing: 4

        StyledRect {
            id: batteryDetailsContainer
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            visible: Battery.available
            variant: "common"
            enableShadow: false

            radius: Styling.radius(0)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 12

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: Battery.getBatteryIcon()
                    font.family: Icons.font
                    font.pixelSize: 24
                    color: root.getBatteryColor()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: Battery.isPluggedIn ? (Battery.isCharging ? "Charging" : "Full") : "On battery"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(0)
                        font.bold: true
                        color: Colors.overBackground
                    }

                    Text {
                        text: Battery.isPluggedIn ? (Battery.timeToFull !== "" ? "Full in " + Battery.timeToFull : "Fully charged") : (Battery.timeToEmpty !== "" ? Battery.timeToEmpty + " remaining" : "")
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overBackground
                        opacity: 0.8
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                // Battery percentage display
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: Math.round(Battery.percentage) + "%"
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(2)
                    font.bold: true
                    color: root.getBatteryColor()
                    opacity: 0.8
                }
            }
        }

        RowLayout {
            id: profilesRow
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4

            Repeater {
                model: PowerProfile.availableProfiles

                delegate: StyledRect {
                    id: profileButton
                    required property string modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredWidth: 80
                    height: 36

                    readonly property bool isSelected: PowerProfile.currentProfile === modelData
                    readonly property bool isFirst: index === 0
                    readonly property bool isLast: index === PowerProfile.availableProfiles.length - 1
                    property bool buttonHovered: false

                    readonly property real defaultRadius: Styling.radius(0)
                    readonly property real selectedRadius: Styling.radius(0) / 2

                    variant: isSelected ? "primary" : (buttonHovered ? "focus" : "common")
                    enableShadow: false

                    topLeftRadius: isSelected ? (isFirst ? defaultRadius : selectedRadius) : defaultRadius
                    bottomLeftRadius: isSelected ? (isFirst ? defaultRadius : selectedRadius) : defaultRadius
                    topRightRadius: isSelected ? (isLast ? defaultRadius : selectedRadius) : defaultRadius
                    bottomRightRadius: isSelected ? (isLast ? defaultRadius : selectedRadius) : defaultRadius

                    Text {
                        anchors.centerIn: parent
                        text: PowerProfile.getProfileIcon(profileButton.modelData)
                        font.family: Icons.font
                        font.pixelSize: 18
                        color: profileButton.item
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onEntered: profileButton.buttonHovered = true
                        onExited: profileButton.buttonHovered = false

                        onClicked: {
                            PowerProfile.setProfile(profileButton.modelData);
                        }
                    }

                    StyledToolTip {
                        show: profileButton.buttonHovered
                        tooltipText: PowerProfile.getProfileDisplayName(profileButton.modelData)
                    }
                }
            }
        }
    }
}
