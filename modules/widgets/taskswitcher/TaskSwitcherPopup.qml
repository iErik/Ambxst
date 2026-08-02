import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config
import "../../../config/KeybindActions.js" as KeybindActions
import "."

PanelWindow {
    id: taskSwitcherPopup

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    readonly property var screenVisibilities: Visibilities.getForScreen(screen.name)
    readonly property bool taskSwitcherOpen: screenVisibilities ? screenVisibilities.taskswitcher : false

    // Gate drawing until hold-modifier check passes so ultra-fast Super release never flashes UI.
    property bool allowShow: false

    // Hold modifier from the configured Task Switcher bind (SUPER / ALT / CTRL).
    readonly property string holdModifier: {
        const loader = Config.keybindsLoader;
        const bind = loader && loader.adapter && loader.adapter.ambxst && loader.adapter.ambxst.system
            ? loader.adapter.ambxst.system.taskswitcher
            : null;
        return KeybindActions.taskSwitcherPrimaryModifier(bind && bind.modifiers ? bind.modifiers : ["SUPER"]);
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst:taskswitcher"
    WlrLayershell.keyboardFocus: (taskSwitcherOpen && allowShow) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: taskSwitcherOpen && allowShow
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        item: (taskSwitcherOpen && allowShow) ? fullMask : emptyMask
    }

    Item {
        id: fullMask
        anchors.fill: parent
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    FocusGrab {
        id: focusGrab
        windows: [taskSwitcherPopup]
        active: taskSwitcherOpen && allowShow

        onCleared: {
            Qt.callLater(() => {
                if (taskSwitcherOpen && allowShow)
                    Visibilities.setActiveModule("");
            });
        }
    }

    function isHoldModifierKey(key) {
        const mod = holdModifier;
        if (mod === "SUPER")
            return key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R;
        if (mod === "ALT")
            return key === Qt.Key_Alt;
        if (mod === "CTRL")
            return key === Qt.Key_Control;
        return false;
    }

    property bool confirming: false

    function focusSelectedWindow(win) {
        const target = win || switcherView.selectedWindow;
        if (!target || !target.address)
            return;
        AxctlService.focusWindow(target.address, target.workspace ? target.workspace.id : undefined);
    }

    function confirmFromModifierRelease() {
        if (!taskSwitcherOpen || confirming)
            return;
        confirming = true;
        allowShow = false;
        // Mark confirm time so a compositor Super_L bindr launcher action can be suppressed.
        GlobalShortcuts.taskSwitcherConfirmedAt = Date.now();
        GlobalStates.taskSwitcherPendingConfirm = false;
        switcherView.confirmSelection();
    }

    function consumePendingOrHiddenConfirm() {
        if (!taskSwitcherOpen || confirming)
            return false;
        if (!GlobalStates.taskSwitcherPendingConfirm)
            return false;
        confirming = true;
        allowShow = false;
        GlobalStates.taskSwitcherPendingConfirm = false;
        switcherView.confirmSelection();
        return true;
    }

    function revealIfStillHeld() {
        if (!taskSwitcherOpen || confirming || GlobalStates.taskSwitcherPendingConfirm)
            return;
        allowShow = true;
        focusSelectedWindow(switcherView.selectedWindow);
        keyHandler.forceActiveFocus();
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Colors.scrim
        opacity: taskSwitcherOpen ? 0.45 : 0

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Visibilities.setActiveModule("")
        }
    }

    Item {
        id: mainContainer
        anchors.centerIn: parent
        width: switcherPanel.width
        height: switcherPanel.height

        opacity: taskSwitcherOpen ? 1 : 0
        scale: taskSwitcherOpen ? 1 : 0.92

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        Behavior on scale {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutBack
                easing.overshoot: 1.1
            }
        }

        StyledRect {
            id: switcherPanel
            variant: "popup"
            radius: Styling.radius(2)
            width: switcherView.implicitWidth
            height: switcherView.implicitHeight

            layer.enabled: true
            layer.effect: Shadow {}

            TaskSwitcherView {
                id: switcherView
                anchors.fill: parent
                holdModifierLabel: {
                    const mod = taskSwitcherPopup.holdModifier;
                    if (mod === "ALT")
                        return "Alt";
                    if (mod === "CTRL")
                        return "Ctrl";
                    return "Super";
                }

                onSelectionChanged: win => {
                    // Live preview: focus + warp cursor while switcher stays open.
                    if (taskSwitcherOpen && win)
                        taskSwitcherPopup.focusSelectedWindow(win);
                }

                onConfirmed: win => {
                    const address = win?.address;
                    const wsId = win?.workspace?.id;
                    Visibilities.setActiveModule("");
                    Qt.callLater(() => {
                        if (address)
                            AxctlService.focusWindow(address, wsId);
                    });
                }

                onCancelled: {
                    GlobalStates.taskSwitcherPendingConfirm = false;
                    Visibilities.setActiveModule("");
                }
            }
        }
    }

    // Capture Super/Alt/Ctrl release for hold-to-confirm (Exclusive focus).
    Item {
        id: keyHandler
        anchors.fill: parent
        focus: taskSwitcherOpen
        activeFocusOnTab: false

        Keys.onReleased: event => {
            if (!taskSwitcherOpen)
                return;
            if (isHoldModifierKey(event.key)) {
                confirmFromModifierRelease();
                event.accepted = true;
            }
        }

        Keys.onPressed: event => {
            if (!taskSwitcherOpen)
                return;
            // Swallow hold-modifier presses so they don't leak; Tab/arrows use Shortcuts below.
            if (isHoldModifierKey(event.key))
                event.accepted = true;
        }
    }

    // Keyboard navigation while Exclusive focus is held
    Shortcut {
        sequences: ["Tab", "Right", "Meta+Tab", "Alt+Tab", "Ctrl+Tab"]
        enabled: taskSwitcherOpen
        onActivated: switcherView.advance(1)
    }

    Shortcut {
        sequences: ["Shift+Tab", "Left", "Meta+Shift+Tab", "Alt+Shift+Tab", "Ctrl+Shift+Tab"]
        enabled: taskSwitcherOpen
        onActivated: switcherView.advance(-1)
    }

    Shortcut {
        sequences: ["Return", "Enter", "Space"]
        enabled: taskSwitcherOpen
        onActivated: switcherView.confirmSelection()
    }

    Shortcut {
        sequences: ["Escape"]
        enabled: taskSwitcherOpen
        onActivated: {
            GlobalStates.taskSwitcherPendingConfirm = false;
            Visibilities.setActiveModule("");
        }
    }

    Connections {
        target: GlobalStates
        function onTaskSwitcherConfirmRequestChanged() {
            if (!taskSwitcherOpen || confirming || GlobalStates.taskSwitcherConfirmRequest <= 0)
                return;
            confirming = true;
            allowShow = false;
            GlobalShortcuts.taskSwitcherConfirmedAt = Date.now();
            GlobalStates.taskSwitcherPendingConfirm = false;
            switcherView.confirmSelection();
        }

        function onTaskSwitcherPendingConfirmChanged() {
            if (GlobalStates.taskSwitcherPendingConfirm)
                consumePendingOrHiddenConfirm();
        }
    }

    Connections {
        target: GlobalShortcuts
        function onHoldModifierProbeResult(held) {
            if (!taskSwitcherOpen || confirming)
                return;
            if (!held) {
                consumePendingOrHiddenConfirm();
                return;
            }
            revealIfStillHeld();
        }
    }

    // Re-check shortly after open (Loader vs bindr / IPC ordering).
    Timer {
        id: holdReleaseCheckTimer
        interval: 16
        repeat: false
        onTriggered: {
            if (!taskSwitcherOpen || confirming)
                return;
            if (consumePendingOrHiddenConfirm())
                return;
            GlobalShortcuts.flushPendingTaskSwitcherConfirm();
            GlobalShortcuts.probeHoldModifierDown();
        }
    }

    Timer {
        id: holdReleaseCheckTimer2
        interval: 50
        repeat: false
        onTriggered: {
            if (!taskSwitcherOpen || confirming)
                return;
            if (consumePendingOrHiddenConfirm())
                return;
            GlobalShortcuts.flushPendingTaskSwitcherConfirm();
            GlobalShortcuts.probeHoldModifierDown();
        }
    }

    Timer {
        id: holdReleaseCheckTimer3
        interval: 100
        repeat: false
        onTriggered: {
            if (!taskSwitcherOpen || confirming)
                return;
            if (consumePendingOrHiddenConfirm())
                return;
            // Non-Hyprland / probe failure fallback: show if still open and Super not known-up.
            if (!allowShow)
                revealIfStillHeld();
            GlobalShortcuts.probeHoldModifierDown();
        }
    }

    onTaskSwitcherOpenChanged: {
        if (taskSwitcherOpen) {
            confirming = false;
            allowShow = false;
            switcherView.resetSelection();

            // If Super already released, confirm without ever painting the UI.
            if (GlobalStates.taskSwitcherPendingConfirm || GlobalShortcuts.hasFreshPendingTaskSwitcherConfirm()) {
                confirming = true;
                GlobalStates.taskSwitcherPendingConfirm = false;
                switcherView.confirmSelection();
                return;
            }

            GlobalShortcuts.flushPendingTaskSwitcherConfirm();
            GlobalShortcuts.probeHoldModifierDown();
            // Hyprland: reveal only after probe says hold mod is down. Others: next tick.
            if (!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
                Qt.callLater(() => revealIfStillHeld());
            }
            holdReleaseCheckTimer.restart();
            holdReleaseCheckTimer2.restart();
            holdReleaseCheckTimer3.restart();
        } else {
            confirming = false;
            allowShow = false;
            holdReleaseCheckTimer.stop();
            holdReleaseCheckTimer2.stop();
            holdReleaseCheckTimer3.stop();
        }
    }
}
