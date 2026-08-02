pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool available: false
    property bool running: false
    property bool mounted: false
    property bool syncing: false
    property string statusText: "Unknown"
    property string drivePath: ""
    property string username: ""
    property string lastError: ""

    property real quotaTotal: 0
    property real quotaUsed: 0
    property real quotaFree: 0

    property int uploadCount: 0
    property int downloadCount: 0
    property int transferCount: 0
    property var transfers: []

    property bool _initialized: false
    property bool _refreshing: false

    readonly property real usageRatio: {
        if (root.quotaTotal <= 0)
            return 0;
        return Math.min(1, Math.max(0, root.quotaUsed / root.quotaTotal));
    }

    readonly property string usageSummary: {
        if (root.quotaTotal <= 0)
            return "Quota unknown";
        return root.formatBytes(root.quotaUsed) + " / " + root.formatBytes(root.quotaTotal)
                 + " · " + root.formatBytes(root.quotaFree) + " free";
    }

    readonly property string statusSummary: {
        if (!root.available)
            return "pCloud not installed";
        if (root.syncing) {
            const parts = [];
            if (root.uploadCount > 0)
                parts.push(root.uploadCount + " up");
            if (root.downloadCount > 0)
                parts.push(root.downloadCount + " down");
            if (parts.length === 0)
                parts.push(root.transferCount + " transfer" + (root.transferCount === 1 ? "" : "s"));
            return "Syncing · " + parts.join(" · ");
        }
        if (root.mounted)
            return root.usageSummary !== "Quota unknown" ? ("Connected · " + root.usageSummary) : "Connected";
        return root.statusText || "Offline";
    }

    function initialize() {
        if (_initialized)
            return;
        _initialized = true;
        checkAvailable();
    }

    function checkAvailable() {
        checkAvailableProcess.running = true;
    }

    function refreshStatus() {
        if (!root.available || root._refreshing)
            return;
        root._refreshing = true;
        statusProcess.running = true;
    }

    function openDrive() {
        const path = root.drivePath && root.drivePath.length > 0
            ? root.drivePath
            : (Quickshell.env("HOME") + "/pCloudDrive");
        Quickshell.execDetached(["xdg-open", path]);
    }

    function formatBytes(bytes) {
        const n = Number(bytes) || 0;
        if (n < 1024)
            return Math.round(n) + " B";
        const units = ["KB", "MB", "GB", "TB", "PB"];
        let v = n / 1024;
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        const digits = v >= 100 ? 0 : (v >= 10 ? 1 : 2);
        return v.toFixed(digits) + " " + units[i];
    }

    function applyStatus(data) {
        if (!data || typeof data !== "object")
            return;

        root.available = !!data.available;
        root.running = !!data.running;
        root.mounted = !!data.mounted;
        root.syncing = !!data.syncing;
        root.statusText = data.status || root.statusText;
        root.drivePath = data.drivePath || root.drivePath || (Quickshell.env("HOME") + "/pCloudDrive");
        root.username = data.username || "";
        root.quotaTotal = Number(data.quotaTotal) || 0;
        root.quotaUsed = Number(data.quotaUsed) || 0;
        root.quotaFree = Number(data.quotaFree) || 0;
        root.uploadCount = Number(data.uploadCount) || 0;
        root.downloadCount = Number(data.downloadCount) || 0;
        root.transferCount = Number(data.transferCount) || 0;

        const list = Array.isArray(data.transfers) ? data.transfers : [];
        Qt.callLater(() => {
            root.transfers = list;
        });

        pollTimer.interval = root.syncing ? 5000 : 15000;
    }

    Process {
        id: checkAvailableProcess
        command: ["bash", "-c", "command -v pcloud >/dev/null 2>&1 || command -v pcloudcc >/dev/null 2>&1 || test -x /opt/pcloud/pCloud.AppImage || test -d \"$HOME/.pcloud\" || test -d \"$HOME/pCloudDrive\""]
        running: false
        onExited: exitCode => {
            root.available = (exitCode === 0);
            if (root.available) {
                root.refreshStatus();
                pollTimer.restart();
            } else {
                root.running = false;
                root.mounted = false;
                root.syncing = false;
                root.statusText = "Unavailable";
                root.transfers = [];
                root.transferCount = 0;
            }
        }
    }

    Process {
        id: statusProcess
        command: ["python3", Quickshell.shellDir + "/scripts/pcloud_status.py"]
        running: false
        property string buffer: ""
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: SplitParser {
            onRead: data => {
                statusProcess.buffer += data + "\n";
            }
        }
        stderr: SplitParser {
            onRead: data => {
                // Keep stderr for diagnostics only
                if (data && data.length)
                    root.lastError = String(data).trim();
            }
        }
        onRunningChanged: {
            if (running)
                statusProcess.buffer = "";
        }
        onExited: exitCode => {
            const text = statusProcess.buffer.trim();
            statusProcess.buffer = "";
            root._refreshing = false;

            if (!text) {
                if (exitCode !== 0)
                    root.statusText = "Unavailable";
                return;
            }

            // Prefer the last non-empty line (script emits one JSON object)
            const lines = text.split("\n").map(l => l.trim()).filter(Boolean);
            const payload = lines.length ? lines[lines.length - 1] : text;
            try {
                const data = JSON.parse(payload);
                root.applyStatus(data);
            } catch (e) {
                root.lastError = "Failed to parse pCloud status";
                console.warn("Pcloud: parse error:", e);
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 15000
        repeat: true
        running: root.available && !SuspendManager.isSuspending
        onTriggered: root.refreshStatus()
    }

    // Occasional re-check in case pCloud is installed after startup
    Timer {
        interval: 120000
        repeat: true
        running: !root.available
        onTriggered: root.checkAvailable()
    }

    Component.onCompleted: {
        Qt.callLater(() => root.initialize());
    }
}
