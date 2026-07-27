import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

QtObject {
    id: root

    function ensurePlatformTheme() {
        const home = Quickshell.env("HOME")
        const qt5Conf = home + "/.config/qt5ct/qt5ct.conf"
        const qt6Conf = home + "/.config/qt6ct/qt6ct.conf"
        const qt5Scheme = home + "/.config/qt5ct/colors/ambxst.colors"
        const qt6Scheme = home + "/.config/qt6ct/colors/ambxst.colors"

        // Ensure qt5ct/qt6ct select Ambxst palette without wiping unrelated user settings
        const cmd = `
ensure_qtct_conf() {
    conf="$1"
    scheme="$2"
    mkdir -p "$(dirname "$conf")"
    if [ ! -f "$conf" ]; then
        printf '%s\\n' \\
            '[Appearance]' \\
            "color_scheme_path=\${scheme}" \\
            'custom_palette=true' \\
            'style=Fusion' \\
            > "$conf"
        return
    fi

    if grep -q '^\\[Appearance\\]' "$conf"; then
        if grep -q '^color_scheme_path=' "$conf"; then
            sed -i "s|^color_scheme_path=.*|color_scheme_path=\${scheme}|" "$conf"
        else
            sed -i "/^\\[Appearance\\]/a color_scheme_path=\${scheme}" "$conf"
        fi
        if grep -q '^custom_palette=' "$conf"; then
            sed -i 's|^custom_palette=.*|custom_palette=true|' "$conf"
        else
            sed -i "/^\\[Appearance\\]/a custom_palette=true" "$conf"
        fi
        if ! grep -q '^style=' "$conf"; then
            sed -i "/^\\[Appearance\\]/a style=Fusion" "$conf"
        fi
    else
        printf '\\n%s\\n' \\
            '[Appearance]' \\
            "color_scheme_path=\${scheme}" \\
            'custom_palette=true' \\
            'style=Fusion' \\
            >> "$conf"
    fi
}

ensure_qtct_conf "${qt5Conf}" "${qt5Scheme}"
ensure_qtct_conf "${qt6Conf}" "${qt6Scheme}"

# Hint KDE-style consumers at the Ambxst scheme without wiping other kdeglobals keys
kdeglobals="${home}/.config/kdeglobals"
mkdir -p "$(dirname "$kdeglobals")"
if [ ! -f "$kdeglobals" ]; then
    printf '[General]\\nColorScheme=Ambxst\\n' > "$kdeglobals"
elif grep -q '^ColorScheme=' "$kdeglobals"; then
    sed -i 's|^ColorScheme=.*|ColorScheme=Ambxst|' "$kdeglobals"
elif grep -q '^\\[General\\]' "$kdeglobals"; then
    sed -i '/^\\[General\\]/a ColorScheme=Ambxst' "$kdeglobals"
else
    printf '\\n[General]\\nColorScheme=Ambxst\\n' >> "$kdeglobals"
fi
`

        configProcess.command = ["sh", "-c", cmd]
        configProcess.running = true
    }

    function generate(Colors) {
        if (!Colors) return

        // Helper to format color
        const fmt = (c) => c.toString()

        // Core colors
        const bg = Qt.rgba(Colors.background.r, Colors.background.g, Colors.background.b, Config.theme.srBg.opacity).toString()
        const fg = fmt(Colors.overBackground)
        const surface = fmt(Colors.surface)
        const primary = fmt(Colors.primary)
        const secondary = fmt(Colors.secondary)
        const error = fmt(Colors.error)
        const inactive = fmt(Colors.outline)
        const link = fmt(Colors.tertiary)
        const selection = fmt(Colors.primary)
        const selectionFg = fmt(Colors.overPrimary)

        // Construct INI content
        let ini = ""

        ini += "[ColorEffects:Disabled]\n"
        ini += `Color=${bg}\n`
        ini += "ColorAmount=0.5\n"
        ini += "ColorEffect=3\n"
        ini += "ContrastAmount=0\n"
        ini += "ContrastEffect=0\n"
        ini += "IntensityAmount=0\n"
        ini += "IntensityEffect=0\n\n"

        ini += "[ColorEffects:Inactive]\n"
        ini += "ChangeSelectionColor=true\n"
        ini += `Color=${bg}\n`
        ini += "ColorAmount=0.025\n"
        ini += "ColorEffect=0\n"
        ini += "ContrastAmount=0.1\n"
        ini += "ContrastEffect=0\n"
        ini += "Enable=true\n"
        ini += "IntensityAmount=0\n"
        ini += "IntensityEffect=0\n\n"

        ini += "[Colors:Button]\n"
        ini += `BackgroundAlternate=${surface}\n`
        ini += `BackgroundNormal=${surface}\n`
        ini += `DecorationFocus=${primary}\n`
        ini += `DecorationHover=${primary}\n`
        ini += `ForegroundActive=${fg}\n`
        ini += `ForegroundInactive=${inactive}\n`
        ini += `ForegroundLink=${link}\n`
        ini += `ForegroundNegative=${error}\n`
        ini += `ForegroundNeutral=${fg}\n`
        ini += `ForegroundNormal=${fg}\n`
        ini += `ForegroundPositive=${secondary}\n`
        ini += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
        ini += "\n"

        ini += "[Colors:Complementary]\n"
        ini += `BackgroundAlternate=${bg}\n`
        ini += `BackgroundNormal=${bg}\n`
        ini += `DecorationFocus=${primary}\n`
        ini += `DecorationHover=${primary}\n`
        ini += `ForegroundActive=${fg}\n`
        ini += `ForegroundInactive=${inactive}\n`
        ini += `ForegroundLink=${link}\n`
        ini += `ForegroundNegative=${error}\n`
        ini += `ForegroundNeutral=${fg}\n`
        ini += `ForegroundNormal=${fg}\n`
        ini += `ForegroundPositive=${secondary}\n`
        ini += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
        ini += "\n"

        ini += "[Colors:Header]\n"
        ini += `BackgroundAlternate=${bg}\n`
        ini += `BackgroundNormal=${bg}\n`
        ini += `DecorationFocus=${primary}\n`
        ini += `DecorationHover=${primary}\n`
        ini += `ForegroundActive=${fg}\n`
        ini += `ForegroundInactive=${inactive}\n`
        ini += `ForegroundLink=${link}\n`
        ini += `ForegroundNegative=${error}\n`
        ini += `ForegroundNeutral=${fg}\n`
        ini += `ForegroundNormal=${fg}\n`
        ini += `ForegroundPositive=${secondary}\n`
        ini += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
        ini += "\n"

        ini += "[Colors:Header][Inactive]\n"
        ini += `BackgroundAlternate=${bg}\n`
        ini += `BackgroundNormal=${bg}\n`
        ini += `DecorationFocus=${primary}\n`
        ini += `DecorationHover=${primary}\n`
        ini += `ForegroundActive=${fg}\n`
        ini += `ForegroundInactive=${inactive}\n`
        ini += `ForegroundLink=${link}\n`
        ini += `ForegroundNegative=${error}\n`
        ini += `ForegroundNeutral=${fg}\n`
        ini += `ForegroundNormal=${fg}\n`
        ini += `ForegroundPositive=${secondary}\n`
        ini += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
        ini += "\n"

        ini += "[Colors:Selection]\n"
        ini += `BackgroundAlternate=${selection}\n`
        ini += `BackgroundNormal=${selection}\n`
        ini += `DecorationFocus=${selection}\n`
        ini += `DecorationHover=${selection}\n`
        ini += `ForegroundActive=${selectionFg}\n`
        ini += `ForegroundInactive=${selectionFg}\n`
        ini += `ForegroundLink=${link}\n`
        ini += `ForegroundNegative=${error}\n`
        ini += `ForegroundNeutral=${selectionFg}\n`
        ini += `ForegroundNormal=${selectionFg}\n`
        ini += `ForegroundPositive=${secondary}\n`
        ini += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
        ini += "\n"

        ini += "[Colors:Tooltip]\n"
        ini += `BackgroundAlternate=${surface}\n`
        ini += `BackgroundNormal=${bg}\n`
        ini += `DecorationFocus=${primary}\n`
        ini += `DecorationHover=${primary}\n`
        ini += `ForegroundActive=${fg}\n`
        ini += `ForegroundInactive=${inactive}\n`
        ini += `ForegroundLink=${link}\n`
        ini += `ForegroundNegative=${error}\n`
        ini += `ForegroundNeutral=${fg}\n`
        ini += `ForegroundNormal=${fg}\n`
        ini += `ForegroundPositive=${secondary}\n`
        ini += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
        ini += "\n"

        ini += "[Colors:View]\n"
        ini += `BackgroundAlternate=${surface}\n`
        ini += `BackgroundNormal=${bg}\n`
        ini += `DecorationFocus=${primary}\n`
        ini += `DecorationHover=${primary}\n`
        ini += `ForegroundActive=${fg}\n`
        ini += `ForegroundInactive=${inactive}\n`
        ini += `ForegroundLink=${link}\n`
        ini += `ForegroundNegative=${error}\n`
        ini += `ForegroundNeutral=${fg}\n`
        ini += `ForegroundNormal=${fg}\n`
        ini += `ForegroundPositive=${secondary}\n`
        ini += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
        ini += "\n"

        ini += "[Colors:Window]\n"
        ini += `BackgroundAlternate=${surface}\n`
        ini += `BackgroundNormal=${bg}\n`
        ini += `DecorationFocus=${primary}\n`
        ini += `DecorationHover=${primary}\n`
        ini += `ForegroundActive=${fg}\n`
        ini += `ForegroundInactive=${inactive}\n`
        ini += `ForegroundLink=${link}\n`
        ini += `ForegroundNegative=${error}\n`
        ini += `ForegroundNeutral=${fg}\n`
        ini += `ForegroundNormal=${fg}\n`
        ini += `ForegroundPositive=${secondary}\n`
        ini += `ForegroundVisited=${fmt(Colors.tertiary)}\n`
        ini += "\n"

        ini += "[General]\n"
        ini += "ColorScheme=Ambxst\n"
        ini += "Name=Ambxst\n"
        ini += "shadeSortColumn=true\n"
        ini += "\n"
        
        ini += "[KDE]\n"
        ini += "contrast=4\n"
        ini += "\n"
        
        ini += "[WM]\n"
        ini += `activeBackground=${bg}\n`
        ini += "activeBlend=252,252,252\n" 
        ini += `activeForeground=${fg}\n`
        ini += `inactiveBackground=${fmt(Colors.surfaceDim)}\n`
        ini += "inactiveBlend=161,169,177\n"
        ini += `inactiveForeground=${inactive}\n`

        const home = Quickshell.env("HOME")
        const qt5Dir = home + "/.config/qt5ct/colors"
        const qt6Dir = home + "/.config/qt6ct/colors"
        const kdeSchemeDir = home + "/.local/share/color-schemes"
        const qt5Conf = home + "/.config/qt5ct/qt5ct.conf"
        const qt6Conf = home + "/.config/qt6ct/qt6ct.conf"
        const qt5Scheme = qt5Dir + "/ambxst.colors"
        const qt6Scheme = qt6Dir + "/ambxst.colors"

        writer.text = ini
        
        // Write color schemes, expose to KDE color-schemes, and select them in qt*ct.conf
        const cmd = `
mkdir -p "${qt5Dir}" "${qt6Dir}" "${kdeSchemeDir}" && \\
echo "${ini}" | tee "${qt5Scheme}" "${qt6Scheme}" "${kdeSchemeDir}/Ambxst.colors" > /dev/null

ensure_qtct_conf() {
    conf="$1"
    scheme="$2"
    mkdir -p "$(dirname "$conf")"
    if [ ! -f "$conf" ]; then
        printf '%s\\n' \\
            '[Appearance]' \\
            "color_scheme_path=\${scheme}" \\
            'custom_palette=true' \\
            'style=Fusion' \\
            > "$conf"
        return
    fi

    if grep -q '^\\[Appearance\\]' "$conf"; then
        if grep -q '^color_scheme_path=' "$conf"; then
            sed -i "s|^color_scheme_path=.*|color_scheme_path=\${scheme}|" "$conf"
        else
            sed -i "/^\\[Appearance\\]/a color_scheme_path=\${scheme}" "$conf"
        fi
        if grep -q '^custom_palette=' "$conf"; then
            sed -i 's|^custom_palette=.*|custom_palette=true|' "$conf"
        else
            sed -i "/^\\[Appearance\\]/a custom_palette=true" "$conf"
        fi
        if ! grep -q '^style=' "$conf"; then
            sed -i "/^\\[Appearance\\]/a style=Fusion" "$conf"
        fi
    else
        printf '\\n%s\\n' \\
            '[Appearance]' \\
            "color_scheme_path=\${scheme}" \\
            'custom_palette=true' \\
            'style=Fusion' \\
            >> "$conf"
    fi
}

ensure_qtct_conf "${qt5Conf}" "${qt5Scheme}"
ensure_qtct_conf "${qt6Conf}" "${qt6Scheme}"

kdeglobals="${home}/.config/kdeglobals"
mkdir -p "$(dirname "$kdeglobals")"
if [ ! -f "$kdeglobals" ]; then
    printf '[General]\\nColorScheme=Ambxst\\n' > "$kdeglobals"
elif grep -q '^ColorScheme=' "$kdeglobals"; then
    sed -i 's|^ColorScheme=.*|ColorScheme=Ambxst|' "$kdeglobals"
elif grep -q '^\\[General\\]' "$kdeglobals"; then
    sed -i '/^\\[General\\]/a ColorScheme=Ambxst' "$kdeglobals"
else
    printf '\\n[General]\\nColorScheme=Ambxst\\n' >> "$kdeglobals"
fi
`
        
        writerProcess.command = ["sh", "-c", cmd]
        writerProcess.running = true
    }
    
    property QtObject writer: QtObject {
        id: writer
        property string text
    }

    property Process writerProcess: Process {
        id: writerProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: console.log("QtCtGenerator: Colors and qt*ct config generated.")
        }
        stderr: StdioCollector {
            onStreamFinished: (err) => {
                if (err) console.error("QtCtGenerator Error:", err)
            }
        }
    }

    property Process configProcess: Process {
        id: configProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: console.log("QtCtGenerator: Platform theme config ensured.")
        }
        stderr: StdioCollector {
            onStreamFinished: (err) => {
                if (err) console.error("QtCtGenerator config error:", err)
            }
        }
    }
}
