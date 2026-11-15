pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.widgets.dashboard.widgets
import qs.config

// Lights: Yeelight bulbs on the LAN (YeelightService). One card per bulb with
// power, brightness, colour (hue/saturation + swatches) and white temperature.
Item {
    id: root

    // Start talking to the bulbs the first time the page is shown.
    onVisibleChanged: if (visible)
        YeelightService.start()
    Component.onCompleted: if (visible)
        YeelightService.start()

    // ── helpers ─────────────────────────────────────────────────────────
    function kelvinColor(k) {
        // Approximate white point: warm amber at 1700 K to cool blue-white at 6500 K.
        const t = Math.max(0, Math.min(1, (k - 1700) / (6500 - 1700)));
        const warm = Qt.color("#ff9a3c");
        const mid = Qt.color("#fff0dc");
        const cool = Qt.color("#dbe7ff");
        const a = t < 0.5 ? warm : mid;
        const b = t < 0.5 ? mid : cool;
        const u = t < 0.5 ? t * 2 : (t - 0.5) * 2;
        return Qt.rgba(a.r + (b.r - a.r) * u, a.g + (b.g - a.g) * u, a.b + (b.b - a.b) * u, 1);
    }

    function bulbColor(b) {
        if (!b)
            return Colors.outline;
        if (b.color_mode === 2)
            return kelvinColor(b.ct);
        if (b.color_mode === 1) {
            const v = b.rgb;
            return Qt.rgba(((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255, 1);
        }
        return Qt.hsva(b.hue / 360, b.sat / 100, 1, 1);
    }

    // A horizontal gradient track with a draggable knob (hue, temperature).
    component GradientStrip: Item {
        id: strip
        property real position: 0
        property var stops: []
        signal moved(real position)

        Layout.fillWidth: true
        Layout.preferredHeight: 20

        Rectangle {
            id: track
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                stops: strip.stops.map((c, i) => gradientStop.createObject(strip, {
                            position: strip.stops.length > 1 ? i / (strip.stops.length - 1) : 0,
                            color: c
                        }))
            }
        }

        Component {
            id: gradientStop
            GradientStop {}
        }

        StyledRect {
            variant: "common"
            width: 18
            height: 18
            radius: 9
            y: (strip.height - height) / 2
            x: Math.max(0, Math.min(strip.width - width, strip.position * strip.width - width / 2))
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function pick(mx) {
                // Don't assign position (that would break its binding to the
                // bulb); the service's optimistic update moves the knob.
                strip.moved(Math.max(0, Math.min(1, mx / width)));
            }
            onPressed: mouse => pick(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    pick(mouse.x);
            }
        }
    }

    // ── layout ──────────────────────────────────────────────────────────
    Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 10

            // Header: title, scan, all on/off
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: "Lights"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.settingsFontSize(1)
                        font.bold: true
                        color: Colors.overBackground
                    }

                    Text {
                        text: YeelightService.discovering ? "Searching…" : (YeelightService.bulbIps.length + (YeelightService.bulbIps.length === 1 ? " bulb" : " bulbs"))
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.settingsFontSize(-2)
                        color: Colors.overSurfaceVariant
                    }
                }

                Repeater {
                    model: [
                        {
                            icon: Icons.lightbulb,
                            tip: "All on",
                            act: () => YeelightService.setAllPower(true)
                        },
                        {
                            icon: Icons.power,
                            tip: "All off",
                            act: () => YeelightService.setAllPower(false)
                        },
                        {
                            icon: Icons.sync,
                            tip: "Search again",
                            act: () => YeelightService.discover()
                        }
                    ]

                    StyledRect {
                        id: headerButton
                        required property var modelData
                        required property int index
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        variant: headerArea.containsMouse ? "focus" : "common"
                        radius: Styling.radius(-2)
                        visible: index === 2 || YeelightService.bulbIps.length > 0

                        Text {
                            anchors.centerIn: parent
                            text: headerButton.modelData.icon
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: headerButton.item

                            RotationAnimation on rotation {
                                running: headerButton.index === 2 && YeelightService.discovering
                                from: 0
                                to: 360
                                duration: 1000
                                loops: Animation.Infinite
                                onRunningChanged: if (!running)
                                    parent.rotation = 0
                            }
                        }

                        MouseArea {
                            id: headerArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: headerButton.modelData.act()
                        }

                        StyledToolTip {
                            show: headerArea.containsMouse
                            tooltipText: headerButton.modelData.tip
                        }
                    }
                }
            }

            // Add a bulb by IP (works even when discovery is blocked)
            SearchInput {
                id: addInput
                Layout.fillWidth: true
                implicitHeight: 36
                variant: "internalbg"
                iconText: Icons.plus
                placeholderText: "Add a bulb by IP (e.g. 192.168.1.42)"
                onAccepted: {
                    YeelightService.addIp(text);
                    text = "";
                }
            }

            Text {
                Layout.fillWidth: true
                visible: YeelightService.lastError !== "" && YeelightService.bulbIps.length === 0
                text: YeelightService.lastError
                wrapMode: Text.WordWrap
                font.family: Styling.defaultFont
                font.pixelSize: Styling.settingsFontSize(-2)
                color: Colors.error
            }

            // Empty state
            StyledRect {
                Layout.fillWidth: true
                visible: YeelightService.bulbIps.length === 0 && !YeelightService.discovering
                variant: "pane"
                radius: Styling.radius(4)
                implicitHeight: emptyColumn.implicitHeight + 24

                ColumnLayout {
                    id: emptyColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    Text {
                        text: "No bulbs found"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.settingsFontSize(0)
                        font.weight: Font.Medium
                        color: Colors.overBackground
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Enable \"LAN Control\" for each bulb in the Yeelight app, then search again. If a bulb still doesn't show up, add it by its IP address above."
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.settingsFontSize(-2)
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            // Bulb cards
            Repeater {
                model: YeelightService.bulbIps

                StyledRect {
                    id: card
                    required property string modelData
                    readonly property string ip: modelData
                    readonly property var bulb: YeelightService.bulbs[ip] ?? ({
                            ip: ip,
                            name: "",
                            power: false,
                            bright: 0,
                            ct: 4000,
                            rgb: 0,
                            hue: 0,
                            sat: 0,
                            color_mode: 2,
                            online: false
                        })
                    // Which controls to show: follow the bulb's mode unless the
                    // user picked one.
                    property int chosenMode: -1
                    readonly property bool whiteMode: chosenMode >= 0 ? chosenMode === 1 : bulb.color_mode === 2
                    property bool editingName: false

                    Layout.fillWidth: true
                    variant: "pane"
                    radius: Styling.radius(4)
                    implicitHeight: cardColumn.implicitHeight + 24
                    opacity: bulb.online ? 1 : 0.55

                    ColumnLayout {
                        id: cardColumn
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        // Name, status, power
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: Icons.lightbulb
                                font.family: Icons.font
                                font.pixelSize: 22
                                color: card.bulb.power ? root.bulbColor(card.bulb) : Colors.outline
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Config.animDuration / 2
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    visible: !card.editingName
                                    text: YeelightService.displayName(card.bulb)
                                    elide: Text.ElideRight
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.settingsFontSize(0)
                                    font.weight: Font.Medium
                                    color: Colors.overBackground

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.IBeamCursor
                                        onDoubleClicked: card.editingName = true
                                    }
                                }

                                SearchInput {
                                    id: nameInput
                                    Layout.fillWidth: true
                                    visible: card.editingName
                                    implicitHeight: 32
                                    variant: "internalbg"
                                    placeholderText: "Bulb name"
                                    onVisibleChanged: if (visible) {
                                        text = card.bulb.name;
                                        focusInput();
                                    }
                                    onAccepted: {
                                        YeelightService.rename(card.ip, text);
                                        card.editingName = false;
                                    }
                                    onEscapePressed: card.editingName = false
                                }

                                Text {
                                    text: (card.bulb.online ? (card.bulb.power ? "On · " + card.bulb.bright + "%" : "Off") : "Offline") + " · " + card.ip
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.settingsFontSize(-3)
                                    color: Colors.overSurfaceVariant
                                }
                            }

                            StyledRect {
                                id: renameButton
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                variant: renameArea.containsMouse ? "focus" : "common"
                                radius: Styling.radius(-4)

                                Text {
                                    anchors.centerIn: parent
                                    text: Icons.edit
                                    font.family: Icons.font
                                    font.pixelSize: 14
                                    color: renameButton.item
                                }

                                MouseArea {
                                    id: renameArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: card.editingName = !card.editingName
                                }
                            }

                            ControlButton {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                iconName: Icons.power
                                isActive: card.bulb.power
                                tooltipText: card.bulb.power ? "Turn off" : "Turn on"
                                onClicked: YeelightService.togglePower(card.ip)
                            }
                        }

                        // Brightness
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: Icons.sun
                                font.family: Icons.font
                                font.pixelSize: 16
                                color: Colors.overSurfaceVariant
                            }

                            StyledSlider {
                                id: brightSlider
                                Layout.fillWidth: true
                                Layout.preferredHeight: 20
                                progressColor: Styling.srItem("overprimary")
                                tooltipText: Math.round(value * 100) + "%"
                                scroll: true

                                readonly property real bulbValue: card.bulb.bright / 100
                                onBulbValueChanged: if (!isDragging)
                                    value = bulbValue
                                Component.onCompleted: value = bulbValue
                                // Programmatic updates match the bulb, so only
                                // user changes (drag, click, wheel) are sent.
                                onValueChanged: {
                                    const v = Math.max(1, Math.round(value * 100));
                                    if (v !== card.bulb.bright)
                                        YeelightService.setBrightness(card.ip, v);
                                }
                            }

                            Text {
                                text: card.bulb.bright + "%"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.settingsFontSize(-2)
                                color: Colors.overBackground
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 38
                            }
                        }

                        SegmentedSwitch {
                            options: [
                                {
                                    icon: Icons.palette,
                                    label: "Color"
                                },
                                {
                                    icon: Icons.sun,
                                    label: "White"
                                }
                            ]
                            currentIndex: card.whiteMode ? 1 : 0
                            buttonSize: 28
                            onIndexChanged: index => card.chosenMode = index
                        }

                        // Colour: hue strip, saturation, swatches
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !card.whiteMode
                            spacing: 8

                            GradientStrip {
                                id: hueStrip
                                stops: ["#ff0000", "#ffff00", "#00ff00", "#00ffff", "#0000ff", "#ff00ff", "#ff0000"]
                                position: card.bulb.hue / 359
                                onMoved: p => YeelightService.setColor(card.ip, p * 359, card.bulb.color_mode === 2 ? 100 : card.bulb.sat)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: "Saturation"
                                    font.family: Styling.defaultFont
                                    font.pixelSize: Styling.settingsFontSize(-2)
                                    color: Colors.overSurfaceVariant
                                }

                                StyledSlider {
                                    id: satSlider
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 20
                                    progressColor: Qt.hsva(card.bulb.hue / 360, 0.8, 1, 1)
                                    tooltipText: Math.round(value * 100) + "%"
                                    scroll: true

                                    readonly property real bulbValue: card.bulb.sat / 100
                                    onBulbValueChanged: if (!isDragging)
                                        value = bulbValue
                                    Component.onCompleted: value = bulbValue
                                    onValueChanged: {
                                        const v = Math.round(value * 100);
                                        if (v !== card.bulb.sat)
                                            YeelightService.setColor(card.ip, card.bulb.hue, v);
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [0, 30, 55, 120, 180, 220, 275, 320]

                                    Rectangle {
                                        id: swatch
                                        required property int modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        radius: Styling.radius(-6)
                                        color: Qt.hsva(modelData / 360, 1, 1, 1)
                                        border.width: swatchArea.containsMouse ? 2 : 0
                                        border.color: Colors.overBackground

                                        MouseArea {
                                            id: swatchArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: YeelightService.setColor(card.ip, swatch.modelData, 100)
                                        }
                                    }
                                }
                            }
                        }

                        // White: colour temperature + presets
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: card.whiteMode
                            spacing: 8

                            GradientStrip {
                                stops: [root.kelvinColor(1700), root.kelvinColor(4100), root.kelvinColor(6500)]
                                position: (card.bulb.ct - 1700) / (6500 - 1700)
                                onMoved: p => YeelightService.setTemperature(card.ip, 1700 + p * (6500 - 1700))
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [
                                        {
                                            label: "Warm",
                                            k: 2700
                                        },
                                        {
                                            label: "Neutral",
                                            k: 4000
                                        },
                                        {
                                            label: "Daylight",
                                            k: 5500
                                        },
                                        {
                                            label: "Cool",
                                            k: 6500
                                        }
                                    ]

                                    StyledRect {
                                        id: preset
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        variant: Math.abs(card.bulb.ct - modelData.k) < 150 && card.bulb.color_mode === 2 ? "primary" : (presetArea.containsMouse ? "focus" : "common")
                                        radius: Styling.radius(-4)

                                        Text {
                                            anchors.centerIn: parent
                                            text: preset.modelData.label
                                            font.family: Styling.defaultFont
                                            font.pixelSize: Styling.settingsFontSize(-2)
                                            color: preset.item
                                        }

                                        MouseArea {
                                            id: presetArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: YeelightService.setTemperature(card.ip, preset.modelData.k)
                                        }
                                    }
                                }
                            }

                            Text {
                                text: card.bulb.ct + " K"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.settingsFontSize(-3)
                                color: Colors.overSurfaceVariant
                            }
                        }
                    }
                }
            }
        }
    }
}
