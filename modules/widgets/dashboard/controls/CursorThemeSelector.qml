pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.config

Item {
    id: root

    property var themes: []
    property string systemTheme: ""
    property string searchQuery: ""
    property bool loading: false

    readonly property string selectedTheme: Config.theme.cursorTheme || systemTheme

    readonly property var filteredThemes: {
        const q = searchQuery.trim().toLowerCase();
        if (!q)
            return themes;
        return themes.filter(t => (t.name + " " + t.id).toLowerCase().includes(q));
    }

    implicitHeight: column.implicitHeight

    function refresh() {
        loading = true;
        scanProcess.running = false;
        scanProcess.running = true;
    }

    function selectTheme(themeId) {
        if (!themeId)
            return;
        if (Config.theme.cursorTheme === themeId)
            return;
        GlobalStates.markThemeChanged();
        Config.theme.cursorTheme = themeId;
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledRect {
                variant: "common"
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: Styling.radius(-2)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Text {
                        text: Icons.magnifyingGlass
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: Colors.overSurfaceVariant
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        color: Colors.overBackground
                        selectByMouse: true
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        text: root.searchQuery
                        onTextChanged: root.searchQuery = text

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Search cursor themes…"
                            font: parent.font
                            color: Colors.overSurfaceVariant
                            visible: !parent.text && !parent.activeFocus
                        }
                    }
                }
            }

            StyledRect {
                variant: refreshArea.containsMouse ? "focus" : "common"
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: Styling.radius(-2)

                Text {
                    anchors.centerIn: parent
                    text: Icons.arrowCounterClockwise
                    font.family: Icons.font
                    font.pixelSize: 18
                    color: Colors.overBackground
                }

                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refresh()
                }
            }
        }

        Text {
            visible: !root.loading
            text: root.filteredThemes.length + " theme" + (root.filteredThemes.length === 1 ? "" : "s")
                + (root.selectedTheme ? (" · selected: " + root.selectedTheme) : "")
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            color: Colors.overSurfaceVariant
            Layout.fillWidth: true
        }

        Text {
            visible: root.loading
            text: "Scanning cursor themes…"
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            color: Colors.overSurfaceVariant
            Layout.fillWidth: true
        }

        Text {
            visible: !root.loading && root.filteredThemes.length === 0
            text: "No cursor themes found"
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overSurfaceVariant
            Layout.fillWidth: true
            Layout.topMargin: 12
            horizontalAlignment: Text.AlignHCenter
        }

        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 420 ? 2 : 1
            rowSpacing: 8
            columnSpacing: 8
            visible: !root.loading

            Repeater {
                model: root.filteredThemes

                delegate: StyledRect {
                    id: themeCard
                    required property var modelData

                    readonly property bool isSelected: root.selectedTheme === modelData.id
                    readonly property bool hasPreviews: modelData.previews && modelData.previews.length > 0

                    Layout.fillWidth: true
                    Layout.preferredHeight: 88
                    variant: isSelected ? "focus" : (cardArea.containsMouse ? "pane" : "common")
                    radius: Styling.radius(-1)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        Row {
                            spacing: 8
                            Layout.alignment: Qt.AlignHCenter
                            visible: themeCard.hasPreviews

                            Repeater {
                                model: themeCard.modelData.previews

                                delegate: Image {
                                    required property string modelData
                                    width: 28
                                    height: 28
                                    sourceSize.width: 48
                                    sourceSize.height: 48
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                    source: modelData ? ("file://" + modelData) : ""
                                }
                            }
                        }

                        Text {
                            visible: !themeCard.hasPreviews
                            Layout.alignment: Qt.AlignHCenter
                            text: Icons.cursor
                            font.family: Icons.font
                            font.pixelSize: 28
                            color: Colors.overBackground
                        }

                        Text {
                            text: themeCard.modelData.name
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.bold: themeCard.isSelected
                            color: Colors.overBackground
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        id: cardArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectTheme(themeCard.modelData.id)
                    }
                }
            }
        }
    }

    Process {
        id: scanProcess
        running: false
        command: [
            "python3",
            decodeURIComponent(Qt.resolvedUrl("../../../../scripts/list_cursor_themes.py").toString().replace("file://", ""))
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const data = JSON.parse(text);
                    root.systemTheme = data.current || "";
                    root.themes = data.themes || [];
                } catch (e) {
                    console.error("CursorThemeSelector: failed to parse themes:", e);
                    root.themes = [];
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: err => {
                if (err)
                    console.error("CursorThemeSelector scan error:", err);
            }
        }
    }

    Component.onCompleted: refresh()
}
