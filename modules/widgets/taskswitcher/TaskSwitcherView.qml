pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.modules.bar.workspaces
import qs.modules.globals
import qs.config

Item {
    id: root

    readonly property var focusedMonitor: AxctlService.focusedMonitor
    readonly property var activeWorkspaceId: focusedMonitor?.activeWorkspace?.id ?? null
    readonly property int focusedMonitorId: focusedMonitor?.id ?? -1

    // Snapshot of windows at open time. Live MRU would reshuffle when we preview-focus on Tab.
    property var windows: []

    function collectWindows() {
        const wsId = activeWorkspaceId;
        if (wsId === null || wsId === undefined)
            return [];

        const list = CompositorData.workspaceWindowsMap[wsId] || [];
        const monId = focusedMonitorId;
        const filtered = [];
        for (let i = 0; i < list.length; i++) {
            const win = list[i];
            if (!win)
                continue;
            if (monId >= 0 && win.monitor !== undefined && win.monitor !== null && Number(win.monitor) !== Number(monId))
                continue;
            filtered.push(win);
        }

        filtered.sort((a, b) => {
            const af = a.focusHistoryID ?? Number.MAX_SAFE_INTEGER;
            const bf = b.focusHistoryID ?? Number.MAX_SAFE_INTEGER;
            if (af !== bf)
                return af - bf;
            return String(a.title || "").localeCompare(String(b.title || ""));
        });
        return filtered;
    }

    property int selectedIndex: 0
    property string holdModifierLabel: "Super"

    readonly property var selectedWindow: {
        if (!windows || selectedIndex < 0 || selectedIndex >= windows.length)
            return null;
        return windows[selectedIndex];
    }

    readonly property int cardWidth: 168
    readonly property int cardHeight: 128
    readonly property int cardGap: 12
    readonly property int contentMargin: 24

    // Drive panel size from layout content (title + cards + hint) so font/radius changes don't clip.
    implicitWidth: Math.min(Math.max(windows.length, 1) * (cardWidth + cardGap) - cardGap + contentMargin * 2, 960)
    implicitHeight: contentLayout.implicitHeight + contentMargin * 2

    signal confirmed(var windowData)
    signal cancelled()
    signal selectionChanged(var windowData)

    function advance(delta) {
        const count = windows.length;
        if (count <= 0)
            return;
        selectedIndex = ((selectedIndex + delta) % count + count) % count;
        ensureVisible();
        selectionChanged(selectedWindow);
    }

    function ensureVisible() {
        if (!listView || windows.length === 0)
            return;
        listView.positionViewAtIndex(selectedIndex, ListView.Center);
    }

    function confirmSelection() {
        if (windows.length === 0) {
            cancelled();
            return;
        }
        const win = windows[selectedIndex];
        if (win)
            confirmed(win);
        else
            cancelled();
    }

    function resetSelection() {
        windows = collectWindows();
        const count = windows.length;
        if (count <= 1) {
            selectedIndex = 0;
            return;
        }
        // Pre-select the next window after the currently focused one (MRU index 0).
        selectedIndex = 1;
    }

    Connections {
        target: GlobalStates
        function onTaskSwitcherAdvanceRequestChanged() {
            if (GlobalStates.taskSwitcherAdvanceRequest > 0)
                root.advance(1);
        }
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: root.contentMargin
        spacing: 16

        Text {
            Layout.fillWidth: true
            text: windows.length === 0 ? qsTr("No windows on this workspace") : qsTr("Switch window")
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(1)
            font.weight: Font.Medium
            color: Colors.overBackground
            horizontalAlignment: Text.AlignHCenter
        }

        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.preferredHeight: root.cardHeight
            orientation: ListView.Horizontal
            spacing: root.cardGap
            clip: true
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.windows
            currentIndex: root.selectedIndex

            highlightMoveDuration: Config.animDuration > 0 ? Config.animDuration / 2 : 0

            delegate: Item {
                id: card
                required property var modelData
                required property int index

                width: root.cardWidth
                height: root.cardHeight

                readonly property bool isSelected: index === root.selectedIndex
                readonly property string iconName: AppSearch.getCachedIcon(modelData?.class || modelData?.initialClass || "")

                StyledRect {
                    anchors.fill: parent
                    variant: card.isSelected ? "focus" : (cardArea.containsMouse ? "pane" : "common")
                    radius: Styling.radius(0)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Image {
                                anchors.centerIn: parent
                                width: 56
                                height: 56
                                sourceSize.width: 64
                                sourceSize.height: 64
                                asynchronous: true
                                smooth: true
                                visible: status === Image.Ready
                                source: {
                                    const icon = card.iconName;
                                    if (!icon || icon === "image-missing")
                                        return "";
                                    if (icon.startsWith("/") || icon.startsWith("file:"))
                                        return icon.startsWith("file:") ? icon : ("file://" + icon);
                                    return Quickshell.iconPath(icon, true) || "";
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: parent.children[0].status !== Image.Ready
                                text: Icons.apps
                                font.family: Icons.font
                                font.pixelSize: 40
                                color: Colors.overSurfaceVariant
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: card.modelData?.title || card.modelData?.class || qsTr("Untitled")
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.bold: card.isSelected
                            color: Colors.overBackground
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            maximumLineCount: 2
                            wrapMode: Text.WrapAnywhere
                        }
                    }

                    MouseArea {
                        id: cardArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedIndex = card.index;
                            root.confirmSelection();
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: windows.length > 0
            text: qsTr("Hold %1 · Tab / ← → to cycle · release to focus · Esc to cancel").arg(root.holdModifierLabel)
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    Component.onCompleted: resetSelection()
}
