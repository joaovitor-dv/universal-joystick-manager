import QtQuick
import QtQuick.Controls
import "ControllerVisuals.js" as Visuals

Rectangle {
    id: detail
    objectName: "controllerDetail"
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
    readonly property string visualType: Visuals.kind(family, name)
    readonly property var lightPreview: Visuals.playerLights(visualType, player)
    readonly property var buttonGroups: Visuals.groups(visualType)
    readonly property var faceOverlays: Visuals.faceOverlays(visualType)
    color: Theme.panel
    border.color: Theme.line
    border.width: 1
    radius: Theme.radius

    Flickable {
        id: scroll
        anchors.fill: parent
        anchors.margins: 1
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight + 28
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }

        Column {
            id: body
            x: 14; y: 14
            width: scroll.width - 28
            spacing: 12

            Row {
                width: parent.width
                spacing: 10
                Rectangle {
                    width: 36; height: 36; radius: Theme.radius
                    color: Theme.selected; border.color: Theme.selectedLine
                    Text { anchors.centerIn: parent; text: detail.player; color: Theme.accent; font.bold: true; font.pixelSize: 18 }
                }
                Column {
                    width: parent.width - 46
                    spacing: 3
                    Text {
                        objectName: "detailTitle"
                        width: parent.width
                        text: detail.displayName
                        color: Theme.text; font.pixelSize: 18; font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: detail.transportText + (detail.hasBattery ? "  ·  " + detail.batteryPercent + "% " + detail.batteryStatus : "")
                        color: Theme.muted; font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 8
                visible: detail.homeLed === "on" || detail.homeLed === "off" || detail.ledManual
                StatusPill {
                    id: homeStatus
                    objectName: "homeLedPill"
                    visible: detail.homeLed === "on" || detail.homeLed === "off"
                    text: detail.homeLed === "on" ? "HOME LED on" : "HOME LED off"
                    dot: detail.homeLed === "on" ? Theme.ok : Theme.muted
                }
                StatusPill {
                    id: manualStatus
                    objectName: "manualLedPill"
                    visible: detail.ledManual
                    text: "Player LEDs · manual"
                    dot: Theme.warn
                }
            }

            Row {
                width: parent.width
                spacing: 8
                visible: detail.lightPreview.kind !== "none"
                Rectangle {
                    visible: detail.lightPreview.kind === "color"
                    width: 16; height: 16; radius: 8
                    color: detail.lightPreview.color
                    border.color: Theme.text
                }
                Repeater {
                    model: detail.lightPreview.kind === "indicator" ? 5 : (detail.lightPreview.kind === "ring" ? 4 : 0)
                    Rectangle {
                        required property int index
                        width: 10; height: 14; radius: detail.lightPreview.kind === "ring" ? 5 : 2
                        color: detail.lightPreview.mask & (1 << index) ? Theme.text : "transparent"
                        border.color: Theme.muted
                    }
                }
                Text {
                    objectName: "playerLightPreview"
                    text: detail.lightPreview.text + " · not live"
                    color: Theme.muted; font.pixelSize: 12
                    width: parent.width - x
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                id: artFrame
                objectName: "diagramFrame"
                width: parent.width
                height: Math.max(210, Math.min(330, width * 0.57))
                color: Theme.desktop
                border.color: Theme.line
                border.width: 1
                Image {
                    id: art
                    objectName: "controllerArtwork"
                    anchors { fill: parent; margins: 12 }
                    source: detail.visualType !== "unknown" ? Qt.resolvedUrl(Visuals.artwork(detail.visualType)) : ""
                    sourceSize.width: 1200
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "Diagram of " + detail.displayName
                }
                Repeater {
                    model: detail.faceOverlays
                    delegate: Item {
                        id: face
                        required property var modelData
                        width: Math.max(20, Math.min(42, art.paintedWidth * 0.068))
                        height: width
                        x: art.x + (art.width - art.paintedWidth) / 2 + art.paintedWidth * modelData.x / 100 - width / 2
                        y: art.y + (art.height - art.paintedHeight) / 2 + art.paintedHeight * modelData.y / 100 - height / 2
                        Rectangle {
                            anchors.fill: parent
                            visible: face.modelData.icon.length === 0
                            radius: width / 2
                            color: face.modelData.color
                            border.color: "#f1f7f1"; border.width: 2
                            Text {
                                anchors.centerIn: parent
                                text: face.modelData.label
                                color: "white"; font.bold: true
                                font.pixelSize: Math.max(12, face.width * 0.48)
                            }
                        }
                        Image {
                            objectName: "faceOverlayIcon"
                            anchors.fill: parent
                            visible: face.modelData.icon.length > 0
                            source: visible ? Qt.resolvedUrl("../../ui/assets/controller-icons/" + face.modelData.icon + ".svg") : ""
                            fillMode: Image.PreserveAspectFit
                        }
                    }
                }
                Rectangle {
                    id: seriesShare
                    objectName: "xboxSeriesShare"
                    visible: detail.visualType === "xboxseries" && art.status === Image.Ready
                    width: 28; height: 20; radius: 3
                    x: art.x + (art.width - art.paintedWidth) / 2 + art.paintedWidth * 0.5 - width / 2
                    y: art.y + (art.height - art.paintedHeight) / 2 + art.paintedHeight * (255 / 703) - height / 2
                    color: "transparent"
                    border.color: "#e7f0f7"
                    border.width: 2
                    Text {
                        anchors.centerIn: parent
                        text: "⇧"
                        color: "#e7f0f7"
                        font.bold: true
                        font.pixelSize: 16
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Share button (visual reference)"
                }
                Text {
                    anchors.centerIn: parent
                    visible: detail.visualType === "unknown" || art.status === Image.Error
                    text: "Diagram not available for this controller"
                    color: Theme.muted; font.pixelSize: 13
                }
            }

            Text {
                width: parent.width
                text: "Controller diagram · visual reference, no live input overlay"
                color: Theme.muted; font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
            }

            Text { text: "Buttons and triggers"; color: Theme.text; font.pixelSize: 15; font.bold: true }
            Text {
                width: parent.width
                text: "Available controls for this model · input monitoring is not connected yet"
                color: Theme.muted; font.pixelSize: 12; wrapMode: Text.WordWrap
            }

            Grid {
                id: sectors
                width: parent.width
                columns: width >= 540 ? 2 : 1
                spacing: 8
                Repeater {
                    model: detail.buttonGroups
                    delegate: ButtonSector {
                        required property var modelData
                        width: (sectors.width - (sectors.columns - 1) * sectors.spacing) / sectors.columns
                        title: modelData.title
                        buttons: modelData.buttons
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: info.implicitHeight + 20
                color: Theme.panel2; border.color: Theme.line
                Text {
                    id: info
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    text: "Live sticks, trigger travel, motion data and pressed-state highlights will appear after the service exposes input telemetry."
                    wrapMode: Text.WordWrap
                    color: Theme.muted; font.pixelSize: 12
                }
            }
        }
    }
}
