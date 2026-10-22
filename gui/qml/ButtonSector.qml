import QtQuick

Rectangle {
    id: sector
    objectName: "buttonSector"
    required property string title
    required property var buttons
    implicitHeight: content.implicitHeight + 20
    color: Theme.panel
    border.color: Theme.line
    border.width: 1
    radius: Theme.radius

    Column {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 8
        Text { text: sector.title; color: Theme.muted; font.pixelSize: 12; font.bold: true }
        Flow {
            width: parent.width
            spacing: 7
            Repeater {
                model: sector.buttons
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    readonly property bool wideSystem: modelData.icon === "ps4_button_share" || modelData.icon === "ps4_button_options"
                    width: 42; height: 42
                    color: Theme.panel2
                    border.color: Theme.line
                    radius: Theme.radius
                    Accessible.role: Accessible.StaticText
                    Accessible.name: tile.modelData.label
                    Image {
                        objectName: "buttonIcon"
                        anchors.centerIn: parent
                        width: tile.wideSystem ? 34 : 30
                        height: tile.wideSystem ? 24 : 30
                        visible: tile.modelData.icon.length > 0
                        source: visible ? Qt.resolvedUrl("../../ui/assets/controller-icons/" + tile.modelData.icon + ".svg") : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: tile.modelData.icon.length === 0
                        text: tile.modelData.label
                        color: tile.modelData.color || Theme.text
                        font.pixelSize: 21; font.bold: true
                    }
                }
            }
        }
    }
}
