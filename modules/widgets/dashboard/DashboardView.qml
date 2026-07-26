import QtQuick
import qs.modules.widgets.dashboard
import qs.modules.services

Item {
    id: root

    // Drive notch chrome from the real dashboard size (not stale hardcoded implicits)
    implicitWidth: dashboardItem.width
    implicitHeight: dashboardItem.height
    property string screenName: ""

    readonly property int leftPanelWidth: 270

    Dashboard {
        id: dashboardItem
        // Dashboard manages its own width/height via animatedWidth/Height.
        // Do not anchors.fill — that fought explicit sizing and crushed WidgetsTab.
        leftPanelWidth: root.leftPanelWidth
        screenName: root.screenName

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Visibilities.setActiveModule("");
                event.accepted = true;
            } else if (event.key === Qt.Key_Space) {
                event.accepted = false;
            }
        }

        Component.onCompleted: {
            Qt.callLater(() => {
                forceActiveFocus();
            });
        }
    }
}
