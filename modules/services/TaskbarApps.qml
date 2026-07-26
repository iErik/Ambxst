pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.modules.services

Singleton {
    id: root

    // Check pin status
    function isPinned(appId) {
        const pinnedApps = Config.pinnedApps?.apps || [];
        return pinnedApps.some(id => id.toLowerCase() === appId.toLowerCase());
    }

    // Toggle pin
    function togglePin(appId) {
        let pinnedApps = Config.pinnedApps?.apps || [];
        const normalizedAppId = appId.toLowerCase();
        
        if (isPinned(appId)) {
            // Unpin
            Config.pinnedApps.apps = pinnedApps.filter(id => id.toLowerCase() !== normalizedAppId);
        } else {
            // Pin
            Config.pinnedApps.apps = pinnedApps.concat([appId]);
        }

        // Persist changes
        Config.savePinnedApps();
    }

    // Get entry
    function getDesktopEntry(appId) {
        if (!appId) return null;
        return DesktopEntries.heuristicLookup(appId) || null;
    }

    // Launch
    function launchApp(appId) {
        const entry = getDesktopEntry(appId);
        if (entry) {
            AppSearch.launchApp(entry);
        }
    }

    // Cache entries
    property var _appCache: ({})
    property var _previousKeys: []

    // Combined app list (all workspaces / screens)
    property list<var> apps: []

    // Debounce update
    Timer {
        id: updateTimer
        interval: 100
        repeat: false
        onTriggered: root._updateApps()
    }

    // Update on toplevel change
    Connections {
        target: ToplevelManager.toplevels
        function onObjectInsertedPost() {
            updateTimer.restart();
        }
        function onObjectRemovedPost() {
            updateTimer.restart();
        }
    }

    // Update on config change
    Connections {
        target: Config.pinnedApps ?? null
        function onAppsChanged() {
            updateTimer.restart();
        }
    }

    Connections {
        target: Config.dock ?? null
        function onIgnoredAppRegexesChanged() {
            updateTimer.restart();
        }
        function onFilterToActiveWorkspaceChanged() {
            updateTimer.restart();
        }
    }

    // Workspace / monitor changes (needed for per-screen dock filtering)
    Connections {
        target: AxctlService.clients ?? null
        function onValuesChanged() {
            updateTimer.restart();
        }
    }

    Connections {
        target: AxctlService.monitors ?? null
        function onValuesChanged() {
            updateTimer.restart();
        }
    }

    // Init
    Component.onCompleted: {
        _updateApps();
    }

    function _ignoredRegexes() {
        const ignoredRegexStrings = Config.dock?.ignoredAppRegexes ?? [];
        return ignoredRegexStrings.map(pattern => new RegExp(pattern, "i"));
    }

    function _matchToplevelForClient(win, allToplevels, usedToplevels) {
        const cls = win.class || "";
        if (!cls)
            return null;

        const candidates = [];
        for (let i = 0; i < allToplevels.length; i++) {
            const t = allToplevels[i];
            if (!t || !t.appId || usedToplevels.has(t))
                continue;
            if (t.appId.toLowerCase() === cls.toLowerCase())
                candidates.push(t);
        }

        if (candidates.length === 0)
            return null;
        if (candidates.length === 1)
            return candidates[0];
        return candidates.find(t => t.title === (win.title || "")) || candidates[0];
    }

    // Toplevels visible on the active workspace of the given screen
    function toplevelsForScreen(screen) {
        const mon = AxctlService.monitorFor(screen);
        if (!mon || !mon.activeWorkspace)
            return ToplevelManager.toplevels.values;

        const wsId = mon.activeWorkspace.id;
        const monId = mon.id;
        const clients = AxctlService.clients.values || [];
        const allToplevels = ToplevelManager.toplevels.values;
        const used = new Set();
        const result = [];

        for (let i = 0; i < clients.length; i++) {
            const win = clients[i];
            if (!win)
                continue;
            if ((win.workspace?.id ?? -1) !== wsId)
                continue;
            if ((win.monitor ?? -1) !== monId)
                continue;

            const toplevel = _matchToplevelForClient(win, allToplevels, used);
            if (toplevel) {
                used.add(toplevel);
                result.push(toplevel);
            }
        }

        return result;
    }

    function _buildAppsFromToplevels(toplevels) {
        var map = new Map();
        const pinnedApps = Config.pinnedApps?.apps ?? [];
        const ignoredRegexes = _ignoredRegexes();

        for (const appId of pinnedApps) {
            const key = appId.toLowerCase();
            if (!map.has(key)) {
                map.set(key, {
                    appId: appId,
                    pinned: true,
                    toplevels: []
                });
            }
        }

        var unpinnedRunningApps = [];
        for (let i = 0; i < toplevels.length; i++) {
            const toplevel = toplevels[i];
            if (!toplevel || ignoredRegexes.some(re => re.test(toplevel.appId)))
                continue;

            const key = toplevel.appId.toLowerCase();

            if (map.has(key)) {
                map.get(key).toplevels.push(toplevel);
            } else {
                const existing = unpinnedRunningApps.find(app => app.key === key);
                if (!existing) {
                    unpinnedRunningApps.push({
                        key: key,
                        appId: toplevel.appId,
                        toplevels: [toplevel]
                    });
                } else {
                    existing.toplevels.push(toplevel);
                }
            }
        }

        if (pinnedApps.length > 0 && unpinnedRunningApps.length > 0) {
            map.set("SEPARATOR", {
                appId: "SEPARATOR",
                pinned: false,
                toplevels: []
            });
        }

        for (const app of unpinnedRunningApps) {
            map.set(app.key, {
                appId: app.appId,
                pinned: false,
                toplevels: app.toplevels
            });
        }

        return map;
    }

    // Per-screen dock model: pinned apps + apps open on this screen's active workspace
    function appsForScreen(screen) {
        const filterEnabled = Config.dock?.filterToActiveWorkspace ?? true;

        // Ensure reactive dependencies for QML bindings
        void root.apps;
        void AxctlService.clients.values;
        void AxctlService.monitors.values;

        if (!filterEnabled || !screen)
            return root.apps;

        const localToplevels = toplevelsForScreen(screen);
        const map = _buildAppsFromToplevels(localToplevels);

        // Prefer cached TaskbarAppEntry objects when possible so buttons keep identity,
        // but always expose filtered toplevels for this screen/workspace.
        var values = [];
        for (const [key, value] of map) {
            if (_appCache[key]) {
                values.push({
                    appId: value.appId,
                    pinned: value.pinned,
                    toplevels: value.toplevels,
                    toplevelCount: value.toplevels.length
                });
            } else {
                values.push({
                    appId: value.appId,
                    pinned: value.pinned,
                    toplevels: value.toplevels,
                    toplevelCount: value.toplevels.length
                });
            }
        }
        return values;
    }

    function _updateApps() {
        const toplevels = ToplevelManager.toplevels.values;
        const map = _buildAppsFromToplevels(toplevels);

        var newKeys = Array.from(map.keys());

        // Cleanup entries
        for (const oldKey of _previousKeys) {
            if (!map.has(oldKey) && _appCache[oldKey]) {
                _appCache[oldKey].destroy();
                delete _appCache[oldKey];
            }
        }

        // Sync entries
        var values = [];
        for (const [key, value] of map) {
            if (_appCache[key]) {
                _appCache[key].toplevels = value.toplevels;
                _appCache[key].pinned = value.pinned;
                values.push(_appCache[key]);
            } else {
                const entry = appEntryComp.createObject(root, {
                    appId: value.appId,
                    toplevels: value.toplevels,
                    pinned: value.pinned
                });
                _appCache[key] = entry;
                values.push(entry);
            }
        }

        _previousKeys = newKeys;
        apps = values;
    }

    // App entry component
    component TaskbarAppEntry: QtObject {
        required property string appId
        property var toplevels: []
        property int toplevelCount: toplevels.length
        property bool pinned
    }
    
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}
