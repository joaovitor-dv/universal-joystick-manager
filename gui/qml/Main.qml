import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: win
    visible: true
    width: 960
    height: 640
    minimumWidth: 560
    minimumHeight: 360
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

    Column {
        anchors { fill: parent; margins: 16 }
        spacing: 8

        Row {
            width: parent.width
            spacing: 12
            Text { text: "Controllers"; color: Theme.text; font.pixelSize: 18; font.bold: true }
            Text {
                objectName: "countText"
                anchors.baseline: parent.children[0].baseline
                text: controllerModel.count === 1 ? "1 connected" : controllerModel.count + " connected"
                color: Theme.muted; font.pixelSize: 14
            }
        }
        Text {
            objectName: "serviceText"
            width: parent.width
            text: backend.serviceText
            visible: text.length > 0
            color: backend.sourceKind === "none" ? Theme.warn : Theme.muted
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        ListView {
            id: list
            objectName: "controllerList"
            width: parent.width
            height: parent.height - y
            clip: true
            spacing: 4
            model: controllerModel
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }
            delegate: ControllerCard {
                width: list.width - (list.ScrollBar.vertical.visible ? 12 : 0)
                selected: win.selectedId === controllerId
                onClicked: win.selectedId = controllerId
            }

            Text {
                objectName: "emptyText"
                anchors.centerIn: parent
                visible: list.count === 0
                horizontalAlignment: Text.AlignHCenter
                text: backend.sourceKind === "none" ? "The UJM service is not running."
                                                    : "No controller connected.\nTurn one on or plug it in."
                color: Theme.muted; font.pixelSize: 15
            }
        }
    }
}
