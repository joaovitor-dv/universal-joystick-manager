import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: win
    visible: true
    width: 1100
    height: 740
    minimumWidth: 780
    minimumHeight: 480
    title: "UJM - Universal Joystick Manager"
    color: Theme.window

    // the Basic style takes its colours from the palette: keep every part dark
    palette.window: Theme.window
    palette.windowText: Theme.text
    palette.base: Theme.panel
    palette.text: Theme.text
    palette.button: Theme.panel2
    palette.buttonText: Theme.text
    palette.highlight: Theme.selected
    palette.highlightedText: Theme.text

    menuBar: MenuBar {
        Menu {
            title: "File"
            MenuItem {
                text: "Update UJM…"
                onTriggered: Qt.openUrlExternally("https://github.com/joaovitor-dv/universal-joystick-manager/releases")
            }
        }
    }

    property string selectedId: ""

    header: Rectangle {
        height: 52
        color: Theme.panel
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        Text {
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: "UJM"
            color: Theme.accent; font.pixelSize: 20; font.bold: true
        }
        Text {
            anchors { left: parent.left; leftMargin: 70; verticalCenter: parent.verticalCenter }
            text: "Universal Joystick Manager"; color: Theme.muted; font.pixelSize: 14
        }
        StatusPill {
            id: sourcePill
            objectName: "sourcePill"
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            text: backend.sourceText
            dot: backend.sourceKind === "bridge" ? Theme.ok : (backend.sourceKind === "file" ? Theme.warn : Theme.danger)
        }
    }

    Connections {
        target: controllerModel
        function onModelReset() { win.selectedId = "" }
    }

    Row {
        anchors { fill: parent; margins: 12 }
        spacing: 12

        Rectangle {
            id: sidebar
            width: Math.max(265, Math.min(340, parent.width * 0.32))
            height: parent.height
            color: Theme.panel
            border.color: Theme.line
            border.width: 1

            Column {
                anchors { fill: parent; margins: 10 }
                spacing: 8
                Row {
                    width: parent.width
                    spacing: 10
                    Text { text: "Controllers"; color: Theme.text; font.pixelSize: 17; font.bold: true }
                    Text {
                        objectName: "countText"
                        anchors.baseline: parent.children[0].baseline
                        text: controllerModel.count === 1 ? "1 connected" : controllerModel.count + " connected"
                        color: Theme.muted; font.pixelSize: 12
                    }
                }
                Text {
                    objectName: "serviceText"
                    width: parent.width
                    text: backend.serviceText
                    visible: text.length > 0
                    color: backend.sourceKind === "none" ? Theme.warn : Theme.muted
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                ListView {
                    id: list
                    objectName: "controllerList"
                    width: parent.width
                    height: parent.height - y
                    clip: true
                    spacing: 6
                    model: controllerModel
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }
                    delegate: ControllerCard {
                        width: list.width - (list.ScrollBar.vertical.visible ? 12 : 0)
                        selected: win.selectedId === controllerId
                        onClicked: win.selectedId = controllerId
                        Component.onCompleted: if (index === 0 && win.selectedId === "") win.selectedId = controllerId
                    }
                    Text {
                        objectName: "emptyText"
                        anchors.centerIn: parent
                        visible: list.count === 0
                        horizontalAlignment: Text.AlignHCenter
                        text: backend.sourceKind === "none" ? "The UJM service is not running."
                                                            : "No controller connected.\nTurn one on or plug it in."
                        color: Theme.muted; font.pixelSize: 14
                    }
                }
            }
        }

        Item {
            id: detailPane
            width: parent.width - sidebar.width - parent.spacing
            height: parent.height
            Repeater {
                model: controllerModel
                delegate: Loader {
                    id: detailLoader
                    required property string controllerId
                    required property string displayName
                    required property string name
                    required property string family
                    required property string transportText
                    required property int player
                    required property bool hasBattery
                    required property int batteryPercent
                    required property string batteryStatus
                    required property string homeLed
                    required property bool ledManual
                    anchors.fill: parent
                    active: win.selectedId === controllerId
                    sourceComponent: ControllerDetail {
                        controllerId: detailLoader.controllerId
                        displayName: detailLoader.displayName
                        name: detailLoader.name
                        family: detailLoader.family
                        transportText: detailLoader.transportText
                        player: detailLoader.player
                        hasBattery: detailLoader.hasBattery
                        batteryPercent: detailLoader.batteryPercent
                        batteryStatus: detailLoader.batteryStatus
                        homeLed: detailLoader.homeLed
                        ledManual: detailLoader.ledManual
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: win.selectedId === "" && controllerModel.count > 0
                text: "Select a controller to see its diagram"
                color: Theme.muted; font.pixelSize: 14
            }
        }
    }
}
