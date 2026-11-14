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

// pCloud sync status, storage and transfers (formerly the bar popup).
Item {
    id: root

    implicitHeight: popupColumn.implicitHeight

    readonly property string buttonIcon: {
        if (Pcloud.syncing) {
            if (Pcloud.uploadCount > 0 && Pcloud.downloadCount === 0)
                return Icons.cloudArrowUp;
            if (Pcloud.downloadCount > 0 && Pcloud.uploadCount === 0)
                return Icons.cloudArrowDown;
            return Icons.cloudArrowUp;
        }
        return Icons.cloud;
    }
    function activate() {
        Pcloud.refreshStatus();
    }

    function reset() {
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
                    text: Pcloud.statusText || "pCloud"
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(0)
                    font.bold: true
                    color: Colors.overBackground
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    visible: (Pcloud.username || "").length > 0
                    text: Pcloud.username
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overSurfaceVariant
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        // Space meter
        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: spaceCol.implicitHeight + 16
            variant: "pane"

            ColumnLayout {
                id: spaceCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: Icons.disk
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: Styling.srItem("overprimary")
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Storage"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-1)
                        font.bold: true
                        color: Colors.overBackground
                    }

                    Text {
                        text: Pcloud.quotaTotal > 0 ? (Math.round(Pcloud.usageRatio * 100) + "%") : "—"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                    }
                }

                // Meter track
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 6
                    radius: 3
                    color: Styling.srItem("overprimary")
                    opacity: 0.15

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * (Pcloud.quotaTotal > 0 ? Pcloud.usageRatio : 0)
                        radius: parent.radius
                        color: Styling.srItem("overprimary")
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: Pcloud.usageSummary
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }
        }

        // Transfers
        Text {
            Layout.fillWidth: true
            text: Pcloud.syncing
                ? ("Transfers · " + Pcloud.transferCount)
                : "Transfers"
            font.family: Styling.defaultFont
            font.pixelSize: Styling.fontSize(-1)
            font.bold: true
            color: Colors.overBackground
        }

        StyledRect {
            Layout.fillWidth: true
            // Compact empty state; grow with rows up to 5, then ListView scrolls.
            Layout.preferredHeight: {
                const count = transferList.count;
                if (count <= 0)
                    return 44;
                return Math.min(count, 5) * 36 + 8;
            }
            variant: "pane"
            clip: true

            ListView {
                id: transferList
                anchors.fill: parent
                anchors.margins: 4
                clip: true
                spacing: 2
                model: Pcloud.transfers
                boundsBehavior: Flickable.StopAtBounds

                delegate: StyledRect {
                    id: transferItem
                    required property var modelData
                    required property int index

                    width: transferList.width
                    height: 34
                    variant: "common"

                    readonly property string direction: modelData?.direction ?? "sync"
                    readonly property string label: modelData?.label || modelData?.name || "Transfer"
                    readonly property real size: Number(modelData?.size) || 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 6

                        Text {
                            text: {
                                if (transferItem.direction === "upload")
                                    return Icons.cloudArrowUp;
                                if (transferItem.direction === "download")
                                    return Icons.cloudArrowDown;
                                return Icons.sync;
                            }
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: Styling.srItem("overprimary")
                        }

                        Text {
                            Layout.fillWidth: true
                            text: transferItem.label
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overBackground
                            elide: Text.ElideMiddle
                        }

                        Text {
                            visible: transferItem.size > 0
                            text: Pcloud.formatBytes(transferItem.size)
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.overSurfaceVariant
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: transferList.count === 0
                    text: Pcloud.mounted ? "No active transfers" : "Drive not mounted"
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overSurfaceVariant
                }
            }
        }

        // Open folder
        StyledRect {
            id: openBtn
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            variant: "primary"
            property bool btnHovered: false

            Rectangle {
                anchors.fill: parent
                color: Styling.srItem("overprimary")
                opacity: openBtn.btnHovered ? 0.15 : 0
                radius: parent.radius ?? 0
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: Icons.folder
                    font.family: Icons.font
                    font.pixelSize: 14
                    color: openBtn.item
                }

                Text {
                    text: "Open pCloudDrive"
                    font.family: Styling.defaultFont
                    font.pixelSize: Styling.fontSize(0)
                    font.bold: true
                    color: openBtn.item
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: openBtn.btnHovered = true
                onExited: openBtn.btnHovered = false
                onClicked: Pcloud.openDrive()
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Transfer list is best-effort from local pCloud state"
            font.family: Styling.defaultFont
            font.pixelSize: Styling.fontSize(-3)
            color: Colors.overSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }
}
