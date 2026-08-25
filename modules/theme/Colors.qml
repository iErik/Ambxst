pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

FileView {
    id: colors
    // QUICKSHELL-GIT: path: Quickshell.cachePath("colors.json")
    path: Quickshell.env("HOME") + "/.cache/ambxst/colors.json"
    preload: true
    watchChanges: true
    onFileChanged: {
        reload();
        generationTimer.restart();
    }

    property Connections oledWatcher: Connections {
        target: Config
        function onOledModeChanged() {
            generationTimer.restart();
        }
    }

    property Connections themeWatcher: Connections {
        target: Config.loader
        function onFileChanged() {
            generationTimer.restart();
        }
    }

    property QtCtGenerator qtCtGenerator: QtCtGenerator {
        id: qtCtGenerator
    }

    property GtkGenerator gtkGenerator: GtkGenerator {
        id: gtkGenerator
    }

    property PywalGenerator pywalGenerator: PywalGenerator {
        id: pywalGenerator
    }

    property KittyGenerator kittyGenerator: KittyGenerator {
        id: kittyGenerator
    }

    property NvChadGenerator nvChadGenerator: NvChadGenerator {
        id: nvChadGenerator
    }

    property DiscordGenerator discordGenerator: DiscordGenerator {
        id: discordGenerator
    }

    // Apply system-wide color-scheme immediately when light/dark toggles,
    // without waiting for matugen to rewrite colors.json.
    property Connections lightModeWatcher: Connections {
        target: Config
        function onLightModeChanged() {
            gtkGenerator.syncSystemScheme();
            qtCtGenerator.ensurePlatformTheme();
        }
    }

    property Connections iconThemeWatcher: Connections {
        target: Config
        function onIconThemeChanged() {
            if (Config.iconTheme)
                colors.applyIconTheme(Config.iconTheme);
        }
    }

    property Connections cursorThemeWatcher: Connections {
        target: Config
        function onCursorThemeChanged() {
            if (Config.cursorTheme)
                colors.applyCursorTheme(Config.cursorTheme);
        }
    }

    property Timer generationTimer: Timer {
        id: generationTimer
        interval: 100
        repeat: false
        onTriggered: {
            qtCtGenerator.generate(colors);
            gtkGenerator.generate(colors);
            pywalGenerator.generate(colors);
            kittyGenerator.generate(colors);
            nvChadGenerator.generate(colors);
            discordGenerator.generate(colors);
        }
    }

    function applyIconTheme(themeId) {
        if (!themeId)
            return;

        const home = Quickshell.env("HOME");
        const gtk3Ini = home + "/.config/gtk-3.0/settings.ini";
        const gtk4Ini = home + "/.config/gtk-4.0/settings.ini";
        const qt5Conf = home + "/.config/qt5ct/qt5ct.conf";
        const qt6Conf = home + "/.config/qt6ct/qt6ct.conf";

        const cmd = `
theme_id=${JSON.stringify(themeId)}

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface icon-theme "$theme_id" || true
fi

update_ini_key() {
    file="$1"
    key="$2"
    val="$3"
    mkdir -p "$(dirname "$file")"
    if [ ! -f "$file" ]; then
        printf '[Settings]\\n%s=%s\\n' "$key" "$val" > "$file"
        return
    fi
    if grep -q "^\${key}=" "$file"; then
        sed -i "s|^\${key}=.*|\${key}=\${val}|" "$file"
    elif grep -q '^\\[Settings\\]' "$file"; then
        sed -i "/^\\[Settings\\]/a \${key}=\${val}" "$file"
    else
        printf '\\n[Settings]\\n%s=%s\\n' "$key" "$val" >> "$file"
    fi
}

update_qtct_icon() {
    conf="$1"
    val="$2"
    mkdir -p "$(dirname "$conf")"
    if [ ! -f "$conf" ]; then
        printf '[Appearance]\\nicon_theme=%s\\ncustom_palette=true\\nstyle=Fusion\\n' "$val" > "$conf"
        return
    fi
    if grep -q '^icon_theme=' "$conf"; then
        sed -i "s|^icon_theme=.*|icon_theme=\${val}|" "$conf"
    elif grep -q '^\\[Appearance\\]' "$conf"; then
        sed -i "/^\\[Appearance\\]/a icon_theme=\${val}" "$conf"
    else
        printf '\\n[Appearance]\\nicon_theme=%s\\n' "$val" >> "$conf"
    fi
}

update_ini_key "${gtk3Ini}" "gtk-icon-theme-name" "$theme_id"
update_ini_key "${gtk4Ini}" "gtk-icon-theme-name" "$theme_id"
update_qtct_icon "${qt5Conf}" "$theme_id"
update_qtct_icon "${qt6Conf}" "$theme_id"
`
        iconThemeProcess.command = ["sh", "-c", cmd];
        iconThemeProcess.running = true;
    }

    function applyCursorTheme(themeId) {
        if (!themeId)
            return;

        const home = Quickshell.env("HOME");
        const gtk3Ini = home + "/.config/gtk-3.0/settings.ini";
        const gtk4Ini = home + "/.config/gtk-4.0/settings.ini";
        const qt5Conf = home + "/.config/qt5ct/qt5ct.conf";
        const qt6Conf = home + "/.config/qt6ct/qt6ct.conf";

        const cmd = `
theme_id=${JSON.stringify(themeId)}

cursor_size=""
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface cursor-theme "$theme_id" || true
    cursor_size=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null | tr -d "'" || true)
fi
if [ -z "$cursor_size" ] || [ "$cursor_size" = "0" ]; then
    cursor_size=24
fi

update_ini_key() {
    file="$1"
    key="$2"
    val="$3"
    mkdir -p "$(dirname "$file")"
    if [ ! -f "$file" ]; then
        printf '[Settings]\\n%s=%s\\n' "$key" "$val" > "$file"
        return
    fi
    if grep -q "^\${key}=" "$file"; then
        sed -i "s|^\${key}=.*|\${key}=\${val}|" "$file"
    elif grep -q '^\\[Settings\\]' "$file"; then
        sed -i "/^\\[Settings\\]/a \${key}=\${val}" "$file"
    else
        printf '\\n[Settings]\\n%s=%s\\n' "$key" "$val" >> "$file"
    fi
}

update_qtct_cursor() {
    conf="$1"
    val="$2"
    mkdir -p "$(dirname "$conf")"
    if [ ! -f "$conf" ]; then
        printf '[Appearance]\\ncursor_theme=%s\\ncustom_palette=true\\nstyle=Fusion\\n' "$val" > "$conf"
        return
    fi
    if grep -q '^cursor_theme=' "$conf"; then
        sed -i "s|^cursor_theme=.*|cursor_theme=\${val}|" "$conf"
    elif grep -q '^\\[Appearance\\]' "$conf"; then
        sed -i "/^\\[Appearance\\]/a cursor_theme=\${val}" "$conf"
    else
        printf '\\n[Appearance]\\ncursor_theme=%s\\n' "$val" >> "$conf"
    fi
}

update_ini_key "${gtk3Ini}" "gtk-cursor-theme-name" "$theme_id"
update_ini_key "${gtk4Ini}" "gtk-cursor-theme-name" "$theme_id"
update_qtct_cursor "${qt5Conf}" "$theme_id"
update_qtct_cursor "${qt6Conf}" "$theme_id"

# Apply immediately on Hyprland when this session is Hyprland
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
    hyprctl setcursor "$theme_id" "$cursor_size" >/dev/null 2>&1 || true
fi
`
        cursorThemeProcess.command = ["sh", "-c", cmd];
        cursorThemeProcess.running = true;
    }

    property Process iconThemeProcess: Process {
        id: iconThemeProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: console.log("Colors: Icon theme applied.")
        }
        stderr: StdioCollector {
            onStreamFinished: err => {
                if (err)
                    console.error("Colors icon theme error:", err);
            }
        }
    }

    property Process cursorThemeProcess: Process {
        id: cursorThemeProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: console.log("Colors: Cursor theme applied.")
        }
        stderr: StdioCollector {
            onStreamFinished: err => {
                if (err)
                    console.error("Colors cursor theme error:", err);
            }
        }
    }

    // Keep OS color-scheme / icon / cursor theme aligned with Ambxst even if colors.json was unchanged.
    Component.onCompleted: {
        Qt.callLater(() => {
            gtkGenerator.syncSystemScheme();
            qtCtGenerator.ensurePlatformTheme();
            if (Config.iconTheme)
                colors.applyIconTheme(Config.iconTheme);
            if (Config.cursorTheme)
                colors.applyCursorTheme(Config.cursorTheme);
        });
    }

    adapter: JsonAdapter {
        property color background: "#1a1111"
        property color blue: "#cebdfe"
        property color blueContainer: "#4c3e76"
        property color blueSource: "#0000ff"
        property color blueValue: "#0000ff"
        property color cyan: "#84d5c4"
        property color cyanContainer: "#005045"
        property color cyanSource: "#00ffff"
        property color cyanValue: "#00ffff"
        property color error: "#ffb4ab"
        property color errorContainer: "#93000a"
        property color green: "#b7d085"
        property color greenContainer: "#3a4d10"
        property color greenSource: "#00ff00"
        property color greenValue: "#00ff00"
        property color inverseOnSurface: "#382e2d"
        property color inversePrimary: "#904a46"
        property color inverseSurface: "#f1dedd"
        property color lightBlue: "#cebdfe"
        property color lightCyan: "#84d5c4"
        property color lightGreen: "#b7d085"
        property color lightMagenta: "#fcb0d5"
        property color lightRed: "#ffb4ab"
        property color lightYellow: "#dec56e"
        property color magenta: "#fcb0d5"
        property color magentaContainer: "#6c3353"
        property color magentaSource: "#ff00ff"
        property color magentaValue: "#ff00ff"
        property color overBackground: "#f1dedd"
        property color overBlue: "#35275e"
        property color overBlueContainer: "#e8ddff"
        property color overCyan: "#00382f"
        property color overCyanContainer: "#9ff2e0"
        property color overError: "#690005"
        property color overErrorContainer: "#ffdad6"
        property color overGreen: "#253600"
        property color overGreenContainer: "#d3ec9e"
        property color overMagenta: "#521d3c"
        property color overMagentaContainer: "#ffd8e8"
        property color overPrimary: "#571d1c"
        property color overPrimaryContainer: "#ffdad7"
        property color overPrimaryFixed: "#3b0809"
        property color overPrimaryFixedVariant: "#733331"
        property color overRed: "#561e19"
        property color overRedContainer: "#ffdad6"
        property color overSecondary: "#442928"
        property color overSecondaryContainer: "#ffdad7"
        property color overSecondaryFixed: "#2c1514"
        property color overSecondaryFixedVariant: "#5d3f3d"
        property color overSurface: "#f1dedd"
        property color overSurfaceVariant: "#d8c2c0"
        property color overTertiary: "#402d04"
        property color overTertiaryContainer: "#ffdea7"
        property color overTertiaryFixed: "#271900"
        property color overTertiaryFixedVariant: "#594319"
        property color overWhite: "#00363d"
        property color overWhiteContainer: "#9eeffd"
        property color overYellow: "#3b2f00"
        property color overYellowContainer: "#fce186"
        property color outline: "#a08c8b"
        property color outlineVariant: "#534342"
        property color primary: "#ffb3ae"
        property color primaryContainer: "#733331"
        property color primaryFixed: "#ffdad7"
        property color primaryFixedDim: "#ffb3ae"
        property color red: "#ffb4ab"
        property color redContainer: "#73332e"
        property color redSource: "#ff0000"
        property color redValue: "#ff0000"
        property color scrim: "#000000"
        property color secondary: "#e7bdb9"
        property color secondaryContainer: "#5d3f3d"
        property color secondaryFixed: "#ffdad7"
        property color secondaryFixedDim: "#e7bdb9"
        property color shadow: "#000000"
        property color surface: "#1a1111"
        property color surfaceBright: "#423736"
        property color surfaceContainer: "#271d1d"
        property color surfaceContainerHigh: "#322827"
        property color surfaceContainerHighest: "#3d3231"
        property color surfaceContainerLow: "#231919"
        property color surfaceContainerLowest: "#140c0c"
        property color surfaceDim: "#1a1111"
        property color surfaceTint: "#ffb3ae"
        property color surfaceVariant: "#534342"
        property color tertiary: "#e2c28c"
        property color tertiaryContainer: "#594319"
        property color tertiaryFixed: "#ffdea7"
        property color tertiaryFixedDim: "#e2c28c"
        property color white: "#82d3e0"
        property color whiteContainer: "#004f58"
        property color whiteSource: "#ffffff"
        property color whiteValue: "#ffffff"
        property color yellow: "#dec56e"
        property color yellowContainer: "#554500"
        property color yellowSource: "#ffff00"
        property color yellowValue: "#ffff00"
        property color sourceColor: "#7f2424"
    }

    property color background: Config.oledMode ? "#000000" : adapter.background

    property color surface: Qt.tint(background, Qt.rgba(adapter.overBackground.r, adapter.overBackground.g, adapter.overBackground.b, 0.1))
    property color surfaceBright: Qt.tint(background, Qt.rgba(adapter.overBackground.r, adapter.overBackground.g, adapter.overBackground.b, 0.2))
    property color surfaceContainer: adapter.surfaceContainer
    property color surfaceContainerHigh: adapter.surfaceContainerHigh
    property color surfaceContainerHighest: adapter.surfaceContainerHighest
    property color surfaceContainerLow: adapter.surfaceContainerLow
    property color surfaceContainerLowest: adapter.surfaceContainerLowest
    property color surfaceDim: adapter.surfaceDim
    property color surfaceTint: adapter.surfaceTint
    property color surfaceVariant: adapter.surfaceVariant

    // Direct color properties from adapter
    property color blue: adapter.blue
    property color blueContainer: adapter.blueContainer
    property color blueSource: adapter.blueSource
    property color blueValue: adapter.blueValue
    property color cyan: adapter.cyan
    property color cyanContainer: adapter.cyanContainer
    property color cyanSource: adapter.cyanSource
    property color cyanValue: adapter.cyanValue
    property color error: adapter.error
    property color errorContainer: adapter.errorContainer
    property color green: adapter.green
    property color greenContainer: adapter.greenContainer
    property color greenSource: adapter.greenSource
    property color greenValue: adapter.greenValue
    property color inverseOnSurface: adapter.inverseOnSurface
    property color inversePrimary: adapter.inversePrimary
    property color inverseSurface: adapter.inverseSurface
    property color lightBlue: adapter.lightBlue
    property color lightCyan: adapter.lightCyan
    property color lightGreen: adapter.lightGreen
    property color lightMagenta: adapter.lightMagenta
    property color lightRed: adapter.lightRed
    property color lightYellow: adapter.lightYellow
    property color magenta: adapter.magenta
    property color magentaContainer: adapter.magentaContainer
    property color magentaSource: adapter.magentaSource
    property color magentaValue: adapter.magentaValue
    property color overBackground: adapter.overBackground
    property color overBlue: adapter.overBlue
    property color overBlueContainer: adapter.overBlueContainer
    property color overCyan: adapter.overCyan
    property color overCyanContainer: adapter.overCyanContainer
    property color overError: adapter.overError
    property color overErrorContainer: adapter.overErrorContainer
    property color overGreen: adapter.overGreen
    property color overGreenContainer: adapter.overGreenContainer
    property color overMagenta: adapter.overMagenta
    property color overMagentaContainer: adapter.overMagentaContainer
    property color overPrimary: adapter.overPrimary
    property color overPrimaryContainer: adapter.overPrimaryContainer
    property color overPrimaryFixed: adapter.overPrimaryFixed
    property color overPrimaryFixedVariant: adapter.overPrimaryFixedVariant
    property color overRed: adapter.overRed
    property color overRedContainer: adapter.overRedContainer
    property color overSecondary: adapter.overSecondary
    property color overSecondaryContainer: adapter.overSecondaryContainer
    property color overSecondaryFixed: adapter.overSecondaryFixed
    property color overSecondaryFixedVariant: adapter.overSecondaryFixedVariant
    property color overSurface: adapter.overSurface
    property color overSurfaceVariant: adapter.overSurfaceVariant
    property color overTertiary: adapter.overTertiary
    property color overTertiaryContainer: adapter.overTertiaryContainer
    property color overTertiaryFixed: adapter.overTertiaryFixed
    property color overTertiaryFixedVariant: adapter.overTertiaryFixedVariant
    property color overWhite: adapter.overWhite
    property color overWhiteContainer: adapter.overWhiteContainer
    property color overYellow: adapter.overYellow
    property color overYellowContainer: adapter.overYellowContainer
    property color outline: adapter.outline
    property color outlineVariant: adapter.outlineVariant
    property color primary: adapter.primary
    property color primaryContainer: adapter.primaryContainer
    property color primaryFixed: adapter.primaryFixed
    property color primaryFixedDim: adapter.primaryFixedDim
    property color red: adapter.red
    property color redContainer: adapter.redContainer
    property color redSource: adapter.redSource
    property color redValue: adapter.redValue
    property color scrim: adapter.scrim
    property color secondary: adapter.secondary
    property color secondaryContainer: adapter.secondaryContainer
    property color secondaryFixed: adapter.secondaryFixed
    property color secondaryFixedDim: adapter.secondaryFixedDim
    property color shadow: adapter.shadow
    property color tertiary: adapter.tertiary
    property color tertiaryContainer: adapter.tertiaryContainer
    property color tertiaryFixed: adapter.tertiaryFixed
    property color tertiaryFixedDim: adapter.tertiaryFixedDim
    property color white: adapter.white
    property color whiteContainer: adapter.whiteContainer
    property color whiteSource: adapter.whiteSource
    property color whiteValue: adapter.whiteValue
    property color yellow: adapter.yellow
    property color yellowContainer: adapter.yellowContainer
    property color yellowSource: adapter.yellowSource
    property color yellowValue: adapter.yellowValue
    property color sourceColor: adapter.sourceColor

    property color criticalText: "#FF6B08"
    property color criticalRed: "#FF0028"

    // Semantic aliases
    property color warning: adapter.yellow
    property color success: adapter.green

    // List of available color names for color pickers (excludes internal/source colors)
    readonly property var availableColorNames: ["background", "surface", "surfaceBright", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "surfaceContainerLow", "surfaceContainerLowest", "surfaceDim", "surfaceTint", "surfaceVariant", "primary", "primaryContainer", "primaryFixed", "primaryFixedDim", "secondary", "secondaryContainer", "secondaryFixed", "secondaryFixedDim", "tertiary", "tertiaryContainer", "tertiaryFixed", "tertiaryFixedDim", "error", "errorContainer", "overBackground", "overSurface", "overSurfaceVariant", "overPrimary", "overPrimaryContainer", "overPrimaryFixed", "overPrimaryFixedVariant", "overSecondary", "overSecondaryContainer", "overSecondaryFixed", "overSecondaryFixedVariant", "overTertiary", "overTertiaryContainer", "overTertiaryFixed", "overTertiaryFixedVariant", "overError", "overErrorContainer", "outline", "outlineVariant", "inversePrimary", "inverseSurface", "inverseOnSurface", "shadow", "scrim", "blue", "blueContainer", "overBlue", "overBlueContainer", "lightBlue", "cyan", "cyanContainer", "overCyan", "overCyanContainer", "lightCyan", "green", "greenContainer", "overGreen", "overGreenContainer", "lightGreen", "magenta", "magentaContainer", "overMagenta", "overMagentaContainer", "lightMagenta", "red", "redContainer", "overRed", "overRedContainer", "lightRed", "yellow", "yellowContainer", "overYellow", "overYellowContainer", "lightYellow", "white", "whiteContainer", "overWhite", "overWhiteContainer"]
}
