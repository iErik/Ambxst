import QtQuick
import Quickshell.Io
import qs.config
import qs.modules.globals
import "../../config/KeybindActions.js" as KeybindActions

QtObject {
    id: root

    property Process compositorProcess: Process {}

    property var previousAmbxstBinds: ({})
    property var previousCustomBinds: []
    property bool hasPreviousBinds: false

    property Timer applyTimer: Timer {
        interval: 100
        repeat: false
        onTriggered: applyKeybindsInternal()
    }

    function applyKeybinds() {
        applyTimer.restart();
    }

    // Helper function to check if an action is compatible with the current layout
    function isActionCompatibleWithLayout(action) {
        // If no layouts specified or empty array, action works in all layouts
        if (!action.layouts || action.layouts.length === 0)
            return true;

        // Check if current layout is in the allowed list
        const currentLayout = GlobalStates.compositorLayout;
        return action.layouts.indexOf(currentLayout) !== -1;
    }

    function cloneKeybind(keybind) {
        return {
            modifiers: keybind.modifiers ? keybind.modifiers.slice() : [],
            key: keybind.key || ""
        };
    }

    function storePreviousBinds() {
        if (!Config.keybindsLoader.loaded)
            return;

        const ambxst = Config.keybindsLoader.adapter.ambxst;

        // Store ambxst core keybinds
        previousAmbxstBinds = {
            ambxst: {
                launcher: cloneKeybind(ambxst.launcher),
                dashboard: cloneKeybind(ambxst.dashboard),
                assistant: cloneKeybind(ambxst.assistant),
                clipboard: cloneKeybind(ambxst.clipboard),
                emoji: cloneKeybind(ambxst.emoji),
                notes: cloneKeybind(ambxst.notes),
                tmux: cloneKeybind(ambxst.tmux),
                wallpapers: cloneKeybind(ambxst.wallpapers)
            },
            system: {
                overview: cloneKeybind(ambxst.system.overview),
                powermenu: cloneKeybind(ambxst.system.powermenu),
                config: cloneKeybind(ambxst.system.config),
                lockscreen: cloneKeybind(ambxst.system.lockscreen),
                tools: cloneKeybind(ambxst.system.tools),
                togglebar: ambxst.system.togglebar ? cloneKeybind(ambxst.system.togglebar) : null,
                screenshot: cloneKeybind(ambxst.system.screenshot),
                screenrecord: cloneKeybind(ambxst.system.screenrecord),
                lens: cloneKeybind(ambxst.system.lens),
                reload: ambxst.system.reload ? cloneKeybind(ambxst.system.reload) : null,
                quit: ambxst.system.quit ? cloneKeybind(ambxst.system.quit) : null
            }
        };

        // Store custom keybinds
        const customBinds = Config.keybindsLoader.adapter.custom;
        previousCustomBinds = [];
        if (customBinds && customBinds.length > 0) {
            for (let i = 0; i < customBinds.length; i++) {
                const bind = customBinds[i];
                if (bind.keys) {
                    let keys = [];
                    for (let k = 0; k < bind.keys.length; k++) {
                        keys.push(cloneKeybind(bind.keys[k]));
                    }
                    previousCustomBinds.push({
                        keys: keys
                    });
                } else {
                    previousCustomBinds.push(cloneKeybind(bind));
                }
            }
        }

        hasPreviousBinds = true;
    }

    // Build an unbind target object (modifiers + key only).
    function makeUnbindTarget(keybind) {
        if (!keybind || !keybind.key)
            return null;
        return {
            modifiers: keybind.modifiers || [],
            key: keybind.key || ""
        };
    }

    function pushUnbind(payload, keybind) {
        const target = makeUnbindTarget(keybind);
        if (target)
            payload.unbinds.push(target);
    }

    // Build a structured bind object from a core keybind (has all fields inline).
    function resolveBindAction(action, fallback) {
        const resolved = KeybindActions.resolveAction(action || fallback);
        if (!resolved) return null;
        return {
            dispatcher: resolved.dispatcher || "",
            argument: resolved.argument || "",
            flags: resolved.flags || ""
        };
    }

    function makeBindFromCore(keybind) {
        if (!keybind || !keybind.key)
            return null;
        const resolved = resolveBindAction(keybind.action, keybind);
        if (!resolved) return null;
        return {
            modifiers: keybind.modifiers || [],
            key: keybind.key || "",
            dispatcher: resolved.dispatcher,
            argument: resolved.argument,
            flags: resolved.flags,
            enabled: true
        };
    }

    // Build a structured bind object from a key + action pair (custom keybinds).
    function makeBindFromKeyAction(keyObj, action) {
        const resolved = resolveBindAction(action, action);
        if (!resolved) return null;
        return {
            modifiers: keyObj.modifiers || [],
            key: keyObj.key || "",
            dispatcher: resolved.dispatcher,
            argument: resolved.argument,
            flags: resolved.flags,
            enabled: true
        };
    }

    function applyKeybindsInternal() {
        // Ensure adapter is loaded.
        if (!Config.keybindsLoader.loaded) {
            console.log("CompositorKeybinds: Esperando que se cargue el adapter...");
            return;
        }

        // Wait for layout to be ready.
        if (!GlobalStates.compositorLayoutReady) {
            console.log("CompositorKeybinds: Esperando que se detecte el layout de AxctlService...");
            return;
        }

        console.log("CompositorKeybinds: Aplicando keybindings (layout: " + GlobalStates.compositorLayout + ")...");

        // Build structured payload.
        let payload = { binds: [], unbinds: [] };

        // First, unbind previous keybinds if we have them stored
        if (hasPreviousBinds) {
            // Unbind previous ambxst core keybinds
            if (previousAmbxstBinds.ambxst) {
                pushUnbind(payload, previousAmbxstBinds.ambxst.launcher);
                pushUnbind(payload, previousAmbxstBinds.ambxst.dashboard);
                pushUnbind(payload, previousAmbxstBinds.ambxst.assistant);
                pushUnbind(payload, previousAmbxstBinds.ambxst.clipboard);
                pushUnbind(payload, previousAmbxstBinds.ambxst.emoji);
                pushUnbind(payload, previousAmbxstBinds.ambxst.notes);
                pushUnbind(payload, previousAmbxstBinds.ambxst.tmux);
                pushUnbind(payload, previousAmbxstBinds.ambxst.wallpapers);
            }

            // Unbind previous ambxst system keybinds
            if (previousAmbxstBinds.system) {
                pushUnbind(payload, previousAmbxstBinds.system.overview);
                pushUnbind(payload, previousAmbxstBinds.system.powermenu);
                pushUnbind(payload, previousAmbxstBinds.system.config);
                pushUnbind(payload, previousAmbxstBinds.system.lockscreen);
                pushUnbind(payload, previousAmbxstBinds.system.tools);
                pushUnbind(payload, previousAmbxstBinds.system.togglebar);
                pushUnbind(payload, previousAmbxstBinds.system.screenshot);
                pushUnbind(payload, previousAmbxstBinds.system.screenrecord);
                pushUnbind(payload, previousAmbxstBinds.system.lens);
                pushUnbind(payload, previousAmbxstBinds.system.reload);
                pushUnbind(payload, previousAmbxstBinds.system.quit);
            }

            // Unbind previous custom keybinds
            for (let i = 0; i < previousCustomBinds.length; i++) {
                const prev = previousCustomBinds[i];
                if (prev.keys) {
                    for (let k = 0; k < prev.keys.length; k++) {
                        pushUnbind(payload, prev.keys[k]);
                    }
                } else {
                    pushUnbind(payload, prev);
                }
            }
        }

        // Process core keybinds.
        const ambxst = Config.keybindsLoader.adapter.ambxst;

        // Unbind current core keybinds (ensures clean state before rebinding)
        pushUnbind(payload, ambxst.launcher);
        pushUnbind(payload, ambxst.dashboard);
        pushUnbind(payload, ambxst.assistant);
        pushUnbind(payload, ambxst.clipboard);
        pushUnbind(payload, ambxst.emoji);
        pushUnbind(payload, ambxst.notes);
        pushUnbind(payload, ambxst.tmux);
        pushUnbind(payload, ambxst.wallpapers);

        // Bind current core keybinds
        [ambxst.launcher, ambxst.dashboard, ambxst.assistant, ambxst.clipboard, ambxst.emoji, ambxst.notes, ambxst.tmux, ambxst.wallpapers].forEach(bind => {
            const resolved = makeBindFromCore(bind);
            if (resolved) payload.binds.push(resolved);
        });

        // System keybinds
        const system = ambxst.system;

        // Unbind current system keybinds
        pushUnbind(payload, system.overview);
        pushUnbind(payload, system.powermenu);
        pushUnbind(payload, system.config);
        pushUnbind(payload, system.lockscreen);
        pushUnbind(payload, system.tools);
        pushUnbind(payload, system.togglebar);
        pushUnbind(payload, system.screenshot);
        pushUnbind(payload, system.screenrecord);
        pushUnbind(payload, system.lens);
        pushUnbind(payload, system.reload);
        pushUnbind(payload, system.quit);

        // Bind current system keybinds
        [system.overview, system.powermenu, system.config, system.lockscreen, system.tools, system.togglebar, system.screenshot, system.screenrecord, system.lens, system.reload, system.quit].forEach(bind => {
            if (!bind) return;
            const resolved = makeBindFromCore(bind);
            if (resolved) payload.binds.push(resolved);
        });

        // Process custom keybinds (keys[] and actions[] format).
        const customBinds = Config.keybindsLoader.adapter.custom;
        if (customBinds && customBinds.length > 0) {
            for (let i = 0; i < customBinds.length; i++) {
                const bind = customBinds[i];

                // Check if bind has the new format
                if (bind.keys && bind.actions) {
                    // Unbind all keys first (always unbind regardless of layout)
                    for (let k = 0; k < bind.keys.length; k++) {
                        payload.unbinds.push(makeUnbindTarget(bind.keys[k]));
                    }

                    // Only create binds if enabled
                    if (bind.enabled !== false) {
                        // For each key, bind only compatible actions
                        for (let k = 0; k < bind.keys.length; k++) {
                            for (let a = 0; a < bind.actions.length; a++) {
                                const action = bind.actions[a];
                                // Check if this action is compatible with the current layout
                                if (isActionCompatibleWithLayout(action)) {
                                    const resolved = makeBindFromKeyAction(bind.keys[k], action);
                                    if (resolved) payload.binds.push(resolved);
                                }
                            }
                        }
                    }
                } else {
                    // Fallback for old format (shouldn't happen after normalization)
                    payload.unbinds.push(makeUnbindTarget(bind));
                    if (bind.enabled !== false) {
                        const resolved = makeBindFromCore(bind);
                        if (resolved) payload.binds.push(resolved);
                    }
                }
            }
        }

        storePreviousBinds();

        // Send structured payload via axctl keybinds-batch.
        console.log("CompositorKeybinds: Enviando keybinds-batch (" + payload.unbinds.length + " unbinds, " + payload.binds.length + " binds)");
        compositorProcess.command = ["axctl", "config", "keybinds-batch", JSON.stringify(payload)];
        compositorProcess.running = true;
    }

    property Connections configConnections: Connections {
        target: Config.keybindsLoader
        function onFileChanged() {
            applyKeybinds();
        }
        function onLoaded() {
            applyKeybinds();
        }
        function onAdapterUpdated() {
            applyKeybinds();
        }
    }

    // Re-apply keybinds when layout changes
    property Connections globalStatesConnections: Connections {
        target: GlobalStates
        function onCompositorLayoutChanged() {
            console.log("CompositorKeybinds: Layout changed to " + GlobalStates.compositorLayout + ", reapplying keybindings...");
            applyKeybinds();
        }
        function onCompositorLayoutReadyChanged() {
            if (GlobalStates.compositorLayoutReady) {
                applyKeybinds();
            }
        }
    }

    // property Connections compositorConnections: Connections {
    //     target: AxctlService
    //     function onRawEvent(event) {
    //         if (event.name === "configreloaded") {
    //             console.log("CompositorKeybinds: Detectado configreloaded, reaplicando keybindings...");
    //             applyKeybinds();
    //         }
    //     }
    // }

    Component.onCompleted: {
        // Apply immediately if loader is ready.
        if (Config.keybindsLoader.loaded) {
            applyKeybinds();
        }
    }
}
