pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.modules.services
import qs.modules.theme
import qs.config

/**
 * Default Pipewire audio sink/source wrapper.
 * Handles volume, mute, app nodes, and devices.
 * Includes "ear-bang" protection against volume spikes.
 */
Singleton {
    id: root

    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00
    // PipeWire / GNOME-style soft ceiling when over-amplification is enabled
    readonly property real overAmplificationLimit: 1.5
    readonly property bool overAmplification: Config.audio?.overAmplification ?? false
    readonly property real maxVolume: overAmplification ? overAmplificationLimit : 1.0
    property real value: sink?.audio?.volume ?? 0

    // Volume protection (persisted)
    property bool protectionEnabled: true
    readonly property real maxVolumeJump: 0.15  // 15% max jump
    property bool protectionTriggered: false

    // Load state
    Connections {
        target: StateService
        function onStateLoaded() {
            root.protectionEnabled = StateService.get("volumeProtectionEnabled", true);
        }
    }

    // Persist protection
    function setProtectionEnabled(enabled: bool) {
        root.protectionEnabled = enabled;
        StateService.set("volumeProtectionEnabled", enabled);
    }

    function setOverAmplification(enabled: bool) {
        if (!Config.audio)
            return;
        if (Config.audio.overAmplification === enabled)
            return;
        Config.audio.overAmplification = enabled;
        if (!enabled)
            root.clampOutputToUnity();
    }

    function clampOutputToUnity() {
        if (sink?.audio && sink.audio.volume > 1)
            sink.audio.volume = 1;
    }

    function clampVolume(volume: real): real {
        return Math.max(0, Math.min(root.maxVolume, volume));
    }

    signal sinkProtectionTriggered(string reason);
    signal volumeChanged(real volume, bool muted, var node);
    signal micVolumeChanged(real volume, bool muted, var node);

    PwObjectTracker {
        objects: [sink, source]
    }

    // Volume signals for OSD
    Connections {
        target: root.sink?.audio ?? null
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            if (root.sink?.ready) {
                root.volumeChanged(root.sink.audio.volume, root.sink.audio.muted, root.sink);
            }
        }
        function onMutedChanged() {
            if (root.sink?.ready) {
                root.volumeChanged(root.sink.audio.volume, root.sink.audio.muted, root.sink);
            }
        }
    }

    Connections {
        target: root.source?.audio ?? null
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            if (root.source?.ready) {
                root.micVolumeChanged(root.source.audio.volume, root.source.audio.muted, root.source);
            }
        }
        function onMutedChanged() {
            if (root.source?.ready) {
                root.micVolumeChanged(root.source.audio.volume, root.source.audio.muted, root.source);
            }
        }
    }

    // Helpers
    function friendlyDeviceName(node) {
        return (node?.nickname || node?.description || "Unknown");
    }

    function appNodeDisplayName(node) {
        return (node?.properties?.["application.name"] || node?.description || node?.name || "Unknown");
    }

    // Node filters
    function correctType(node, isSink) {
        return (node?.isSink === isSink) && node?.audio;
    }

    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => {
            return root.correctType(node, isSink) && node.isStream;
        });
    }

    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream;
        });
    }

    // IO lists
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)
    readonly property bool available: sink !== null || source !== null
        || outputDevices.length > 0 || inputDevices.length > 0

    // Volume jump limiter
    function protectedSetVolume(node, targetVolume: real, currentVolume: real) {
        if (!root.protectionEnabled) {
            return targetVolume;
        }

        const jump = targetVolume - currentVolume;
        
        // Limit increases only
        if (jump <= 0) {
            root.protectionTriggered = false;
            return targetVolume;
        }

        // Limit excessive jumps
        if (jump > root.maxVolumeJump) {
            root.protectionTriggered = true;
            root.sinkProtectionTriggered("Volume jump limited");
            
            // Reset trigger after delay
            protectionResetTimer.restart();
            
            return currentVolume + root.maxVolumeJump;
        }

        root.protectionTriggered = false;
        return targetVolume;
    }

    Timer {
        id: protectionResetTimer
        interval: 1500
        onTriggered: root.protectionTriggered = false
    }

    // Controls
    function toggleMute() {
        if (sink?.audio) {
            sink.audio.muted = !sink.audio.muted;
        }
    }

    function toggleMicMute() {
        if (source?.audio) {
            source.audio.muted = !source.audio.muted;
        }
    }

    function incrementVolume() {
        if (sink?.audio) {
            const currentVolume = sink.audio.volume;
            const step = currentVolume < 0.1 ? 0.01 : 0.02;
            root.setVolume(currentVolume + step);
        }
    }

    function decrementVolume() {
        if (sink?.audio) {
            const currentVolume = sink.audio.volume;
            const step = currentVolume < 0.1 ? 0.01 : 0.02;
            root.setVolume(currentVolume - step);
        }
    }

    function setVolume(volume: real) {
        if (sink?.audio) {
            const current = sink.audio.volume;
            const safeVolume = protectedSetVolume(sink, root.clampVolume(volume), current);
            sink.audio.volume = root.clampVolume(safeVolume);
        }
    }

    function setMicVolume(volume: real) {
        if (source?.audio) {
            // Mic stays at unity max; over-amplification is an output feature
            source.audio.volume = Math.max(0, Math.min(1, volume));
        }
    }

    // Protected volume set
    function setNodeVolume(node, volume: real) {
        if (node?.audio) {
            // Output sinks can over-amplify; inputs stay at 100%
            const limit = (node.isSink === true) ? root.maxVolume : 1;
            const target = Math.max(0, Math.min(limit, volume));
            const current = node.audio.volume;
            const safeVolume = protectedSetVolume(node, target, current);
            node.audio.volume = Math.max(0, Math.min(limit, safeVolume));
        }
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Icon helper
    function volumeIcon(volume: real, muted: bool): string {
        if (muted) return Icons.speakerX;
        if (volume <= 0) return Icons.speakerNone;
        if (volume < 0.33) return Icons.speakerLow;
        return Icons.speakerHigh;
    }

    IpcHandler {
        target: "audio"

        function increment() {
            root.incrementVolume();
        }

        function decrement() {
            root.decrementVolume();
        }

        function toggleMute() {
            root.toggleMute();
        }

        function set(volume: real) {
            root.setVolume(volume);
        }
    }
}
