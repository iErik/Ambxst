pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.services

Singleton {
    id: root

    property var screens: ({})
    property var panels: ({})
    property var bars: ({})
    property var barPanels: ({})
    property var notches: ({})
    property var notchPanels: ({})
    property var docks: ({})
    property var dockPanels: ({})
    property string currentActiveModule: ""
    property string lastFocusedScreen: ""
    property var contextMenu: null
    property bool playerMenuOpen: false
    readonly property var moduleNames: ["launcher", "dashboard", "overview", "powermenu", "tools", "presets", "taskswitcher", "controlcenter"]

    function setContextMenu(menu) {
        contextMenu = menu;
    }

    function getForScreen(screenName) {
        if (!screens[screenName]) {
            screens[screenName] = screenPropertiesComponent.createObject(root, {
                screenName: screenName
            });
        }
        return screens[screenName];
    }

    function getForActive() {
        if (!AxctlService.focusedMonitor) {
            return null;
        }
        return getForScreen(AxctlService.focusedMonitor.name);
    }

    // Helper to clone map and trigger update
    // Drop `key`, unless it now belongs to someone other than `owner`: a panel
    // being torn down (screen re-added, reload) must not remove the entry its
    // replacement already registered.
    function _removeFromMap(map, key, owner) {
        if (owner !== undefined && map[key] !== owner)
            return map;
        return _updateMap(map, key, null);
    }

    function _updateMap(map, key, value) {
        var newMap = {};
        for (var k in map) {
            newMap[k] = map[k];
        }
        if (value === null) {
            delete newMap[key];
        } else {
            newMap[key] = value;
        }
        return newMap;
    }

    function registerPanel(screenName, panel) {
        panels = _updateMap(panels, screenName, panel);
    }

    function unregisterPanel(screenName, owner) {
        panels = _removeFromMap(panels, screenName, owner);
    }

    function registerBar(screenName, barContainer) {
        bars = _updateMap(bars, screenName, barContainer);
    }

    function unregisterBar(screenName, owner) {
        bars = _removeFromMap(bars, screenName, owner);
    }

    function getBarForScreen(screenName) {
        return bars[screenName] || null;
    }

    function registerBarPanel(screenName, barPanel) {
        barPanels = _updateMap(barPanels, screenName, barPanel);
    }

    function unregisterBarPanel(screenName, owner) {
        barPanels = _removeFromMap(barPanels, screenName, owner);
    }

    function getBarPanelForScreen(screenName) {
        return barPanels[screenName] || null;
    }

    function registerNotch(screenName, notchContainer) {
        notches = _updateMap(notches, screenName, notchContainer);
    }

    function unregisterNotch(screenName, owner) {
        notches = _removeFromMap(notches, screenName, owner);
    }

    function getNotchForScreen(screenName) {
        return notches[screenName] || null;
    }

    function registerNotchPanel(screenName, notchPanel) {
        notchPanels = _updateMap(notchPanels, screenName, notchPanel);
    }

    function unregisterNotchPanel(screenName, owner) {
        notchPanels = _removeFromMap(notchPanels, screenName, owner);
    }

    function getNotchPanelForScreen(screenName) {
        return notchPanels[screenName] || null;
    }

    function registerDock(screenName, dockContainer) {
        docks = _updateMap(docks, screenName, dockContainer);
    }

    function unregisterDock(screenName, owner) {
        docks = _removeFromMap(docks, screenName, owner);
    }

    function getDockForScreen(screenName) {
        return docks[screenName] || null;
    }

    function registerDockPanel(screenName, dockPanel) {
        dockPanels = _updateMap(dockPanels, screenName, dockPanel);
    }

    function unregisterDockPanel(screenName, owner) {
        dockPanels = _removeFromMap(dockPanels, screenName, owner);
    }

    function getDockPanelForScreen(screenName) {
        return dockPanels[screenName] || null;
    }

    function setActiveModule(moduleName) {
        const focusedMonitor = AxctlService.focusedMonitor;
        if (!focusedMonitor)
            return;

        const focusedScreenName = focusedMonitor.name;

        clearAll();

        if (moduleName) {
            currentActiveModule = moduleName;
            applyActiveModuleToScreen(focusedScreenName);
        } else {
            currentActiveModule = "";
        }

        lastFocusedScreen = focusedScreenName;
    }

    function moveActiveModuleToFocusedScreen() {
        const focusedMonitor = AxctlService.focusedMonitor;
        if (!focusedMonitor || !currentActiveModule)
            return;

        const newFocusedScreen = focusedMonitor.name;
        if (newFocusedScreen === lastFocusedScreen)
            return;

        clearAll();
        applyActiveModuleToScreen(newFocusedScreen);
        lastFocusedScreen = newFocusedScreen;
    }

    Component {
        id: screenPropertiesComponent
        QtObject {
            property string screenName
            property bool launcher: false
            property bool dashboard: false
            property bool overview: false
            property bool powermenu: false
            property bool tools: false
            property bool presets: false
            property bool taskswitcher: false
            property bool controlcenter: false
        }
    }

    function clearAll() {
        for (const screenName in screens) {
            const screenProps = screens[screenName];
            for (let i = 0; i < moduleNames.length; i++) {
                screenProps[moduleNames[i]] = false;
            }
        }
    }

    function applyActiveModuleToScreen(screenName) {
        if (!currentActiveModule)
            return;

        const screenProps = getForScreen(screenName);
        if (moduleNames.indexOf(currentActiveModule) !== -1) {
            screenProps[currentActiveModule] = true;
        }
    }

    // Monitor focus changes
    Connections {
        target: AxctlService
        function onFocusedMonitorChanged() {
            moveActiveModuleToFocusedScreen();
        }
    }
}
