pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals
import qs.modules.theme

Singleton {
    id: root

    property bool available: false
    property bool enabled: false
    property bool discovering: false
    property bool connected: false
    property int connectedDevices: 0
    property bool agentReady: false
    property bool agentDefault: false
    property int uiActiveCount: 0
    readonly property bool uiActive: uiActiveCount > 0
    property string lastError: ""

    // Active BlueZ agent request surfaced to the UI (null when idle)
    // { id, kind, devicePath, address, name, code, entered, needsReply, numeric }
    property var pairingRequest: null

    readonly property list<BluetoothDevice> devices: []

    // Cached sorted device list - only updates when devices change
    property list<var> friendlyDeviceList: []

    // Queue for batching updateInfo calls
    property var pendingInfoUpdates: []
    property bool isProcessingInfoQueue: false
    property bool isUpdating: false
    property bool wasEnabledBeforeSleep: false

    readonly property string statusSummary: {
        if (!root.available)
            return "Bluetooth unavailable";
        if (!root.enabled)
            return "Bluetooth off";
        if (root.pairingRequest)
            return "Pairing...";
        if (root.connected) {
            const active = root.friendlyDeviceList.find(d => d?.connected);
            if (active?.name)
                return "Connected · " + active.name;
            return "Connected";
        }
        if (root.discovering)
            return "Scanning...";
        return "On";
    }

    readonly property string agentScriptPath: Quickshell.shellDir + "/scripts/bluetooth_agent.py"

    property var suspendConnections: Connections {
        target: SuspendManager
        function onPreparingForSleep() {
            root.wasEnabledBeforeSleep = root.enabled;
            if (discovering) {
                root.stopDiscovery();
            }
            scanTimer.stop();
            infoQueueTimer.stop();
            root.stopAgent();
        }
        function onWakingUp() {
            // Re-sync status after wake
            wakeSyncTimer.restart();

            // Restore state if it was enabled
            if (root.wasEnabledBeforeSleep) {
                root.setEnabled(true);
            }
            if (root.uiActive)
                root.ensureAgent();
        }
    }

    property var wakeSyncTimer: Timer {
        id: wakeSyncTimer
        interval: 3000
        repeat: false
        onTriggered: {
            root.updateStatus();
            if (root.enabled) {
                root.updateDevices();
            }
        }
    }

    function setUiActive(active: bool): void {
        if (active) {
            root.uiActiveCount += 1;
            agentIdleStopTimer.stop();
            root.ensureAgent();
            if (root.enabled)
                root.updateDevices();
        } else {
            root.uiActiveCount = Math.max(0, root.uiActiveCount - 1);
            if (root.uiActiveCount === 0 && !root.pairingRequest)
                agentIdleStopTimer.restart();
        }
    }

    function updateFriendlyList() {
        friendlyDeviceList = [...devices].sort((a, b) => {
            // Connected devices first
            if (a.connected && !b.connected)
                return -1;
            if (!a.connected && b.connected)
                return 1;
            // Then paired devices
            if (a.paired && !b.paired)
                return -1;
            if (!a.paired && b.paired)
                return 1;
            // Then by name
            return (a.name || "").localeCompare(b.name || "");
        });
    }

    function iconForDevice(device): string {
        const icon = device?.icon ?? "bluetooth";
        if (icon.includes("audio-headset") || icon.includes("headphone"))
            return Icons.headphones;
        if (icon.includes("input-keyboard"))
            return Icons.keyboard;
        if (icon.includes("input-mouse"))
            return Icons.mouse;
        if (icon.includes("phone"))
            return Icons.phone;
        if (icon.includes("watch"))
            return Icons.watch;
        if (icon.includes("input-gaming") || icon.includes("gamepad"))
            return Icons.gamepad;
        if (icon.includes("printer"))
            return Icons.printer;
        if (icon.includes("camera"))
            return Icons.camera;
        if (icon.includes("audio-speakers") || icon.includes("speaker"))
            return Icons.speaker;
        return Icons.bluetooth;
    }

    // Batch process info updates with delay between each
    function queueInfoUpdate(device: BluetoothDevice) {
        if (pendingInfoUpdates.indexOf(device) === -1) {
            pendingInfoUpdates.push(device);
        }
        if (!isProcessingInfoQueue) {
            processNextInfoUpdate();
        }
    }

    function processNextInfoUpdate() {
        if (pendingInfoUpdates.length === 0) {
            isProcessingInfoQueue = false;
            updateFriendlyList();
            return;
        }

        isProcessingInfoQueue = true;
        const device = pendingInfoUpdates.shift();
        if (device) {
            device.updateInfo();
        }
        // Process next after a small delay
        infoQueueTimer.restart();
    }

    Timer {
        id: infoQueueTimer
        interval: 50  // 50ms between each info request
        running: false
        repeat: false
        onTriggered: {
            if (!SuspendManager.isSuspending) {
                root.processNextInfoUpdate();
            }
        }
    }

    Component {
        id: asyncProcessComp
        Process {
            id: internalProc
            property var resolve
            property var reject
            property string buffer: ""
            property string errorBuffer: ""

            stdout: SplitParser {
                onRead: data => internalProc.buffer += data + "\n"
            }

            stderr: SplitParser {
                onRead: data => internalProc.errorBuffer += data + "\n"
            }

            onExited: (exitCode, exitStatus) => {
                if (exitCode === 0)
                    resolve(buffer.trim());
                else
                    reject(errorBuffer.trim() || `Process exited with code ${exitCode}`);
                destroy();
            }
        }
    }

    function runAsync(command, environment = {}) {
        return new Promise((resolve, reject) => {
            const proc = asyncProcessComp.createObject(root, {
                command: command,
                environment: environment,
                resolve: resolve,
                reject: reject
            });
            proc.running = true;
        });
    }

    // Control functions
    function setEnabled(value: bool): void {
        if (SuspendManager.isSuspending)
            return;
        isUpdating = true;
        runAsync(["bluetoothctl", "power", value ? "on" : "off"]).then(() => {
            updateStatus();
            if (value) {
                updateDevices();
                ensureAgent();
            } else {
                stopDiscovery();
                clearPairingRequest();
            }
            isUpdating = false;
        }).catch(e => {
            root.lastError = String(e || "Failed to toggle Bluetooth");
            isUpdating = false;
        });
    }

    function toggle(): void {
        setEnabled(!enabled);
    }

    function startDiscovery(): void {
        if (enabled && !SuspendManager.isSuspending) {
            discovering = true;
            ensureAgent();
            runAsync(["bluetoothctl", "scan", "on"]).then(() => {
                scanTimer.restart();
                updateDevices();
            }).catch(e => {
                discovering = false;
            });
        }
    }

    function stopDiscovery(): void {
        discovering = false;
        runAsync(["bluetoothctl", "scan", "off"]).then(() => {
            scanTimer.stop();
        }).catch(e => {});
    }

    function connectDevice(address: string): void {
        isUpdating = true;
        ensureAgent();
        runAsync(["bluetoothctl", "connect", address]).then(() => {
            updateDevices();
            isUpdating = false;
        }).catch(e => {
            root.lastError = String(e || "Connect failed");
            isUpdating = false;
        });
    }

    function disconnectDevice(address: string): void {
        isUpdating = true;
        runAsync(["bluetoothctl", "disconnect", address]).then(() => {
            updateDevices();
            isUpdating = false;
        }).catch(e => {
            isUpdating = false;
        });
    }

    function pairDevice(address: string): void {
        isUpdating = true;
        ensureAgent();
        runAsync(["bluetoothctl", "pair", address]).then(() => {
            updateDevices();
            isUpdating = false;
        }).catch(e => {
            root.lastError = String(e || "Pair failed");
            isUpdating = false;
        });
    }

    function trustDevice(address: string): void {
        runAsync(["bluetoothctl", "trust", address]).catch(e => {});
    }

    function removeDevice(address: string): void {
        isUpdating = true;
        runAsync(["bluetoothctl", "remove", address]).then(() => {
            updateDevices();
            isUpdating = false;
        }).catch(e => {
            isUpdating = false;
        });
    }

    function clearPairingRequest(): void {
        root.pairingRequest = null;
        if (root.uiActiveCount === 0)
            agentIdleStopTimer.restart();
    }

    function submitPairingCode(code: string): void {
        const req = root.pairingRequest;
        if (!req || !req.needsReply)
            return;
        const value = (code || "").trim();
        if (!value)
            return;
        agentProcess.write(JSON.stringify({
            id: req.id,
            action: "submit",
            value: value
        }) + "\n");
        // Keep display requests; clear input requests after submit
        if (req.kind === "pin" || req.kind === "passkey")
            root.clearPairingRequest();
    }

    function confirmPairing(): void {
        const req = root.pairingRequest;
        if (!req || !req.needsReply)
            return;
        agentProcess.write(JSON.stringify({
            id: req.id,
            action: "confirm"
        }) + "\n");
        root.clearPairingRequest();
    }

    function rejectPairing(): void {
        const req = root.pairingRequest;
        if (!req)
            return;
        if (req.needsReply) {
            agentProcess.write(JSON.stringify({
                id: req.id,
                action: "reject"
            }) + "\n");
        }
        root.clearPairingRequest();
    }

    function dismissPairingDisplay(): void {
        const req = root.pairingRequest;
        if (!req || req.needsReply)
            return;
        root.clearPairingRequest();
    }

    function ensureAgent(): void {
        if (SuspendManager.isSuspending || !root.available)
            return;
        if (!agentProcess.running)
            agentProcess.running = true;
    }

    function stopAgent(): void {
        agentIdleStopTimer.stop();
        root.pairingRequest = null;
        root.agentReady = false;
        root.agentDefault = false;
        if (agentProcess.running) {
            try {
                agentProcess.write(JSON.stringify({
                    action: "quit"
                }) + "\n");
            } catch (e) {}
            agentStopTimer.restart();
        }
    }

    Timer {
        id: agentStopTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (agentProcess.running)
                agentProcess.running = false;
        }
    }

    // Release default agent shortly after Bluetooth UI closes (unless a prompt is open)
    Timer {
        id: agentIdleStopTimer
        interval: 8000
        repeat: false
        onTriggered: {
            if (root.uiActiveCount === 0 && !root.pairingRequest)
                root.stopAgent();
        }
    }

    Process {
        id: agentProcess
        command: ["python3", root.agentScriptPath]
        stdinEnabled: true
        running: false

        stdout: SplitParser {
            onRead: data => {
                const line = (data || "").trim();
                if (!line)
                    return;
                let msg = null;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                Qt.callLater(() => root.handleAgentMessage(msg));
            }
        }

        stderr: SplitParser {
            onRead: data => {
                const text = (data || "").trim();
                if (text)
                    console.warn("bluetooth_agent:", text);
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.agentReady = false;
            root.agentDefault = false;
            root.clearPairingRequest();
            if (root.uiActive && root.available && !SuspendManager.isSuspending)
                agentRestartTimer.restart();
        }
    }

    Timer {
        id: agentRestartTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.uiActive && root.available && !SuspendManager.isSuspending)
                root.ensureAgent();
        }
    }

    function handleAgentMessage(msg): void {
        if (!msg || !msg.event)
            return;

        if (msg.event === "ready") {
            root.agentReady = true;
            root.agentDefault = !!msg.defaultAgent;
            root.lastError = "";
            return;
        }

        if (msg.event === "warning") {
            root.lastError = msg.message || "Bluetooth agent warning";
            return;
        }

        if (msg.event === "error") {
            root.lastError = msg.message || "Bluetooth agent error";
            root.agentReady = false;
            return;
        }

        if (msg.event === "request") {
            agentIdleStopTimer.stop();
            root.pairingRequest = {
                id: msg.id,
                kind: msg.kind || "",
                devicePath: msg.devicePath || "",
                address: msg.address || "",
                name: msg.name || "Unknown device",
                code: msg.code || "",
                entered: msg.entered || 0,
                needsReply: !!msg.needsReply,
                numeric: !!msg.numeric
            };
            return;
        }

        if (msg.event === "cancel") {
            if (root.pairingRequest && root.pairingRequest.id === msg.id) {
                root.clearPairingRequest();
                if (root.uiActiveCount === 0)
                    agentIdleStopTimer.restart();
            }
            return;
        }

        if (msg.event === "released") {
            root.agentReady = false;
            root.clearPairingRequest();
        }
    }

    Timer {
        id: updateDebouncer
        interval: 200
        repeat: false
        onTriggered: root.performUpdate()
    }

    function updateStatus() {
        updateDebouncer.restart();
    }

    function performUpdate() {
        if (isUpdating)
            return;
        isUpdating = true;
        checkAvailableProcess.running = true;
    }

    // Timers
    Timer {
        id: updateTimer
        interval: 5000
        // Only poll when interface is visible
        running: root.enabled && !SuspendManager.isSuspending && (root.uiActive || GlobalStates.dashboardOpen || GlobalStates.launcherOpen || GlobalStates.overviewOpen)
        repeat: true
        onTriggered: root.updateDevices()
    }

    Timer {
        id: scanTimer
        interval: 15000
        running: false
        repeat: false
        onTriggered: root.stopDiscovery()
    }

    // Processes
    Process {
        id: checkAvailableProcess
        command: ["bash", "-c", "command -v bluetoothctl >/dev/null && bluetoothctl list 2>/dev/null | grep -q ."]
        running: false
        onExited: (exitCode, exitStatus) => {
            root.available = exitCode === 0;
            if (root.available) {
                checkPowerProcess.running = true;
            } else {
                root.enabled = false;
                root.connected = false;
                root.connectedDevices = 0;
                root.discovering = false;
                root.isUpdating = false;
            }
        }
    }

    Process {
        id: checkPowerProcess
        command: ["bash", "-c", "bluetoothctl show | grep 'Powered:' | awk '{print $2}'"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const output = data ? data.trim() : "";
                root.enabled = output === "yes";

                if (root.enabled) {
                    checkConnectedProcess.running = true;
                } else {
                    root.connected = false;
                    root.connectedDevices = 0;
                    root.discovering = false;
                    root.isUpdating = false;
                }
            }
        }
    }

    Process {
        id: checkConnectedProcess
        command: ["bash", "-c", "bluetoothctl devices Connected | wc -l"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const output = data ? data.trim() : "0";
                root.connectedDevices = parseInt(output) || 0;
                root.connected = root.connectedDevices > 0;
                root.isUpdating = false;
            }
        }
    }

    function updateDevices() {
        getDevicesProcess.running = true;
    }

    Process {
        id: getDevicesProcess
        command: ["bash", "-c", "bluetoothctl devices"]
        running: false
        property string buffer: ""
        environment: ({
            LANG: "C.UTF-8",
            LC_ALL: "C.UTF-8"
        })
        stdout: SplitParser {
            onRead: data => {
                getDevicesProcess.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            const text = getDevicesProcess.buffer;
            getDevicesProcess.buffer = "";

            Qt.callLater(() => {
                const deviceLines = text.trim().split("\n").filter(l => l.startsWith("Device "));
                const deviceDataList = [];
                for (let i = 0; i < deviceLines.length; i++) {
                    const line = deviceLines[i];
                    const parts = line.split(" ");
                    if (parts.length < 2)
                        continue;
                    deviceDataList.push({
                        address: parts[1],
                        name: parts.slice(2).join(" ") || "Unknown"
                    });
                }

                const rDevices = root.devices;

                // 1. Remove gone devices
                for (let i = rDevices.length - 1; i >= 0; i--) {
                    const rd = rDevices[i];
                    if (!deviceDataList.find(d => d.address === rd.address)) {
                        rDevices.splice(i, 1);
                        rd.destroy();
                    }
                }

                // 2. Add or update devices
                for (let i = 0; i < deviceDataList.length; i++) {
                    const data = deviceDataList[i];
                    const existing = rDevices.find(d => d.address === data.address);
                    if (existing) {
                        if (existing.name !== data.name) {
                            existing.name = data.name;
                        }
                        root.queueInfoUpdate(existing);
                    } else {
                        const newDevice = deviceComp.createObject(root, {
                            address: data.address,
                            name: data.name
                        });
                        rDevices.push(newDevice);
                        root.queueInfoUpdate(newDevice);
                    }
                }

                if (deviceDataList.length === 0) {
                    root.updateFriendlyList();
                }
            });
        }
    }

    Component {
        id: deviceComp
        BluetoothDevice {}
    }

    property bool _initialized: false

    function initialize() {
        if (_initialized)
            return;
        _initialized = true;
        updateStatus();
    }

    // Keep availability fresh even when powered off
    Timer {
        id: availabilityTimer
        interval: 15000
        running: true
        repeat: true
        onTriggered: {
            if (!SuspendManager.isSuspending)
                checkAvailableProcess.running = true;
        }
    }

    Component.onCompleted: {
        checkAvailableProcess.running = true;
    }
}
