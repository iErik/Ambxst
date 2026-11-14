import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.corners
import qs.config
import "../../../config/defaults/theme.js" as ThemeDefaults

// A miniature desktop drawn from a preset's settings, used when the preset has
// no screenshot. Surfaces are drawn with the preset's own surface styling
// (gradients, halftone, borders, opacity) over the current wallpaper. Colors
// come from the current palette, since presets don't carry colors.
//
// Geometry is computed in real screen pixels and scaled by `s`. The shell's
// chrome (bar, notch, dock, frame) is drawn `k` times larger than true scale:
// at true scale a 44px bar on a 2560px screen is a hairline in a 640px
// preview, and the chrome is what tells presets apart.
Item {
    id: root

    // Merged preset settings (defaults + preset file), plain objects.
    property var bar: ({})
    property var notch: ({})
    property var dock: ({})
    property var theme: ({})
    property var compositor: ({})

    property real screenW: 1920
    property real screenH: 1080
    // file:// URL of an image to use as the desktop, or "".
    property string wallpaperSource: ""

    readonly property real s: (screenW > 0 && screenH > 0) ? Math.min(width / screenW, height / screenH) : 0.25
    readonly property real k: 1.6
    clip: true

    function val(obj, key, fallback) {
        return (obj && obj[key] !== undefined && obj[key] !== null) ? obj[key] : fallback;
    }

    // --- Preset surface styling -------------------------------------------------
    readonly property var srKeys: ({ bg: "srBg", popup: "srPopup", internalbg: "srInternalBg", pane: "srPane", common: "srCommon", focus: "srFocus", primary: "srPrimary", barbg: "srBarBg" })

    // The preset's styling for a variant, with border widths scaled down to the
    // miniature. null falls back to the current theme.
    function sr(variant) {
        const cfg = theme ? theme[srKeys[variant]] : null;
        if (!cfg)
            return null;
        const out = Object.assign({}, cfg);
        if (cfg.border && cfg.border.length >= 2)
            out.border = [cfg.border[0], cfg.border[1] > 0 ? Math.max(0.5, cfg.border[1] * k * s) : 0];
        return out;
    }

    readonly property var srBar: sr("barbg")
    readonly property var srPopup: sr("popup")
    readonly property var srBg: sr("bg")
    readonly property var srPane: sr("pane")
    readonly property var srCommon: sr("common")
    readonly property var srFocus: sr("focus")
    readonly property var srPrimary: sr("primary")
    readonly property var srInternal: sr("internalbg")

    function inkStyle(cfg, opacity) {
        // Start from the full style so every field StyledRect reads is present.
        return Object.assign({}, cfg || ThemeDefaults.data.srPane, {
            gradient: [[cfg && cfg.itemColor ? cfg.itemColor : "overBackground", 0]],
            gradientType: "linear",
            opacity: opacity,
            border: ["transparent", 0]
        });
    }
    readonly property var paneInk: inkStyle(srPane, 0.28)
    readonly property var paneInkStrong: inkStyle(srPane, 0.45)

    function itemColorOf(cfg, fallback) {
        return cfg && cfg.itemColor ? Config.resolveColor(cfg.itemColor) : fallback;
    }

    // --- Settings ---------------------------------------------------------------
    readonly property string barPos: ["top", "bottom", "left", "right"].includes(val(bar, "position", "top")) ? val(bar, "position", "top") : "top"
    readonly property bool barVertical: barPos === "left" || barPos === "right"
    readonly property bool frameOn: val(bar, "frameEnabled", false)
    readonly property real frameT: frameOn ? Math.max(3, val(bar, "frameThickness", 6)) * k : 0
    readonly property bool containBar: frameOn && val(bar, "containBar", false)
    readonly property bool squished: val(bar, "pillStyle", "default") === "squished"
    // Not floating: the bar sits flush on its edge, square, without a gap.
    readonly property bool barFlush: !containBar && !val(bar, "floating", true)
    readonly property real roundness: Math.max(0, val(theme, "roundness", 16))
    readonly property string fontFamily: val(theme, "font", "")

    readonly property string notchPos: val(notch, "position", "top") === "bottom" ? "bottom" : "top"
    readonly property bool notchIsland: val(notch, "theme", "default") === "island"
    // Merged: the (closed) notch is part of the bar, so only its label shows,
    // centred in the bar. Same conditions as NotchContent.
    readonly property bool notchMerged: val(bar, "mergeNotch", false) && !notchIsland && !barVertical && barPos === notchPos

    readonly property bool dockOn: val(dock, "enabled", false)
    readonly property string dockTheme: val(dock, "theme", "default")
    readonly property bool dockIntegrated: dockOn && dockTheme === "integrated"
    readonly property bool dockFloating: dockTheme === "floating"
    readonly property real dockSize: Math.max(24, val(dock, "height", 48)) * k
    readonly property real dockIcon: Math.max(12, val(dock, "iconSize", 24)) * k
    readonly property real dockMargin: Math.max(0, val(dock, "margin", 4)) * k

    readonly property real gapsIn: Math.max(0, val(compositor, "gapsIn", 2))
    readonly property real gapsOut: Math.max(0, val(compositor, "gapsOut", 4))
    readonly property real windowRounding: val(compositor, "syncRoundness", true) ? roundness : Math.max(0, val(compositor, "rounding", 16))
    readonly property real windowBorder: Math.max(0, val(compositor, "borderSize", 2))
    function firstColor(v, fallback) {
        const name = Array.isArray(v) ? v[0] : v;
        return name ? Config.resolveColor(name) : fallback;
    }
    readonly property bool chromeShadow: val(theme, "shadowOpacity", 0) > 0
    readonly property bool windowShadow: val(compositor, "shadowEnabled", false) && val(compositor, "shadowOpacity", 0) > 0
    readonly property color activeBorder: firstColor(val(compositor, "activeBorderColor", null), Colors.primary)
    readonly property color inactiveBorder: firstColor(val(compositor, "inactiveBorderColor", null), Colors.surface)

    // Same collision rule as DockContent.position: keep the dock off the bar's
    // edge (and off a bottom notch).
    readonly property string dockPos: {
        const user = val(dock, "position", "bottom");
        if (notchPos === "bottom" && user === "bottom")
            return barPos === "left" ? "right" : "left";
        if (user !== barPos)
            return user;
        switch (user) {
        case "bottom":
            if (notchPos === "bottom" || barPos === "bottom")
                return barPos === "left" ? "right" : "left";
            return "left";
        case "left":
            return "right";
        case "right":
            return "left";
        case "top":
            return "bottom";
        default:
            return "bottom";
        }
    }

    // --- Geometry (real pixels) -------------------------------------------------
    readonly property real barT: barVertical ? 40 * 1.3 : 40 * k
    readonly property real barGap: (containBar || barFlush) ? 0 : 4 * k
    readonly property real barInset: frameT + barGap

    // The desktop: inside the frame, and also beside the bar when the frame
    // contains it (the bar then sits on the frame itself).
    readonly property var desktopRect: {
        let x = frameT, y = frameT, w = screenW - 2 * frameT, h = screenH - 2 * frameT;
        if (containBar) {
            if (barPos === "top") { y += barT; h -= barT; }
            else if (barPos === "bottom") { h -= barT; }
            else if (barPos === "left") { x += barT; w -= barT; }
            else { w -= barT; }
        }
        return { x: x, y: y, w: w, h: h };
    }

    readonly property var barRect: {
        const len = (barVertical ? screenH : screenW) - 2 * barInset;
        switch (barPos) {
        case "bottom":
            return { x: barInset, y: screenH - barInset - barT, w: len, h: barT };
        case "left":
            return { x: barInset, y: barInset, w: barT, h: len };
        case "right":
            return { x: screenW - barInset - barT, y: barInset, w: barT, h: len };
        default:
            return { x: barInset, y: barInset, w: len, h: barT };
        }
    }

    // Body of the notch (without the attached style's corner ears).
    readonly property var notchRect: {
        const w = (notchIsland ? 200 : 190) * k;
        const h = (notchIsland ? 32 : 30) * k;
        const x = (screenW - w) / 2;
        if (notchMerged)
            return { x: x, y: barRect.y, w: w, h: barRect.h };
        const gap = notchIsland ? 6 * k + frameT : 0;
        return { x: x, y: notchPos === "bottom" ? screenH - gap - h : gap, w: w, h: h };
    }
    // Real notch: corner ears and far-corner radius are roundness + 4.
    readonly property real notchCorner: roundness > 0 ? Math.min(roundness + 4, 30) * k : 0

    readonly property int dockIcons: 6
    readonly property real dockLen: dockIcons * (dockIcon + 12 * k) + 24 * k
    readonly property var dockRect: {
        const off = dockFloating ? dockMargin + 8 * k + frameT : 0;
        switch (dockPos) {
        case "left":
            return { x: off, y: (screenH - dockLen) / 2, w: dockSize, h: dockLen };
        case "right":
            return { x: screenW - off - dockSize, y: (screenH - dockLen) / 2, w: dockSize, h: dockLen };
        case "top":
            return { x: (screenW - dockLen) / 2, y: off, w: dockLen, h: dockSize };
        default:
            return { x: (screenW - dockLen) / 2, y: screenH - off - dockSize, w: dockLen, h: dockSize };
        }
    }

    // Area for windows: the desktop minus a floating bar, minus outer gaps.
    readonly property var workArea: {
        const d = desktopRect;
        const g = (gapsOut + 10) * k;
        let x = d.x + g, y = d.y + g, w = d.w - 2 * g, h = d.h - 2 * g;
        if (!containBar) {
            const used = barGap + barT;
            if (barPos === "top") { y += used; h -= used; }
            else if (barPos === "bottom") { h -= used; }
            else if (barPos === "left") { x += used; w -= used; }
            else { w -= used; }
        }
        if (dockOn && !dockIntegrated) {
            // Keep windows a gap away from the dock's inner edge.
            const dr = dockRect;
            const gap = 6 * k;
            if (dockPos === "bottom") {
                h = Math.min(h, dr.y - gap - y);
            } else if (dockPos === "top") {
                const top = dr.y + dr.h + gap;
                if (top > y) { h -= top - y; y = top; }
            } else if (dockPos === "left") {
                const left = dr.x + dr.w + gap;
                if (left > x) { w -= left - x; x = left; }
            } else {
                w = Math.min(w, dr.x - gap - x);
            }
        }
        return { x: x, y: y, w: w, h: h };
    }

    // --- Drawing ----------------------------------------------------------------
    // Centered canvas with the screen's exact aspect ratio.
    Item {
        id: canvas
        width: root.screenW * root.s
        height: root.screenH * root.s
        anchors.centerIn: parent
        clip: true

        // --- Drawing ----------------------------------------------------------------
        // Frame: everything else sits on top of it.
        StyledRect {
            variant: "barbg"
            configOverride: root.srBar
            anchors.fill: parent
            radius: Styling.radius(-4)
            enableBorder: false
            animateRadius: false
            visible: root.frameOn
        }

        // Desktop with the current wallpaper; rounded inner corners when framed.
        StyledRect {
            id: desktop
            variant: "internalbg"
            configOverride: root.srInternal
            enableBorder: false
            animateRadius: false
            x: root.desktopRect.x * root.s
            y: root.desktopRect.y * root.s
            width: root.desktopRect.w * root.s
            height: root.desktopRect.h * root.s
            radius: root.frameOn ? root.roundness * root.k * root.s : Styling.radius(-4)

            Image {
                id: wallpaper
                anchors.fill: parent
                source: root.wallpaperSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 1024
                visible: status === Image.Ready
            }

            // Light tint so windows still stand out without a wallpaper.
            StyledRect {
                variant: "primary"
                anchors.fill: parent
                radius: desktop.radius
                backgroundOpacity: 0.14
                enableBorder: false
                animateRadius: false
                visible: !wallpaper.visible
            }
        }

        // Two tiled windows; the first is focused.
        Item {
            id: windowLayer
            anchors.fill: parent
            layer.enabled: root.windowShadow
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowBlur: Math.min(1, root.val(root.compositor, "shadowRange", 8) / 16)
                shadowOpacity: root.val(root.compositor, "shadowOpacity", 0.5)
                shadowColor: Config.resolveColor(root.val(root.compositor, "shadowColor", "shadow"))
            }

        Repeater {
            model: 2
            Item {
                id: win
                required property int index
                readonly property real gap: (root.gapsIn * 2 + 6) * root.k
                readonly property bool sideBySide: root.workArea.w >= root.workArea.h
                readonly property bool focused: index === 0
                readonly property real r: root.windowRounding * root.s * root.k * 0.8
                x: (root.workArea.x + (sideBySide ? index * (root.workArea.w + gap) / 2 : 0)) * root.s
                y: (root.workArea.y + (sideBySide ? 0 : index * (root.workArea.h + gap) / 2)) * root.s
                width: (sideBySide ? (root.workArea.w - gap) / 2 : root.workArea.w) * root.s
                height: (sideBySide ? root.workArea.h : (root.workArea.h - gap) / 2) * root.s

                StyledRect {
                    id: winBody
                    variant: "pane"
                    configOverride: root.srPane
                    anchors.fill: parent
                    radius: win.r
                    enableBorder: false
                    animateRadius: false

                    readonly property real u: Math.max(2, 10 * root.k * root.s)

                    // Title row: three dots and a title.
                    Row {
                        x: winBody.u
                        y: winBody.u
                        spacing: winBody.u * 0.5
                        Repeater {
                            model: 3
                            StyledRect {
                                variant: "common"
                                configOverride: root.paneInkStrong
                                enableBorder: false
                                animateRadius: false
                                width: winBody.u
                                height: winBody.u
                                radius: width / 2
                            }
                        }
                        StyledRect {
                            variant: "common"
                            configOverride: root.paneInkStrong
                            enableBorder: false
                            animateRadius: false
                            width: Math.max(0, winBody.width * 0.32)
                            height: winBody.u
                            radius: height / 2
                        }
                    }

                    // Content: a few lines of varying length.
                    Column {
                        x: winBody.u
                        y: winBody.u * 3.2
                        spacing: winBody.u * 0.7
                        Repeater {
                            model: [0.78, 0.55, 0.66, 0.4, 0.6]
                            StyledRect {
                                required property real modelData
                                variant: "common"
                                configOverride: root.paneInk
                                enableBorder: false
                                animateRadius: false
                                visible: y + height < winBody.height - winBody.u * 3.2 - winBody.u
                                width: Math.max(0, (winBody.width - 2 * winBody.u) * modelData)
                                height: winBody.u * 0.8
                                radius: height / 2
                            }
                        }
                    }
                }

                // Compositor border: active vs inactive.
                ClippingRectangle {
                    anchors.fill: parent
                    radius: win.r
                    color: "transparent"
                    border.width: root.windowBorder > 0 ? Math.max(1, root.windowBorder * root.k * root.s) : 0
                    border.color: win.focused ? root.activeBorder : root.inactiveBorder
                }
            }
        }
        }

        // The shell's chrome, casting the preset's shadow like the real panel.
        Item {
            id: chromeLayer
            anchors.fill: parent
            layer.enabled: root.chromeShadow
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowBlur: root.val(root.theme, "shadowBlur", 1)
                shadowOpacity: root.val(root.theme, "shadowOpacity", 0.5)
                shadowColor: Config.resolveColor(root.val(root.theme, "shadowColor", "shadow"))
                shadowHorizontalOffset: root.val(root.theme, "shadowXOffset", 0) * root.s * root.k
                shadowVerticalOffset: root.val(root.theme, "shadowYOffset", 0) * root.s * root.k
            }

        // Bar with pill groups. Inside a frame that contains it, the bar has no
        // surface of its own: it sits on the frame.
        StyledRect {
            id: barShape
            variant: "barbg"
            configOverride: root.srBar
            animateRadius: false
            enableBorder: !root.containBar
            backgroundOpacity: root.containBar ? 0 : -1
            x: root.barRect.x * root.s
            y: root.barRect.y * root.s
            width: root.barRect.w * root.s
            height: root.barRect.h * root.s
            radius: (root.containBar || root.barFlush) ? 0 : root.roundness * root.s * root.k * 0.6

            readonly property real pad: 6 * root.k * root.s
            readonly property real pillT: (root.barT - 12 * root.k) * root.s
            readonly property real pillR: (root.squished ? root.roundness / 2 : root.roundness) * root.s
            readonly property color ink: root.itemColorOf(root.srBar, Colors.overBackground)

            // Start group: launcher + two pills.
            Grid {
                x: barShape.pad
                y: barShape.pad
                rows: root.barVertical ? 3 : 1
                columns: root.barVertical ? 1 : 3
                spacing: 4 * root.s
                Repeater {
                    model: 3
                    StyledRect {
                        required property int index
                        variant: index === 0 ? "primary" : "common"
                        configOverride: index === 0 ? root.srPrimary : root.srCommon
                        enableBorder: false
                        animateRadius: false
                        width: root.barVertical ? barShape.pillT : barShape.pillT * (index === 0 ? 1 : 2.4)
                        height: root.barVertical ? barShape.pillT * (index === 0 ? 1 : 2.4) : barShape.pillT
                        radius: barShape.pillR
                    }
                }
            }

            // Center: workspace dots, or the integrated dock's icons. A notch
            // merged into the bar takes the centre instead.
            Grid {
                visible: !root.notchMerged || root.dockIntegrated
                readonly property int count: root.dockIntegrated ? root.dockIcons : 5
                rows: root.barVertical ? count : 1
                columns: root.barVertical ? 1 : count
                spacing: 5 * root.s
                anchors.centerIn: parent
                Repeater {
                    model: parent.count
                    StyledRect {
                        required property int index
                        readonly property bool activeWs: !root.dockIntegrated && index === 1
                        variant: activeWs ? "primary" : (root.dockIntegrated ? "focus" : "common")
                        configOverride: activeWs ? root.srPrimary : (root.dockIntegrated ? root.srFocus : root.srCommon)
                        enableBorder: false
                        animateRadius: false
                        width: barShape.pillT * (activeWs && !root.barVertical ? 1.4 : 0.7)
                        height: barShape.pillT * (activeWs && root.barVertical ? 1.4 : 0.7)
                        radius: root.dockIntegrated ? barShape.pillR * 0.6 : Math.min(width, height) / 2
                    }
                }
            }

            // End group: a pill and the clock (shows the preset's font).
            Grid {
                anchors.right: root.barVertical ? undefined : parent.right
                anchors.bottom: root.barVertical ? parent.bottom : undefined
                anchors.rightMargin: barShape.pad
                anchors.bottomMargin: barShape.pad
                x: root.barVertical ? barShape.pad : 0
                y: root.barVertical ? 0 : barShape.pad
                rows: root.barVertical ? 3 : 1
                columns: root.barVertical ? 1 : 3
                spacing: 4 * root.s
                // Tray icons, then the Control Center gear.
                StyledRect {
                    variant: "common"
                    configOverride: root.srCommon
                    enableBorder: false
                    animateRadius: false
                    width: root.barVertical ? barShape.pillT : barShape.pillT * 1.8
                    height: root.barVertical ? barShape.pillT * 1.8 : barShape.pillT
                    radius: barShape.pillR
                }
                StyledRect {
                    variant: "common"
                    configOverride: root.srCommon
                    enableBorder: false
                    animateRadius: false
                    width: barShape.pillT
                    height: barShape.pillT
                    radius: barShape.pillR
                    Text {
                        anchors.centerIn: parent
                        text: Icons.gear
                        font.family: Icons.font
                        font.pixelSize: Math.max(6, parent.height * 0.55)
                        color: root.itemColorOf(root.srCommon, barShape.ink)
                    }
                }
                StyledRect {
                    variant: "common"
                    configOverride: root.srCommon
                    enableBorder: false
                    animateRadius: false
                    width: root.barVertical ? barShape.pillT : clockText.implicitWidth + 4 * barShape.pad
                    height: root.barVertical ? clockText.implicitHeight + 2 * barShape.pad : barShape.pillT
                    radius: barShape.pillR
                    Text {
                        id: clockText
                        anchors.centerIn: parent
                        text: root.barVertical ? "12\n00" : "12:00"
                        horizontalAlignment: Text.AlignHCenter
                        lineHeight: 0.85
                        font.family: root.fontFamily
                        font.pixelSize: Math.max(7, 13 * root.s * root.k)
                        font.bold: true
                        color: root.itemColorOf(root.srCommon, barShape.ink)
                    }
                }
            }
        }

        // Notch. Attached: a body with concave corner ears where it meets the edge,
        // built like Notch.qml (a styled surface masked by the body plus two
        // RoundCorners). Island: a floating pill.
        Item {
            id: notchItem
            readonly property bool atTop: root.notchPos === "top"
            readonly property real cs: (root.notchIsland || root.notchMerged) ? 0 : root.notchCorner * root.s
            readonly property real r: root.notchIsland ? root.notchRect.h * root.s / 2 : Math.min(root.notchCorner * root.s, root.notchRect.h * root.s / 2)
            x: root.notchRect.x * root.s - cs
            y: root.notchRect.y * root.s
            width: root.notchRect.w * root.s + 2 * cs
            height: root.notchRect.h * root.s

            StyledRect {
                anchors.fill: parent
                visible: !root.notchMerged
                variant: "bg"
                configOverride: root.srBg
                enableBorder: root.notchIsland
                animateRadius: false
                radius: root.notchIsland ? notchItem.r : 0
                layer.enabled: !root.notchIsland
                layer.smooth: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: notchMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
            }

            Item {
                id: notchMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                layer.smooth: true

                RoundCorner {
                    x: 0
                    y: notchItem.atTop ? 0 : parent.height - height
                    width: notchItem.cs
                    height: notchItem.cs
                    size: Math.max(1, notchItem.cs)
                    corner: notchItem.atTop ? RoundCorner.CornerEnum.TopRight : RoundCorner.CornerEnum.BottomRight
                    color: "white"
                }
                // Mask shape only (never drawn): same approach as Notch.qml.
                Rectangle {
                    x: notchItem.cs
                    width: parent.width - 2 * notchItem.cs
                    height: parent.height
                    color: "white"
                    topLeftRadius: notchItem.atTop ? 0 : notchItem.r
                    topRightRadius: notchItem.atTop ? 0 : notchItem.r
                    bottomLeftRadius: notchItem.atTop ? notchItem.r : 0
                    bottomRightRadius: notchItem.atTop ? notchItem.r : 0
                }
                RoundCorner {
                    x: parent.width - width
                    y: notchItem.atTop ? 0 : parent.height - height
                    width: notchItem.cs
                    height: notchItem.cs
                    size: Math.max(1, notchItem.cs)
                    corner: notchItem.atTop ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.BottomLeft
                    color: "white"
                }
            }

            Text {
                anchors.centerIn: parent
                text: "user@host"
                font.family: root.fontFamily
                font.pixelSize: Math.max(7, 12 * root.s * root.k)
                color: root.notchMerged ? barShape.ink : root.itemColorOf(root.srBg, Colors.overBackground)
            }
        }

        // Standalone dock: attached to its edge, or floating.
        StyledRect {
            id: dockShape
            visible: root.dockOn && !root.dockIntegrated
            variant: "bg"
            configOverride: root.srBg
            animateRadius: false
            x: root.dockRect.x * root.s
            y: root.dockRect.y * root.s
            width: root.dockRect.w * root.s
            height: root.dockRect.h * root.s

            readonly property bool vertical: root.dockPos === "left" || root.dockPos === "right"
            readonly property real r: root.roundness * root.k * 0.7 * root.s
            readonly property bool attached: !root.dockFloating
            radius: r
            topLeftRadius: attached && (root.dockPos === "top" || root.dockPos === "left") ? 0 : r
            topRightRadius: attached && (root.dockPos === "top" || root.dockPos === "right") ? 0 : r
            bottomLeftRadius: attached && (root.dockPos === "bottom" || root.dockPos === "left") ? 0 : r
            bottomRightRadius: attached && (root.dockPos === "bottom" || root.dockPos === "right") ? 0 : r

            Grid {
                anchors.centerIn: parent
                rows: dockShape.vertical ? root.dockIcons : 1
                columns: dockShape.vertical ? 1 : root.dockIcons
                spacing: 12 * root.k * root.s
                Repeater {
                    model: root.dockIcons
                    StyledRect {
                        required property int index
                        variant: index === 0 ? "primary" : "focus"
                        configOverride: index === 0 ? root.srPrimary : root.srFocus
                        enableBorder: false
                        animateRadius: false
                        width: root.dockIcon * root.s
                        height: root.dockIcon * root.s
                        radius: Math.min(width / 2, root.roundness * root.s * 0.8)
                    }
                }
            }
        }
        }
    }
}
