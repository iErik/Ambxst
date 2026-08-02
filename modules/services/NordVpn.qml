pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool available: false
    property bool busy: false
    property bool connected: false
    property string statusText: "Unknown"
    property string country: ""
    property string city: ""
    property string server: ""
    property string ip: ""
    property string lastError: ""
    property string selectedCountry: ""

    property var countries: []
    property var cities: []
    property var groups: []
    property bool countriesLoaded: false
    property bool citiesLoading: false
    property bool groupsLoaded: false

    property bool _initialized: false

    readonly property string displayLocation: {
        if (!root.connected)
            return "";
        if (root.city && root.country)
            return root.city + ", " + root.country;
        return root.country || root.server || "";
    }

    readonly property string statusSummary: {
        if (!root.available)
            return "NordVPN not installed";
        if (root.busy)
            return root.connected ? "Disconnecting..." : "Connecting...";
        if (root.connected)
            return root.displayLocation ? ("Connected · " + root.displayLocation) : "Connected";
        return "Disconnected";
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
        if (!root.available)
            return;
        statusProcess.running = true;
    }

    function ensureCountries() {
        if (!root.available)
            return;
        if (root.countriesLoaded && root.countries.length > 0)
            return;
        countriesProcess.running = true;
    }

    function ensureGroups() {
        if (!root.available)
            return;
        if (root.groupsLoaded && root.groups.length > 0)
            return;
        groupsProcess.running = true;
    }

    function loadCities(countryName) {
        if (!root.available || !countryName)
            return;
        root.selectedCountry = countryName;
        root.cities = [];
        root.citiesLoading = true;
        citiesProcess.command = ["nordvpn", "cities", normalizeConnectArg(countryName)];
        citiesProcess.running = true;
    }

    function clearCityBrowse() {
        root.selectedCountry = "";
        root.cities = [];
        root.citiesLoading = false;
    }

    function connectRecommended() {
        connectTo([]);
    }

    function connectToCountry(countryName) {
        if (!countryName)
            return;
        connectTo([normalizeConnectArg(countryName)]);
    }

    function connectToCity(countryName, cityName) {
        if (!countryName || !cityName)
            return;
        connectTo([normalizeConnectArg(countryName), normalizeConnectArg(cityName)]);
    }

    function connectToGroup(groupName) {
        if (!groupName)
            return;
        connectTo([normalizeConnectArg(groupName)]);
    }

    function connectTo(args) {
        if (!root.available || root.busy)
            return;
        root.busy = true;
        root.lastError = "";
        root._pendingAction = "connect";
        const cmd = ["nordvpn", "connect"].concat(args || []);
        actionProcess.command = cmd;
        actionProcess.running = true;
    }

    function disconnect() {
        if (!root.available || root.busy)
            return;
        root.busy = true;
        root.lastError = "";
        root._pendingAction = "disconnect";
        actionProcess.command = ["nordvpn", "disconnect"];
        actionProcess.running = true;
    }

    function toggleConnection() {
        if (root.connected)
            disconnect();
        else
            connectRecommended();
    }

    function normalizeConnectArg(value) {
        if (!value)
            return "";
        return String(value).trim().replace(/\s+/g, "_");
    }

    function displayName(value) {
        if (!value)
            return "";
        return String(value).replace(/_/g, " ");
    }

    function stripAnsi(text) {
        return String(text || "").replace(/\x1B\[[0-9;]*[A-Za-z]/g, "").replace(/\r/g, "");
    }

    function parseLocationList(text) {
        const cleaned = stripAnsi(text);
        const lines = cleaned.split("\n");
        const items = [];
        const seen = {};

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            if (!line)
                continue;
            if (/^(available|countries|cities|groups)\b/i.test(line))
                continue;
            if (/couldn't find|isn't running|permission denied|log\.Output/i.test(line))
                continue;

            let parts = line.split(/\s{2,}/).map(p => p.trim()).filter(Boolean);
            if (parts.length <= 1 && line.indexOf(",") !== -1)
                parts = line.split(",").map(p => p.trim()).filter(Boolean);
            if (parts.length <= 1 && /\t/.test(line))
                parts = line.split(/\t+/).map(p => p.trim()).filter(Boolean);
            if (parts.length === 0)
                parts = [line];

            for (let j = 0; j < parts.length; j++) {
                const token = parts[j].replace(/^[-•*]\s*/, "").trim();
                if (!token || token.length < 2)
                    continue;
                if (/^https?:\/\//i.test(token))
                    continue;
                const key = token.toLowerCase();
                if (seen[key])
                    continue;
                seen[key] = true;
                items.push(token);
            }
        }

        return items;
    }

    function parseStatus(text) {
        const cleaned = stripAnsi(text);
        const lines = cleaned.split("\n");
        let status = "";
        let country = "";
        let city = "";
        let server = "";
        let ip = "";

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line || line.indexOf(":") === -1)
                continue;
            const idx = line.indexOf(":");
            const key = line.slice(0, idx).trim().toLowerCase();
            const value = line.slice(idx + 1).trim();

            if (key === "status")
                status = value;
            else if (key === "country")
                country = value;
            else if (key === "city")
                city = value;
            else if (key === "server" || key === "current server" || key === "hostname")
                server = value;
            else if (key === "ip")
                ip = value;
        }

        const connected = /connected/i.test(status) && !/disconnected/i.test(status);
        root.connected = connected;
        root.statusText = status || (connected ? "Connected" : "Disconnected");
        root.country = connected ? country : "";
        root.city = connected ? city : "";
        root.server = connected ? server : "";
        root.ip = connected ? ip : "";
    }

    function notifyError(message) {
        root.lastError = message || "NordVPN command failed";
        if (typeof Notifications !== "undefined" && Notifications.notifyInternal) {
            Notifications.notifyInternal({
                "appName": "NordVPN",
                "summary": "NordVPN",
                "body": root.lastError,
                "replaceKey": "nordvpn-status",
                "expireTimeout": 6000
            });
        }
    }

    function notifyInfo(message) {
        if (typeof Notifications !== "undefined" && Notifications.notifyInternal) {
            Notifications.notifyInternal({
                "appName": "NordVPN",
                "summary": "NordVPN",
                "body": message,
                "replaceKey": "nordvpn-status",
                "expireTimeout": 4000
            });
        }
    }

    Process {
        id: checkAvailableProcess
        command: ["which", "nordvpn"]
        running: false
        onExited: exitCode => {
            root.available = (exitCode === 0);
            if (root.available) {
                root.refreshStatus();
                pollTimer.restart();
            } else {
                root.connected = false;
                root.statusText = "Unavailable";
            }
        }
    }

    Process {
        id: statusProcess
        command: ["nordvpn", "status"]
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
                statusProcess.buffer += data + "\n";
            }
        }
        onRunningChanged: {
            if (running)
                statusProcess.buffer = "";
        }
        onExited: exitCode => {
            const text = statusProcess.buffer;
            statusProcess.buffer = "";
            if (text && /Status:/i.test(text)) {
                root.parseStatus(text);
            } else if (exitCode !== 0) {
                // Daemon down / not logged in — keep available=true (binary exists)
                root.connected = false;
                if (/isn't running|nordvpnd\.sock/i.test(text))
                    root.statusText = "Daemon offline";
                else if (/not logged in|log in/i.test(text))
                    root.statusText = "Not logged in";
                else
                    root.statusText = "Unavailable";
            }
        }
    }

    Process {
        id: countriesProcess
        command: ["nordvpn", "countries"]
        running: false
        property string buffer: ""
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: SplitParser {
            onRead: data => {
                countriesProcess.buffer += data + "\n";
            }
        }
        stderr: SplitParser {
            onRead: data => {
                countriesProcess.buffer += data + "\n";
            }
        }
        onRunningChanged: {
            if (running)
                countriesProcess.buffer = "";
        }
        onExited: exitCode => {
            const text = countriesProcess.buffer;
            countriesProcess.buffer = "";
            if (exitCode === 0) {
                const list = root.parseLocationList(text);
                Qt.callLater(() => {
                    root.countries = list;
                    root.countriesLoaded = list.length > 0;
                });
            }
        }
    }

    Process {
        id: citiesProcess
        running: false
        property string buffer: ""
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: SplitParser {
            onRead: data => {
                citiesProcess.buffer += data + "\n";
            }
        }
        stderr: SplitParser {
            onRead: data => {
                citiesProcess.buffer += data + "\n";
            }
        }
        onRunningChanged: {
            if (running)
                citiesProcess.buffer = "";
        }
        onExited: exitCode => {
            const text = citiesProcess.buffer;
            citiesProcess.buffer = "";
            root.citiesLoading = false;
            if (exitCode === 0) {
                const list = root.parseLocationList(text);
                Qt.callLater(() => {
                    root.cities = list;
                });
            } else {
                root.cities = [];
            }
        }
    }

    Process {
        id: groupsProcess
        command: ["nordvpn", "groups"]
        running: false
        property string buffer: ""
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: SplitParser {
            onRead: data => {
                groupsProcess.buffer += data + "\n";
            }
        }
        stderr: SplitParser {
            onRead: data => {
                groupsProcess.buffer += data + "\n";
            }
        }
        onRunningChanged: {
            if (running)
                groupsProcess.buffer = "";
        }
        onExited: exitCode => {
            const text = groupsProcess.buffer;
            groupsProcess.buffer = "";
            if (exitCode === 0) {
                const list = root.parseLocationList(text);
                Qt.callLater(() => {
                    root.groups = list;
                    root.groupsLoaded = list.length > 0;
                });
            }
        }
    }

    property string _pendingAction: ""

    Process {
        id: actionProcess
        running: false
        property string buffer: ""
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: SplitParser {
            onRead: data => {
                actionProcess.buffer += data + "\n";
            }
        }
        stderr: SplitParser {
            onRead: data => {
                actionProcess.buffer += data + "\n";
            }
        }
        onRunningChanged: {
            if (running)
                actionProcess.buffer = "";
        }
        onExited: exitCode => {
            const text = root.stripAnsi(actionProcess.buffer).trim();
            const action = root._pendingAction;
            actionProcess.buffer = "";
            root._pendingAction = "";
            root.busy = false;
            root.refreshStatus();

            if (exitCode === 0) {
                if (action === "disconnect")
                    root.notifyInfo("Disconnected");
                else
                    root.notifyInfo(text || "Connected");
            } else {
                root.notifyError(text || "NordVPN command failed");
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

    // Occasional re-check in case NordVPN is installed after startup
    Timer {
        interval: 120000
        repeat: true
        running: !root.available
        onTriggered: root.checkAvailable()
    }

    Component.onCompleted: {
        // Lightweight: only binary check; full status follows if present
        Qt.callLater(() => root.initialize());
    }
}
