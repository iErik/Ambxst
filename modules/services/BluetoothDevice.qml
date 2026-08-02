import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string address: ""
    property string name: "Unknown"
    property string icon: "bluetooth"
    property bool paired: false
    property bool connected: false
    property bool trusted: false
    property int battery: -1
    property bool batteryAvailable: battery >= 0
    property bool connecting: false

    signal infoUpdated()

    // Connect (pair if needed, auto-trust)
    function connect() {
        connecting = true;
        BluetoothService.ensureAgent();

        let chain = Promise.resolve();

        if (!paired) {
            chain = chain.then(() => BluetoothService.runAsync(["bluetoothctl", "pair", address]));
        }

        if (!trusted) {
            chain = chain.then(() => BluetoothService.runAsync(["bluetoothctl", "trust", address]));
        }

        chain = chain.then(() => BluetoothService.runAsync(["bluetoothctl", "connect", address]));

        return chain.catch(e => {
            console.error(`Failed to connect to ${address}: ${e}`);
            BluetoothService.lastError = String(e || "Connect failed");
        }).finally(() => {
            connecting = false;
            updateInfo();
            BluetoothService.updateDevices();
        });
    }

    function updateInfo() {
        return BluetoothService.runAsync(["bluetoothctl", "info", address]).then(text => {
            Qt.callLater(() => {
                const lines = text.split("\n");
                for (const line of lines) {
                    const trimmed = line.trim();
                    if (trimmed.startsWith("Paired:")) {
                        root.paired = trimmed.includes("yes");
                    } else if (trimmed.startsWith("Connected:")) {
                        root.connected = trimmed.includes("yes");
                        if (root.connected)
                            root.connecting = false;
                    } else if (trimmed.startsWith("Trusted:")) {
                        root.trusted = trimmed.includes("yes");
                    } else if (trimmed.startsWith("Icon:")) {
                        root.icon = trimmed.split(":")[1]?.trim() || "bluetooth";
                    } else if (trimmed.startsWith("Battery Percentage:")) {
                        const match = trimmed.match(/\((\d+)\)/);
                        if (match) {
                            root.battery = parseInt(match[1]) || -1;
                        }
                    }
                }
                root.infoUpdated();
            });
        }).catch(e => {
            console.error(`Failed to get info for ${address}: ${e}`);
        });
    }

    function disconnect() {
        BluetoothService.disconnectDevice(address);
    }

    function pair() {
        BluetoothService.ensureAgent();
        BluetoothService.pairDevice(address);
    }

    function trust() {
        BluetoothService.trustDevice(address);
    }

    function forget() {
        BluetoothService.removeDevice(address);
    }
}
