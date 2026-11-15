pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.services
import qs.modules.components
import qs.modules.theme
import qs.modules.widgets.dashboard.widgets
import qs.config

// Lights: Yeelight bulbs on the LAN (YeelightService). Groups first, then
// single bulbs; each card has power, brightness, colour (hue/saturation +
// swatches) and white temperature. A group controls all its member bulbs.
Item {
    id: root

    // Start talking to the bulbs the first time the page is shown.
    onVisibleChanged: if (visible)
        YeelightService.start()
    Component.onCompleted: if (visible)
        YeelightService.start()

    readonly property var emptyState: ({
            power: false,
            bright: 0,
            ct: 4000,
            rgb: 0,
            hue: 0,
            sat: 0,
            color_mode: 2,
            online: false
        })

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

    function lightColor(s) {
        if (!s)
            return Colors.outline;
        if (s.color_mode === 2)
            return kelvinColor(s.ct);
        if (s.color_mode === 1) {
            const v = s.rgb;
            return Qt.rgba(((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255, 1);
        }
        return Qt.hsva(s.hue / 360, s.sat / 100, 1, 1);
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
                // light); the service's optimistic update moves the knob.
                strip.moved(Math.max(0, Math.min(1, mx / width)));
            }
            onPressed: mouse => pick(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    pick(mouse.x);
            }
        }
    }

    // A light (single bulb or group): name, power, brightness, colour/white.
    component LightCard: StyledRect {
        id: card

        property string title: ""
        property string subtitle: ""
        property string editText: title
        property var lightState: root.emptyState
        property bool usable: true
        property bool showControls: true
        property bool isGroup: false
        // Which controls to show: follow the light's mode unless picked.
        property int chosenMode: -1
        readonly property bool whiteMode: chosenMode >= 0 ? chosenMode === 1 : lightState.color_mode === 2
        property bool editingName: false
        default property alias extraContent: extraColumn.data

        signal renameRequested(string name)
        signal powerToggled
        signal brightnessSet(int value)
        signal colorSet(real hue, real sat)
        signal temperatureSet(real kelvin)

        Layout.fillWidth: true
        variant: "pane"
        radius: Styling.radius(4)
        implicitHeight: cardColumn.implicitHeight + 24

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Name, status, power
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26

                    Text {
                        anchors.centerIn: parent
                        text: Icons.lightbulb
                        font.family: Icons.font
                        font.pixelSize: 22
                        color: card.lightState.power ? root.lightColor(card.lightState) : Colors.outline
                        Behavior on color {
                            ColorAnimation {
                                duration: Config.animDuration / 2
                            }
                        }
                    }

                    // Groups: a second bulb behind the first.
                    Text {
                        visible: card.isGroup
                        x: 10
                        y: -4
                        z: -1
                        text: Icons.lightbulb
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: card.lightState.power ? root.lightColor(card.lightState) : Colors.outline
                        opacity: 0.55
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        visible: !card.editingName
                        text: card.title
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

                    // Edited in place: same font, size, weight and colour as
                    // the label above, so only the cursor shows that it's being
                    // edited. Enter saves, Escape or clicking elsewhere cancels.
                    TextInput {
                        id: nameInput
                        Layout.fillWidth: true
                        visible: card.editingName
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.settingsFontSize(0)
                        font.weight: Font.Medium
                        color: Colors.overBackground
                        selectionColor: Styling.srItem("overprimary")
                        selectedTextColor: Colors.background
                        selectByMouse: true
                        clip: true
                        onVisibleChanged: if (visible) {
                            text = card.editText;
                            selectAll();
                            forceActiveFocus();
                        }
                        onAccepted: {
                            card.renameRequested(text);
                            card.editingName = false;
                        }
                        Keys.onEscapePressed: event => {
                            card.editingName = false;
                            event.accepted = true;
                        }
                        onActiveFocusChanged: if (!activeFocus)
                            card.editingName = false
                    }

                    Text {
                        text: card.subtitle
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

                    StyledToolTip {
                        show: renameArea.containsMouse
                        tooltipText: "Rename"
                    }
                }

                ControlButton {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    enabled: card.usable
                    iconName: Icons.shutdown
                    isActive: card.lightState.power
                    tooltipText: card.lightState.power ? "Turn off" : "Turn on"
                    onClicked: card.powerToggled()
                }
            }

            // The controls, dimmed and disabled when there's nothing to control.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: card.showControls
                enabled: card.usable
                opacity: card.usable ? 1 : 0.45

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
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        progressColor: Styling.srItem("overprimary")
                        tooltipText: Math.round(value * 100) + "%"
                        scroll: true

                        readonly property real lightValue: card.lightState.bright / 100
                        onLightValueChanged: if (!isDragging)
                            value = lightValue
                        Component.onCompleted: value = lightValue
                        // Programmatic updates match the light, so only user
                        // changes (drag, click, wheel) are sent.
                        onValueChanged: {
                            const v = Math.max(1, Math.round(value * 100));
                            if (v !== card.lightState.bright)
                                card.brightnessSet(v);
                        }
                    }

                    Text {
                        text: card.lightState.bright + "%"
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
                        stops: ["#ff0000", "#ffff00", "#00ff00", "#00ffff", "#0000ff", "#ff00ff", "#ff0000"]
                        position: card.lightState.hue / 359
                        onMoved: p => card.colorSet(p * 359, card.lightState.color_mode === 2 ? 100 : card.lightState.sat)
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
                            Layout.fillWidth: true
                            Layout.preferredHeight: 20
                            progressColor: Qt.hsva(card.lightState.hue / 360, 0.8, 1, 1)
                            tooltipText: Math.round(value * 100) + "%"
                            scroll: true

                            readonly property real lightValue: card.lightState.sat / 100
                            onLightValueChanged: if (!isDragging)
                                value = lightValue
                            Component.onCompleted: value = lightValue
                            onValueChanged: {
                                const v = Math.round(value * 100);
                                if (v !== card.lightState.sat)
                                    card.colorSet(card.lightState.hue, v);
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
                                    onClicked: card.colorSet(swatch.modelData, 100)
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
                        position: (card.lightState.ct - 1700) / (6500 - 1700)
                        onMoved: p => card.temperatureSet(1700 + p * (6500 - 1700))
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
                                variant: Math.abs(card.lightState.ct - modelData.k) < 150 && card.lightState.color_mode === 2 ? "primary" : (presetArea.containsMouse ? "focus" : "common")
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
                                    onClicked: card.temperatureSet(preset.modelData.k)
                                }
                            }
                        }
                    }

                    Text {
                        text: card.lightState.ct + " K"
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.settingsFontSize(-3)
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            // Extra content (group members).
            ColumnLayout {
                id: extraColumn
                Layout.fillWidth: true
                spacing: 8
                visible: children.length > 0
            }
        }
    }

    // Section title.
    component SectionLabel: Text {
        font.family: Styling.defaultFont
        font.pixelSize: Styling.settingsFontSize(-1)
        font.weight: Font.Medium
        color: Colors.overSurfaceVariant
        Layout.topMargin: 4
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

            // Header: title, new group, all on/off, search
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
                        text: YeelightService.discovering ? "Searching…" : (YeelightService.bulbIps.length + (YeelightService.bulbIps.length === 1 ? " bulb" : " bulbs") + (YeelightService.groups.length > 0 ? " · " + YeelightService.groups.length + (YeelightService.groups.length === 1 ? " group" : " groups") : ""))
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.settingsFontSize(-2)
                        color: Colors.overSurfaceVariant
                    }
                }

                // Pushes the buttons to the right edge (the title column
                // can't stretch: its text lines cap its maximum width).
                Item {
                    Layout.fillWidth: true
                }

                StyledRect {
                    id: newGroupButton
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: newGroupRow.implicitWidth + 24
                    visible: YeelightService.bulbIps.length > 0
                    variant: newGroupArea.containsMouse ? "focus" : "common"
                    radius: Styling.radius(-2)

                    RowLayout {
                        id: newGroupRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: Icons.plus
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: newGroupButton.item
                        }

                        Text {
                            text: "New group"
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.settingsFontSize(-2)
                            font.weight: Font.Medium
                            color: newGroupButton.item
                        }
                    }

                    MouseArea {
                        id: newGroupArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: YeelightService.createGroup("", [])
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
                            icon: Icons.shutdown,
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
                        text: "Enable \"LAN Control\" for each bulb in the Yeelight app, then search again. Bulbs need to be on the same network as this computer."
                        font.family: Styling.defaultFont
                        font.pixelSize: Styling.settingsFontSize(-2)
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            // ── Groups ──────────────────────────────────────────────────
            SectionLabel {
                visible: YeelightService.groups.length > 0
                text: "Groups"
            }

            Repeater {
                model: YeelightService.groupIds

                LightCard {
                    id: groupCard
                    required property string modelData
                    readonly property string groupId: modelData
                    readonly property var group: YeelightService.group(groupId)
                    readonly property var stateOf: YeelightService.groupState(groupId)

                    isGroup: true
                    title: YeelightService.groupName(group)
                    editText: group ? group.name : ""
                    subtitle: stateOf.count === 0 ? "Empty group" : (stateOf.count + (stateOf.count === 1 ? " bulb" : " bulbs") + " · " + (stateOf.power ? "On · " + stateOf.bright + "%" : "Off"))
                    lightState: stateOf
                    usable: stateOf.count > 0

                    onRenameRequested: name => YeelightService.renameGroup(groupId, name)
                    onPowerToggled: YeelightService.toggleGroupPower(groupId)
                    onBrightnessSet: v => YeelightService.setGroupBrightness(groupId, v)
                    onColorSet: (h, s) => YeelightService.setGroupColor(groupId, h, s)
                    onTemperatureSet: k => YeelightService.setGroupTemperature(groupId, k)

                    property bool editingMembers: false
                    showControls: stateOf.count > 0

                    // Empty group: call to action.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: groupCard.stateOf.count === 0 && !groupCard.editingMembers
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: "This group has no bulbs yet. Add the bulbs it should control."
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.settingsFontSize(-2)
                            color: Colors.overSurfaceVariant
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledRect {
                                id: addBulbsButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                variant: addBulbsArea.containsMouse ? "primaryfocus" : "primary"
                                radius: Styling.radius(-2)

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: Icons.plus
                                        font.family: Icons.font
                                        font.pixelSize: 14
                                        color: addBulbsButton.item
                                    }

                                    Text {
                                        text: "Add bulbs"
                                        font.family: Styling.defaultFont
                                        font.pixelSize: Styling.settingsFontSize(-1)
                                        font.weight: Font.Medium
                                        color: addBulbsButton.item
                                    }
                                }

                                MouseArea {
                                    id: addBulbsArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: groupCard.editingMembers = true
                                }
                            }

                            StyledRect {
                                id: deleteEmptyButton
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                variant: deleteEmptyArea.containsMouse ? "focus" : "common"
                                radius: Styling.radius(-2)

                                Text {
                                    anchors.centerIn: parent
                                    text: Icons.trash
                                    font.family: Icons.font
                                    font.pixelSize: 14
                                    color: deleteEmptyArea.containsMouse ? Colors.error : deleteEmptyButton.item
                                }

                                MouseArea {
                                    id: deleteEmptyArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: YeelightService.deleteGroup(groupCard.groupId)
                                }

                                StyledToolTip {
                                    show: deleteEmptyArea.containsMouse
                                    tooltipText: "Delete group"
                                }
                            }
                        }
                    }

                    // Group with bulbs: edit bulbs / delete.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: groupCard.stateOf.count > 0 || groupCard.editingMembers
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: groupCard.editingMembers ? "Click bulbs to add or remove them" : "Bulbs in this group"
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.settingsFontSize(-2)
                            color: Colors.overSurfaceVariant
                        }

                        StyledRect {
                            id: editMembersButton
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: editMembersLabel.implicitWidth + 20
                            variant: groupCard.editingMembers ? "primary" : (editMembersArea.containsMouse ? "focus" : "common")
                            radius: Styling.radius(-4)

                            Text {
                                id: editMembersLabel
                                anchors.centerIn: parent
                                text: groupCard.editingMembers ? "Done" : "Edit bulbs"
                                font.family: Styling.defaultFont
                                font.pixelSize: Styling.settingsFontSize(-2)
                                color: editMembersButton.item
                            }

                            MouseArea {
                                id: editMembersArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: groupCard.editingMembers = !groupCard.editingMembers
                            }
                        }

                        StyledRect {
                            id: deleteButton
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            variant: deleteArea.containsMouse ? "focus" : "common"
                            radius: Styling.radius(-4)

                            Text {
                                anchors.centerIn: parent
                                text: Icons.trash
                                font.family: Icons.font
                                font.pixelSize: 14
                                color: deleteArea.containsMouse ? Colors.error : deleteButton.item
                            }

                            MouseArea {
                                id: deleteArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: YeelightService.deleteGroup(groupCard.groupId)
                            }

                            StyledToolTip {
                                show: deleteArea.containsMouse
                                tooltipText: "Delete group (the bulbs stay)"
                            }
                        }
                    }

                    // Member chips: all bulbs while editing, else just members.
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: groupCard.stateOf.count > 0 || groupCard.editingMembers

                        Repeater {
                            model: YeelightService.bulbIps

                            StyledRect {
                                id: chip
                                required property string modelData
                                readonly property bool member: groupCard.group ? groupCard.group.members.indexOf(modelData) >= 0 : false
                                visible: member || groupCard.editingMembers
                                width: chipRow.implicitWidth + 20
                                height: 28
                                variant: member ? "primary" : (chipArea.containsMouse ? "focus" : "common")
                                radius: Styling.radius(-4)

                                RowLayout {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: chip.member && groupCard.editingMembers ? Icons.cancel : (groupCard.editingMembers ? Icons.plus : Icons.lightbulb)
                                        font.family: Icons.font
                                        font.pixelSize: 12
                                        color: chip.item
                                    }

                                    Text {
                                        text: YeelightService.displayName(YeelightService.bulbs[chip.modelData])
                                        font.family: Styling.defaultFont
                                        font.pixelSize: Styling.settingsFontSize(-2)
                                        color: chip.item
                                    }
                                }

                                MouseArea {
                                    id: chipArea
                                    anchors.fill: parent
                                    enabled: groupCard.editingMembers
                                    hoverEnabled: true
                                    cursorShape: groupCard.editingMembers ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: YeelightService.toggleMember(groupCard.groupId, chip.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // ── Bulbs ───────────────────────────────────────────────────
            SectionLabel {
                visible: YeelightService.groups.length > 0 && YeelightService.bulbIps.length > 0
                text: "Bulbs"
            }

            Repeater {
                model: YeelightService.bulbIps

                LightCard {
                    id: bulbCard
                    required property string modelData
                    readonly property string ip: modelData
                    readonly property var bulb: YeelightService.bulbs[ip] ?? Object.assign({
                            ip: ip,
                            name: ""
                        }, root.emptyState)

                    title: YeelightService.displayName(bulb)
                    editText: title
                    subtitle: (bulb.online ? (bulb.power ? "On · " + bulb.bright + "%" : "Off") : "Offline") + " · " + ip
                    lightState: bulb
                    opacity: bulb.online ? 1 : 0.55

                    onRenameRequested: name => YeelightService.rename(ip, name)
                    onPowerToggled: YeelightService.togglePower(ip)
                    onBrightnessSet: v => YeelightService.setBrightness(ip, v)
                    onColorSet: (h, s) => YeelightService.setColor(ip, h, s)
                    onTemperatureSet: k => YeelightService.setTemperature(ip, k)
                }
            }
        }
    }
}
