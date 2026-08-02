pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.globals
import qs.modules.services
import qs.config
import "../../config/KeybindActions.js" as KeybindActions

import Quickshell.Io

QtObject {
    id: root

    readonly property string appId: "ambxst"
    readonly property string ipcPipe: "/tmp/ambxst_ipc.pipe"

    // High-performance Pipe Listener (Daemon mode)
    property Process pipeListener: Process {
        command: ["bash", "-c", "rm -f " + root.ipcPipe + "; mkfifo " + root.ipcPipe + "; tail -f " + root.ipcPipe]
        running: true
        
        stdout: SplitParser {
            onRead: data => {
                const cmd = data.trim();
                if (cmd !== "") {
                    root.run(cmd);
                }
            }
        }
    }

    function run(command) {
        console.log("IPC run command received:", command);
        switch (command) {
            // Launcher (Standalone Notch Module)
            case "launcher": toggleLauncher(); break;
            case "clipboard": toggleLauncherWithPrefix(1, Config.prefix.clipboard + " "); break;
            case "emoji": toggleLauncherWithPrefix(2, Config.prefix.emoji + " "); break;
            case "tmux": toggleLauncherWithPrefix(3, Config.prefix.tmux + " "); break;
            case "notes": toggleLauncherWithPrefix(4, Config.prefix.notes + " "); break;

            // Dashboard
            case "dashboard": toggleDashboardTab(0); break;
            case "wallpapers": toggleDashboardTab(1); break;
            case "assistant": toggleAssistant(); break;
            case "dashboard-widgets": toggleDashboardTab(0); break;
            case "dashboard-wallpapers": toggleDashboardTab(1); break;
            case "dashboard-kanban": toggleDashboardTab(2); break;
            case "dashboard-assistant": toggleAssistant(); break;
            case "dashboard-controls": toggleSettings(); break;

            // System
            case "overview": toggleSimpleModule("overview"); break;
            case "task-switcher":
            case "taskswitcher":
                openOrAdvanceTaskSwitcher();
                break;
            case "task-switcher-confirm":
            case "taskswitcher-confirm":
                confirmTaskSwitcher();
                break;
            case "powermenu": toggleSimpleModule("powermenu"); break;
            case "tools": toggleSimpleModule("tools"); break;
            case "toggle-bar": GlobalStates.toggleBarForceHidden(); break;
            case "config": toggleSettings(); break;
            case "screenshot": Screenshot.initialize(); GlobalStates.screenshotToolVisible = true; break;
            case "screenrecord":
                ScreenRecorder.initialize();
                if (ScreenRecorder.isRecording) {
                    ScreenRecorder.toggleRecording();
                } else {
                    GlobalStates.screenRecordToolVisible = true;
                }
                break;
            case "lens": 
                Screenshot.initialize();
                Screenshot.captureMode = "lens";
                GlobalStates.screenshotToolVisible = true;
                break;
            case "lockscreen": GlobalStates.lockscreenVisible = true; break;
            
            // Media
            case "media-seek-backward": seekActivePlayer(-mediaSeekStepMs); break;
            case "media-seek-forward": seekActivePlayer(mediaSeekStepMs); break;
            case "media-play-pause": 
                if (MprisController.canTogglePlaying) MprisController.togglePlaying();
                break;
            case "media-next": MprisController.next(); break;
            case "media-prev": MprisController.previous(); break;
                
            default: console.warn("Unknown IPC command:", command);
        }
    }

    property IpcHandler ipcHandler: IpcHandler {
        target: "ambxst"

        function run(command: string) {
            root.run(command);
        }
    }

    function toggleSettings(screenName) {
        const willOpen = !GlobalStates.settingsWindowVisible;
        if (willOpen) {
            const targetMonitor = screenName ? AxctlService.monitorFor(screenName) : AxctlService.focusedMonitor;
            GlobalStates.settingsTargetWorkspaceId = targetMonitor?.activeWorkspace?.id || AxctlService.focusedMonitor?.activeWorkspace?.id || AxctlService.focusedWorkspace?.id || 0;
            GlobalStates.settingsTargetScreenName = targetMonitor?.name || AxctlService.focusedMonitor?.name || "";
            if (targetMonitor && targetMonitor.id !== AxctlService.focusedMonitor?.id) {
                AxctlService.dispatch(`focusmonitor ${targetMonitor.id}`);
            }
            Qt.callLater(() => Visibilities.setActiveModule(""));
        }
        GlobalStates.settingsWindowVisible = willOpen;
    }

    function toggleSimpleModule(moduleName) {
        if (Visibilities.currentActiveModule === moduleName) {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule(moduleName);
        }
    }

    // Suppress launcher toggle briefly after Super-release confirms the task switcher,
    // so a shared Super_L bindr (default launcher) does not reopen the launcher.
    property double taskSwitcherConfirmedAt: 0
    property double taskSwitcherOpenRequestedAt: 0
    property bool taskSwitcherForceClosing: false

    function taskSwitcherHoldModifier() {
        const loader = Config.keybindsLoader;
        const bind = loader && loader.adapter && loader.adapter.ambxst && loader.adapter.ambxst.system
            ? loader.adapter.ambxst.system.taskswitcher
            : null;
        return KeybindActions.taskSwitcherPrimaryModifier(bind && bind.modifiers ? bind.modifiers : ["SUPER"]);
    }

    function hasFreshPendingTaskSwitcherConfirm() {
        if (!GlobalStates.taskSwitcherPendingConfirm || taskSwitcherConfirmedAt <= 0)
            return false;
        return (Date.now() - taskSwitcherConfirmedAt) < 500;
    }

    // Alt-tab style: first press opens, further presses advance; modifier release confirms.
    function openOrAdvanceTaskSwitcher() {
        // Confirm IPC already arrived (Super released before/during open): never show UI.
        if (hasFreshPendingTaskSwitcherConfirm()) {
            taskSwitcherConfirmedAt = Date.now();
            GlobalStates.taskSwitcherPendingConfirm = false;
            pendingConfirmExpire.stop();
            if (Visibilities.currentActiveModule === "taskswitcher") {
                confirmTaskSwitcherNow();
            } else {
                focusTaskSwitcherTargetWindow();
            }
            return;
        }

        if (Visibilities.currentActiveModule === "taskswitcher") {
            GlobalStates.taskSwitcherAdvanceRequest++;
            armHoldInvariantChecks();
            return;
        }

        taskSwitcherOpenRequestedAt = Date.now();
        Visibilities.setActiveModule("taskswitcher");
        startHoldInvariantPolling();
        armHoldInvariantChecks();
    }

    // Drop a raced confirm into the Popup path, and force-close if Popup never consumed it.
    function flushPendingTaskSwitcherConfirm() {
        if (!hasFreshPendingTaskSwitcherConfirm())
            return;
        if (Visibilities.currentActiveModule !== "taskswitcher")
            return;
        taskSwitcherConfirmedAt = Date.now();
        // Prefer Popup selection if it is already loaded.
        GlobalStates.taskSwitcherConfirmRequest++;
        Qt.callLater(() => {
            if (GlobalStates.taskSwitcherPendingConfirm && Visibilities.currentActiveModule === "taskswitcher")
                confirmTaskSwitcherNow();
        });
    }

    function confirmTaskSwitcher() {
        taskSwitcherConfirmedAt = Date.now();
        // Sticky until Popup or GlobalShortcuts failsafe consumes it.
        GlobalStates.taskSwitcherPendingConfirm = true;
        pendingConfirmExpire.restart();

        if (Visibilities.currentActiveModule !== "taskswitcher") {
            // Open IPC may still be in flight — arm flushes; openOrAdvance also short-circuits.
            if (taskSwitcherOpenRequestedAt > 0 && (Date.now() - taskSwitcherOpenRequestedAt) < 500)
                armHoldInvariantChecks();
            return;
        }

        // Module flagged active, but Loader/Popup may not exist yet (fast-tap race).
        GlobalStates.taskSwitcherConfirmRequest++;
        armHoldInvariantChecks();
        // Failsafe: if Popup does not clear pending, close + focus without it.
        Qt.callLater(() => {
            if (GlobalStates.taskSwitcherPendingConfirm && Visibilities.currentActiveModule === "taskswitcher")
                confirmTaskSwitcherNow();
        });
    }

    // Close switcher and focus the default next window without needing the Popup.
    // Used when confirm races ahead of Loader creation.
    function confirmTaskSwitcherNow() {
        if (taskSwitcherForceClosing)
            return;
        taskSwitcherForceClosing = true;
        taskSwitcherConfirmedAt = Date.now();
        GlobalStates.taskSwitcherPendingConfirm = false;
        pendingConfirmExpire.stop();
        stopHoldInvariantPolling();

        const wasOpen = Visibilities.currentActiveModule === "taskswitcher";
        if (wasOpen)
            Visibilities.setActiveModule("");
        focusTaskSwitcherTargetWindow();

        Qt.callLater(() => {
            taskSwitcherForceClosing = false;
        });
    }

    function focusTaskSwitcherTargetWindow() {
        const mon = AxctlService.focusedMonitor;
        if (!mon)
            return;
        const wsId = mon.activeWorkspace?.id;
        if (wsId === null || wsId === undefined)
            return;
        const monId = mon.id ?? -1;
        const clients = AxctlService.clients.values || [];
        const list = [];
        for (let i = 0; i < clients.length; i++) {
            const win = clients[i];
            if (!win || !win.workspace)
                continue;
            if (Number(win.workspace.id) !== Number(wsId))
                continue;
            if (monId >= 0 && win.monitor !== undefined && win.monitor !== null && Number(win.monitor) !== Number(monId))
                continue;
            list.push(win);
        }
        list.sort((a, b) => {
            const af = a.focusHistoryID ?? Number.MAX_SAFE_INTEGER;
            const bf = b.focusHistoryID ?? Number.MAX_SAFE_INTEGER;
            if (af !== bf)
                return af - bf;
            return String(a.title || "").localeCompare(String(b.title || ""));
        });
        if (list.length === 0)
            return;
        const target = list.length > 1 ? list[1] : list[0];
        AxctlService.focusWindow(target.address, target.workspace ? target.workspace.id : undefined);
    }

    function armHoldInvariantChecks() {
        Qt.callLater(() => enforceTaskSwitcherHoldInvariant());
        holdInvariantTimer16.restart();
        holdInvariantTimer50.restart();
        holdInvariantTimer100.restart();
    }

    function enforceTaskSwitcherHoldInvariant() {
        if (Visibilities.currentActiveModule !== "taskswitcher")
            return;
        if (GlobalStates.taskSwitcherPendingConfirm) {
            // Popup may still consume via confirmRequest; only force if still pending next tick.
            Qt.callLater(() => {
                if (GlobalStates.taskSwitcherPendingConfirm && Visibilities.currentActiveModule === "taskswitcher")
                    confirmTaskSwitcherNow();
            });
            return;
        }
        probeHoldModifierDown();
    }

    function startHoldInvariantPolling() {
        if (!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
            return;
        holdInvariantPollTimer.restart();
    }

    function stopHoldInvariantPolling() {
        holdInvariantPollTimer.stop();
        if (holdModifierProbe.running)
            holdModifierProbe.running = false;
    }

    function probeHoldModifierDown() {
        if (Visibilities.currentActiveModule !== "taskswitcher")
            return;
        if (!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
            return;
        if (holdModifierProbe.running)
            return;
        const keys = KeybindActions.taskSwitcherReleaseKeys(taskSwitcherHoldModifier());
        if (!keys.length)
            return;
        const expr = keys.map(k => 'hl.is_key_down("' + k + '")').join(" or ");
        holdModifierProbe.command = ["hyprctl", "repl", "return (" + expr + ') and "down" or "up"'];
        holdModifierProbe.running = true;
    }

    // Emitted after each hyprctl is_key_down probe while the switcher is active.
    signal holdModifierProbeResult(bool held)

    property Process holdModifierProbe: Process {
        running: false
        stdout: SplitParser {
            onRead: data => {
                const s = String(data).trim().toLowerCase();
                // Require an explicit token; ignore empty/error output so we never false-close.
                if (s.indexOf("down") >= 0) {
                    root.holdModifierProbeResult(true);
                    return;
                }
                if (s.indexOf("up") >= 0) {
                    if (Visibilities.currentActiveModule === "taskswitcher") {
                        // Prefer Popup confirm (keeps advanced selection); failsafe closes if Loader lags.
                        root.confirmTaskSwitcher();
                    }
                    root.holdModifierProbeResult(false);
                }
            }
        }
    }

    property Timer holdInvariantPollTimer: Timer {
        interval: 32
        repeat: true
        onTriggered: {
            if (Visibilities.currentActiveModule !== "taskswitcher") {
                stop();
                return;
            }
            root.enforceTaskSwitcherHoldInvariant();
        }
    }

    property Timer holdInvariantTimer16: Timer {
        interval: 16
        repeat: false
        onTriggered: root.enforceTaskSwitcherHoldInvariant()
    }

    property Timer holdInvariantTimer50: Timer {
        interval: 50
        repeat: false
        onTriggered: root.enforceTaskSwitcherHoldInvariant()
    }

    property Timer holdInvariantTimer100: Timer {
        interval: 100
        repeat: false
        onTriggered: root.enforceTaskSwitcherHoldInvariant()
    }

    property Timer pendingConfirmExpire: Timer {
        interval: 500
        repeat: false
        onTriggered: {
            // Only drop stale confirms when the switcher never became active.
            if (Visibilities.currentActiveModule !== "taskswitcher")
                GlobalStates.taskSwitcherPendingConfirm = false;
        }
    }

    property Connections taskSwitcherModuleConnections: Connections {
        target: Visibilities
        function onCurrentActiveModuleChanged() {
            if (Visibilities.currentActiveModule === "taskswitcher") {
                root.startHoldInvariantPolling();
                root.armHoldInvariantChecks();
                root.flushPendingTaskSwitcherConfirm();
            } else {
                root.stopHoldInvariantPolling();
            }
        }
    }

    function toggleLauncher() {
        if (taskSwitcherConfirmedAt > 0 && (Date.now() - taskSwitcherConfirmedAt) < 400)
            return;
        const isActive = Visibilities.currentActiveModule === "launcher";
        if (isActive && GlobalStates.widgetsTabCurrentIndex === 0 && GlobalStates.launcherSearchText === "") {
            Visibilities.setActiveModule("");
        } else {
            GlobalStates.widgetsTabCurrentIndex = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("launcher");
            }
        }
    }

    function toggleLauncherWithPrefix(tabIndex, prefix) {
        const isActive = Visibilities.currentActiveModule === "launcher";
        const currentTab = GlobalStates.widgetsTabCurrentIndex;
        const currentText = GlobalStates.launcherSearchText;

        if (isActive && currentTab === tabIndex && (currentText === prefix || currentText === "")) {
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        GlobalStates.widgetsTabCurrentIndex = tabIndex;
        GlobalStates.launcherSearchText = prefix;
        
        if (!isActive) {
            Visibilities.setActiveModule("launcher");
        }
    }

    function toggleDashboardTab(tabIndex) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        // Special handling for widgets tab (launcher)
        if (tabIndex === 0) {
            if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === "") {
                // Only toggle off if we're already in launcher without prefix
                Visibilities.setActiveModule("");
                return;
            }
            
            // Otherwise, always go to launcher (clear any prefix and ensure tab 0)
            GlobalStates.dashboardCurrentTab = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("dashboard");
            }
            return;
        }
        
        // For other tabs, normal toggle behavior
        if (isActive && GlobalStates.dashboardCurrentTab === tabIndex) {
            Visibilities.setActiveModule("");
            return;
        }

        GlobalStates.dashboardCurrentTab = tabIndex;
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
        }
    }

    function toggleDashboardWithPrefix(prefix) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === prefix) {
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        GlobalStates.dashboardCurrentTab = 0;
        
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
            Qt.callLater(() => {
                GlobalStates.launcherSearchText = prefix;
            });
        } else {
            GlobalStates.launcherSearchText = prefix;
        }
    }

    function toggleAssistant() {
        GlobalStates.toggleAssistant();
    }
    function seekActivePlayer(offset) {
        const player = MprisController.activePlayer;
        if (!player || !player.canSeek) {
            return;
        }

        const maxLength = typeof player.length === "number" && !isNaN(player.length)
                ? player.length
                : Number.MAX_SAFE_INTEGER;
        const clamped = Math.max(0, Math.min(maxLength, player.position + offset));
        player.position = clamped;
    }
}
