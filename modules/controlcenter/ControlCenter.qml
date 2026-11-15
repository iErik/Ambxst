pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.modules.services
import qs.modules.components
import qs.modules.corners
import qs.modules.theme
import qs.modules.globals
import qs.modules.widgets.dashboard.controls
import qs.config

// Control Center: a panel attached to the right edge of the screen, styled
// like the notch (a styled surface masked by a body plus concave corner
// flares where it meets an edge). Holds the control center page and Settings.
Item {
    id: root

    required property var targetScreen

    readonly property var screenVisibilities: Visibilities.getForScreen(targetScreen.name)
    readonly property bool active: screenVisibilities ? screenVisibilities.controlcenter : false

    // Input region for the shell panel's mask.
    property alias hitbox: hitArea

    // ── Placement ───────────────────────────────────────────────────────
    readonly property var screenBar: Visibilities.bars[targetScreen.name] ?? null
    readonly property string barPosition: screenBar ? (screenBar.barPosition ?? "top") : "top"
    readonly property bool barShown: screenBar !== null && screenBar.visible && (screenBar.reveal ?? false)
    readonly property bool barFloating: Config.bar?.floating ?? true
    readonly property bool barContained: (Config.bar?.frameEnabled ?? false) && (Config.bar?.containBar ?? false)
    readonly property int frameInset: (Config.bar?.frameEnabled ?? false) ? (Config.bar?.frameThickness ?? 6) : 0
    readonly property int barExtent: barShown ? (screenBar.totalBarHeight ?? 0) : 0

    // The top of the panel meets an edge (a flush bar, the frame or the screen
    // edge) and curves out of it; below a floating bar it is a rounded corner.
    readonly property bool topAttached: !(barShown && barPosition === "top" && barFloating && !barContained)
    readonly property int topInset: {
        if (barShown && barPosition === "top")
            return barExtent + (topAttached ? 0 : 4);
        return frameInset;
    }
    readonly property bool bottomAttached: !(barShown && barPosition === "bottom")
    readonly property int bottomInset: {
        if (barShown && barPosition === "bottom")
            return barExtent + 4;
        return frameInset;
    }
    readonly property int rightInset: (barShown && barPosition === "right") ? barExtent : frameInset

    // Blend into a flush bar it hangs from; otherwise look like the notch.
    readonly property bool blendWithBar: barShown && barPosition === "top" && !barFloating && !barContained

    // ── Tabs ────────────────────────────────────────────────────────────
    // 0: Control Center, 1: Lights, 2–11: the Settings sections (SettingsTab
    // sections 0–9), 12: Settings search (the full Settings layout and list).
    readonly property int lightsTab: 1
    readonly property int firstSettingsTab: 2
    readonly property int settingsSectionCount: 10
    readonly property int searchTab: firstSettingsTab + settingsSectionCount
    readonly property int currentTab: GlobalStates.controlCenterTab
    readonly property bool onSettings: currentTab >= firstSettingsTab
    property bool settingsVisited: onSettings
    property bool lightsVisited: currentTab === lightsTab
    onOnSettingsChanged: if (onSettings)
        settingsVisited = true

    readonly property var tabModel: [
        { icon: Icons.squaresFour, label: "Control Center" },
        { icon: Icons.lightbulb, label: "Lights" },
        { icon: Icons.wifiHigh, label: "Network" },
        { icon: Icons.bluetooth, label: "Bluetooth" },
        { icon: Icons.faders, label: "Mixer" },
        { icon: Icons.robot, label: "AI" },
        { icon: Icons.waveform, label: "Effects" },
        { icon: Icons.paintBrush, label: "Theme" },
        { icon: Icons.keyboard, label: "Binds" },
        { icon: Icons.circuitry, label: "System" },
        { icon: Icons.compositor, label: "Compositor" },
        { image: Qt.resolvedUrl("../../assets/ambxst/ambxst-icon.svg"), label: "Ambxst" }
    ]

    // Tabs that can be hidden (their section isn't available).
    function tabShown(index) {
        if (index === firstSettingsTab + 4) // Effects
            return EasyEffectsService.installed;
        return true;
    }
    // If the current tab gets hidden, fall back to the Control Center tab.
    Connections {
        target: EasyEffectsService
        function onInstalledChanged() {
            if (!root.tabShown(root.currentTab))
                root.selectTab(0);
        }
    }

    function selectTab(index) {
        PerfProbe.mark("tab " + index);
        GlobalStates.controlCenterTab = index;
    }

    // Point the shared Settings view at the selected section.
    function syncSettings() {
        const settings = settingsLoader.item;
        if (!settings)
            return;
        settings.showSidebar = root.currentTab === root.searchTab;
        if (root.currentTab >= root.firstSettingsTab && root.currentTab < root.searchTab)
            settings.showSection(root.currentTab - root.firstSettingsTab);
        if (root.currentTab === root.searchTab)
            Qt.callLater(() => settings.focusSearchInput());
    }
    onCurrentTabChanged: {
        if (currentTab === lightsTab)
            lightsVisited = true;
        syncSettings();
    }

    // ── Size ────────────────────────────────────────────────────────────
    readonly property int tabSize: 44
    readonly property int contentWidth: (currentTab === 0 || currentTab === lightsTab) ? 404 : (currentTab === searchTab ? 840 : 620)
    readonly property int bodyWidth: tabSize + 2 + 12 + contentWidth + 32
    readonly property int flareSize: Config.roundness > 0 ? Config.roundness + 4 : 0
    readonly property int cornerRadius: Config.roundness > 0 ? Config.roundness + 20 : 0

    // Widest tab: the frame below is always this wide, so its layers never
    // change size; only `shownWidth` animates.
    readonly property int maxBodyWidth: tabSize + 2 + 12 + 840 + 32
    property real shownWidth: bodyWidth
    Behavior on shownWidth {
        enabled: Config.animDuration > 0 && root.active
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutCubic
        }
    }

    onActiveChanged: {
        PerfProbe.mark(active ? "controlcenter open" : "controlcenter close");
        if (active) {
            panelFocus.forceActiveFocus();
        } else {
            controlsPage.reset();
        }
    }

    // ── Warm-up ─────────────────────────────────────────────────────────
    // Build every page ahead of time while the shell is idle, so opening the
    // panel or switching tabs never creates objects mid-animation.
    Component.onCompleted: {
        const focused = AxctlService.focusedMonitor?.name === root.targetScreen.name;
        const name = root.targetScreen.name;
        const jobs = [];
        jobs.push({
            label: name + " settings",
            run: () => {
                root.settingsVisited = true;
                return settingsLoader;
            }
        });
        for (let i = 0; i < root.settingsSectionCount; i++) {
            const section = i;
            jobs.push({
                label: name + " section " + section,
                run: () => settingsLoader.item && root.tabShown(section + root.firstSettingsTab) ? settingsLoader.item.warmSection(section) : null
            });
        }
        for (const detail of controlsPage.detailNames) {
            const d = detail;
            jobs.push({
                label: name + " detail " + d,
                run: () => controlsPage.warmDetail(d)
            });
        }
        if (focused) {
            for (let j = jobs.length - 1; j >= 0; j--)
                IdleWork.enqueue(jobs[j], true);
        } else {
            for (const job of jobs)
                IdleWork.enqueue(job, false);
        }
    }

    Item {
        id: panel
        // Fixed size (see maxBodyWidth): the open/close slide moves it, the
        // tab resize only moves the mask edge and the content clip.
        width: root.maxBodyWidth + root.flareSize
        y: root.topInset
        height: Math.max(0, parent.height - root.topInset - root.bottomInset)
        property real slide: root.active ? 0 : 1
        // Left edge of the visible body within the frame.
        readonly property real edgeX: width - root.shownWidth
        x: parent.width - root.rightInset - width + slide * (root.shownWidth + root.flareSize + root.rightInset + 16)
        visible: root.active || slide < 1

        Behavior on slide {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutCubic
            }
        }

        // The visible part (body + flares): input region and click absorber.
        Item {
            id: hitArea
            x: panel.edgeX - root.flareSize
            width: root.shownWidth + root.flareSize
            height: parent.height
        }

        // Clicks on the panel never reach the click-outside backdrop.
        MouseArea {
            anchors.fill: hitArea
            acceptedButtons: Qt.AllButtons
            onPressed: mouse => {
                panelFocus.forceActiveFocus();
                mouse.accepted = true;
            }
        }

        // Surface with its own shadow (outside the shell's full-screen shadow
        // layer). Clipped where the panel meets the bar or a screen edge, so
        // no shadow falls onto the bar.
        Item {
            id: shadowClip
            readonly property int pad: 48
            x: -pad
            y: root.topAttached ? 0 : -pad
            width: parent.width + pad
            height: parent.height + (root.topAttached ? 0 : pad) + (root.bottomAttached ? 0 : pad)
            clip: true

            Item {
                id: surfaceWrap
                x: shadowClip.pad
                y: root.topAttached ? 0 : shadowClip.pad
                width: panel.width
                height: panel.height
                layer.enabled: true
                layer.effect: Shadow {}

                // Surface, masked to body + flares.
                StyledRect {
                    anchors.fill: parent
                    variant: root.blendWithBar ? "barbg" : "bg"
                    enableBorder: false
                    animateRadius: false
                    radius: 0
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: panelMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }

                Item {
                    id: panelMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    layer.smooth: true

                    // Flare curving out of the top edge (or the bar) into the body.
                    RoundCorner {
                        x: panel.edgeX - root.flareSize
                        y: 0
                        width: root.flareSize
                        height: root.flareSize
                        size: Math.max(1, root.flareSize)
                        // opacity, not visible: inside the hidden mask layer a
                        // RoundCorner that starts invisible never gets painted.
                        opacity: root.topAttached ? 1 : 0
                        corner: RoundCorner.CornerEnum.TopRight
                        color: "white"
                    }

                    Rectangle {
                        id: bodyMask
                        x: panel.edgeX
                        width: root.shownWidth
                        height: parent.height
                        color: "white"
                        topLeftRadius: root.topAttached ? 0 : root.cornerRadius
                        bottomLeftRadius: root.bottomAttached ? 0 : root.cornerRadius
                    }

                    // Flare curving out of the bottom edge into the body.
                    RoundCorner {
                        x: panel.edgeX - root.flareSize
                        y: parent.height - height
                        width: root.flareSize
                        height: root.flareSize
                        size: Math.max(1, root.flareSize)
                        opacity: root.bottomAttached ? 1 : 0
                        corner: RoundCorner.CornerEnum.BottomRight
                        color: "white"
                    }
                }
            }
        }

        // ── Content ─────────────────────────────────────────────────────
        FocusScope {
            id: panelFocus
            anchors.fill: hitArea
            focus: root.active

            Keys.onEscapePressed: event => {
                Visibilities.setActiveModule("");
                event.accepted = true;
            }
        }

        // Clip to the visible body; the content inside is laid out at the
        // target width right away and kept against the right edge, so pages
        // aren't re-laid out on every frame of the resize.
        Item {
            id: contentClip
            x: panel.edgeX
            width: root.shownWidth
            height: parent.height
            clip: true

        Item {
            id: body
            width: root.bodyWidth
            x: contentClip.width - width
            height: parent.height

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                anchors.topMargin: root.topAttached ? 12 : 16
                anchors.bottomMargin: root.bottomAttached ? 12 : 16
                spacing: 6

                // Side tabs, styled like the dashboard's: a sliding primary
                // highlight behind icon buttons, search pinned to the bottom.
                Item {
                    id: tabsContainer
                    Layout.preferredWidth: root.tabSize
                    Layout.fillHeight: true

                    Flickable {
                        id: tabsFlick
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: searchButton.top
                        anchors.bottomMargin: 8
                        contentHeight: tabsColumn.height
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height
                        clip: true

                        StyledRect {
                            id: tabHighlight
                            variant: "primary"
                            width: root.tabSize
                            height: root.tabSize
                            radius: Styling.radius(4)
                            visible: root.currentTab < root.searchTab
                            // Follow the selected button (hidden tabs shift the rest up).
                            y: {
                                const item = tabRepeater.count > root.currentTab ? tabRepeater.itemAt(root.currentTab) : null;
                                return item ? item.y : 0;
                            }

                            Behavior on y {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: Config.animDuration / 2
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        Column {
                            id: tabsColumn
                            width: parent.width
                            spacing: 4

                            Repeater {
                                id: tabRepeater
                                model: root.tabModel

                                Item {
                                    id: tabButton
                                    required property var modelData
                                    required property int index
                                    readonly property bool selected: root.currentTab === index
                                    visible: root.tabShown(index)
                                    width: root.tabSize
                                    height: root.tabSize

                                    StyledRect {
                                        anchors.fill: parent
                                        variant: "focus"
                                        radius: Styling.radius(4)
                                        opacity: tabArea.containsMouse && !tabButton.selected ? 1 : 0

                                        Behavior on opacity {
                                            enabled: Config.animDuration > 0
                                            NumberAnimation {
                                                duration: Config.animDuration / 3
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !tabButton.modelData.image
                                        text: tabButton.modelData.icon ?? ""
                                        font.family: Icons.font
                                        font.pixelSize: 20
                                        color: tabButton.selected ? Styling.srItem("primary") : Colors.overBackground

                                        Behavior on color {
                                            enabled: Config.animDuration > 0
                                            ColorAnimation {
                                                duration: Config.animDuration
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }

                                    Image {
                                        anchors.centerIn: parent
                                        visible: !!tabButton.modelData.image
                                        width: 20
                                        height: 20
                                        source: tabButton.modelData.image ?? ""
                                        sourceSize: Qt.size(40, 40)
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        layer.enabled: visible
                                        layer.effect: MultiEffect {
                                            brightness: 1.0
                                            colorization: 1.0
                                            colorizationColor: tabButton.selected ? Styling.srItem("primary") : Colors.overBackground
                                        }
                                    }

                                    MouseArea {
                                        id: tabArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectTab(tabButton.index)
                                    }

                                    StyledToolTip {
                                        show: tabArea.containsMouse
                                        tooltipText: tabButton.modelData.label
                                    }
                                }
                            }
                        }

                        // Wheel over the tabs steps through them.
                        WheelHandler {
                            enabled: !tabsFlick.interactive
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                const last = root.tabModel.length - 1;
                                const step = event.angleDelta.y > 0 ? -1 : 1;
                                let next = Math.min(root.currentTab, last) + step;
                                while (next >= 0 && next <= last && !root.tabShown(next))
                                    next += step;
                                if (next >= 0 && next <= last)
                                    root.selectTab(next);
                            }
                        }
                    }

                    // Search: the full Settings layout (search box + results).
                    StyledRect {
                        id: searchButton
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        width: root.tabSize
                        height: root.tabSize
                        radius: Styling.radius(4)
                        variant: root.currentTab === root.searchTab ? "primary" : (searchArea.containsMouse ? "focus" : "common")

                        Text {
                            anchors.centerIn: parent
                            text: Icons.magnifyingGlass
                            font.family: Icons.font
                            font.pixelSize: 20
                            color: root.currentTab === root.searchTab ? Styling.srItem("primary") : Colors.overBackground
                        }

                        MouseArea {
                            id: searchArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectTab(root.searchTab)
                        }

                        StyledToolTip {
                            show: searchArea.containsMouse
                            tooltipText: "Search settings"
                        }
                    }
                }

                Separator {
                    Layout.preferredWidth: 2
                    Layout.fillHeight: true
                    vert: true
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 6
                    clip: true

                    ControlCenterPage {
                        id: controlsPage
                        anchors.fill: parent
                        screen: root.targetScreen
                        visible: root.currentTab === 0
                    }

                    // Lights: built on first open (it starts the bulb helper).
                    Loader {
                        anchors.fill: parent
                        active: root.lightsVisited
                        visible: root.currentTab === root.lightsTab
                        sourceComponent: LightsPage {}
                    }

                    // One Settings view shared by the section tabs and search;
                    // it stays loaded once opened so its state and search
                    // index survive switching tabs.
                    Loader {
                        id: settingsLoader
                        anchors.fill: parent
                        active: root.settingsVisited
                        // Built in the background: creating Settings in one
                        // go froze the shell on its first open.
                        asynchronous: true
                        visible: root.onSettings
                        sourceComponent: SettingsTab {
                            showSidebar: false
                        }
                        onLoaded: root.syncSettings()
                    }
                }
            }
        }
        }
    }
}
