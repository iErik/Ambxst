import QtQuick
import qs.modules.components
import qs.modules.theme
import qs.modules.services

ToggleButton {
    id: toolsButton

    property bool clusterVisible: true

    visible: clusterVisible
    implicitWidth: clusterVisible ? 36 : 0
    implicitHeight: clusterVisible ? 36 : 0

    buttonIcon: Icons.toolbox
    tooltipText: "Tools"
    onToggle: function () {
        if (Visibilities.currentActiveModule === "tools") {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule("tools");
        }
    }
}
