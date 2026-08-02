import QtQuick
import qs.modules.globals
import qs.modules.services
import qs.config
import qs.modules.components
import qs.modules.theme

ToggleButton {
    property bool clusterVisible: true

    visible: clusterVisible
    implicitWidth: clusterVisible ? 36 : 0
    implicitHeight: clusterVisible ? 36 : 0

    buttonIcon: Icons.magicWand
    tooltipText: "Open Presets Manager"

    onToggle: function () {
        if (GlobalStates.presetsOpen) {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule("presets");
        }
    }
}