import QtQuick
import QtQuick.Controls
ApplicationWindow {
    visible: true; width: 1280; height: 800; title: "UJM (QML baseline, no Python)"; color: "#14161a"
    Column { anchors.centerIn: parent; spacing: 12
        Repeater { model: 4
            Rectangle { width: 420; height: 64; radius: 8; color: "#22262d"
                Text { anchors.centerIn: parent; color: "#e6e8ec"; text: "Player " + (index + 1) + "  -  Pro Controller  -  87%" } } } }
}
