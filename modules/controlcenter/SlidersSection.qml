pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.bar
import qs.modules.globals
import qs.config

// Volume, microphone and brightness sliders (formerly the bar Controls popup).
Item {
    id: root

    // Screen whose monitor the brightness slider drives.
    required property var screen

    implicitHeight: 3 * 36 + 2 * 12

    ColumnLayout {
        id: slidersColumn
        anchors.fill: parent
        spacing: 12

        // Volume Slider
        ControlSliderRow {
            id: volumeRow
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.rightMargin: 8

            icon: {
                if (Audio.sink?.audio?.muted)
                    return Icons.speakerSlash;
                const vol = Audio.sink?.audio?.volume ?? 0;
                if (vol < 0.01)
                    return Icons.speakerX;
                if (vol < 0.19)
                    return Icons.speakerNone;
                if (vol < 0.49)
                    return Icons.speakerLow;
                return Icons.speakerHigh;
            }
            sliderValue: Audio.sink?.audio?.volume ?? 0
            maximum: Audio.maxVolume
            progressColor: {
                if (Audio.sink?.audio?.muted)
                    return Colors.outline;
                if ((Audio.sink?.audio?.volume ?? 0) > 1)
                    return Colors.warning;
                return Styling.srItem("overprimary");
            }
            wavy: true
            wavyAmplitude: Audio.sink?.audio?.muted ? 0.5 : 1.5 * Math.min(1, sliderValue)
            wavyFrequency: Audio.sink?.audio?.muted ? 1.0 : 8.0 * Math.min(1, sliderValue)

            onValueChanged: newValue => {
                Audio.setVolume(newValue);
            }

            onIconClicked: {
                if (Audio.sink?.audio) {
                    Audio.sink.audio.muted = !Audio.sink.audio.muted;
                }
            }

            Connections {
                target: Audio.sink?.audio ?? null
                ignoreUnknownSignals: true
                function onVolumeChanged() {
                    if (Audio.sink?.audio) {
                        volumeRow.sliderValue = Audio.sink.audio.volume;
                    }
                }
            }
        }

        // Microphone Slider
        ControlSliderRow {
            id: micRow
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.rightMargin: 8

            icon: Audio.source?.audio?.muted ? Icons.micSlash : Icons.mic
            sliderValue: Audio.source?.audio?.volume ?? 0
            progressColor: Audio.source?.audio?.muted ? Colors.outline : Styling.srItem("overprimary")
            wavy: true
            wavyAmplitude: Audio.source?.audio?.muted ? 0.5 : 1.5 * sliderValue
            wavyFrequency: Audio.source?.audio?.muted ? 1.0 : 8.0 * sliderValue

            onValueChanged: newValue => {
                Audio.setMicVolume(newValue);
            }

            onIconClicked: {
                if (Audio.source?.audio) {
                    Audio.source.audio.muted = !Audio.source.audio.muted;
                }
            }

            Connections {
                target: Audio.source?.audio ?? null
                ignoreUnknownSignals: true
                function onVolumeChanged() {
                    if (Audio.source?.audio) {
                        micRow.sliderValue = Audio.source.audio.volume;
                    }
                }
            }
        }

        // Brightness Slider
        ControlSliderRow {
            id: brightnessRow
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.rightMargin: 8

            property var currentMonitor: Brightness.getMonitorForScreen(root.screen)

            icon: Icons.sun
            sliderValue: currentMonitor?.brightness ?? 0.5
            progressColor: Styling.srItem("overprimary")
            wavy: true
            wavyAmplitude: 1.5 * sliderValue
            wavyFrequency: 8.0 * sliderValue
            iconRotation: (sliderValue / 1.0) * 180
            iconScale: 0.8 + (sliderValue / 1.0) * 0.2

            onValueChanged: newValue => {
                if (Brightness.syncBrightness) {
                    for (let i = 0; i < Brightness.monitors.length; i++) {
                        let mon = Brightness.monitors[i];
                        if (mon && mon.ready) {
                            mon.setBrightness(newValue);
                        }
                    }
                } else if (currentMonitor && currentMonitor.ready) {
                    currentMonitor.setBrightness(newValue);
                }
            }

            onIconClicked: {}

            Connections {
                target: brightnessRow.currentMonitor ?? null
                ignoreUnknownSignals: true
                function onBrightnessChanged() {
                    if (brightnessRow.currentMonitor) {
                        brightnessRow.sliderValue = brightnessRow.currentMonitor.brightness;
                    }
                }
                function onReadyChanged() {
                    if (brightnessRow.currentMonitor?.ready) {
                        brightnessRow.sliderValue = brightnessRow.currentMonitor.brightness;
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        // Initialize values
        if (Audio.sink?.audio)
            volumeRow.sliderValue = Audio.sink.audio.volume;
        if (Audio.source?.audio)
            micRow.sliderValue = Audio.source.audio.volume;
        if (brightnessRow.currentMonitor?.ready)
            brightnessRow.sliderValue = brightnessRow.currentMonitor.brightness;
    }
}
