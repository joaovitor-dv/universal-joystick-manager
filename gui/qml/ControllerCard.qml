import QtQuick

// One connected controller. Read-only: the data comes from the service through the bridge.
Rectangle {
    id: card
    required property int index
    required property string controllerId
    required property string displayName
    required property string name
    required property string alias
    required property string vendor
    required property string transportText
    required property string address
    required property int player
    required property bool hasBattery
    required property int batteryPercent
    required property string batteryStatus
    required property string batteryLevel
    required property int ledMask
    property bool selected: false
    signal clicked()

    implicitHeight: 82
    radius: Theme.radius
    color: selected ? Theme.selected : Theme.panel
    border.color: selected ? Theme.selectedLine : Theme.line
    border.width: 1

    readonly property string subtitle: [vendor, transportText].filter(function (s) { return s.length > 0 }).join(" · ")
    readonly property color batteryColor: batteryStatus === "Charging" ? Theme.ok
        : (batteryLevel === "critical" ? Theme.danger : (batteryLevel === "low" ? Theme.warn : Theme.text))

    Accessible.role: Accessible.ListItem
    Accessible.name: "Player " + player + ", " + displayName + ", " + subtitle
        + (hasBattery ? ", battery " + batteryPercent + " percent " + batteryStatus : "")

    MouseArea { anchors.fill: parent; onClicked: card.clicked(); cursorShape: Qt.PointingHandCursor }

    Rectangle {
        id: playerBadge
        anchors { left: parent.left; top: parent.top; margins: 10 }
        width: 34; height: 34; radius: Theme.radius
        color: Theme.panel2; border.color: Theme.line
        Text { anchors.centerIn: parent; text: card.player > 0 ? card.player : "–"; color: Theme.accent; font.pixelSize: 18; font.bold: true }
    }
    Column {
        anchors { left: playerBadge.right; leftMargin: 10; right: parent.right; rightMargin: 10; top: parent.top; topMargin: 10 }
        spacing: 2
        Text { width: parent.width; text: card.displayName; color: Theme.text; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight }
        Text {
            width: parent.width
            text: card.alias.length > 0 ? card.name + " · " + card.subtitle : card.subtitle
            color: Theme.muted; font.pixelSize: 12; elide: Text.ElideRight
        }
    }
    Text {
        anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 9 }
        width: card.width - 88
        text: card.hasBattery ? card.batteryPercent + "%" + (card.batteryStatus.length > 0 ? " · " + card.batteryStatus : "") : "Battery unavailable"
        color: card.hasBattery ? card.batteryColor : Theme.muted
        font.pixelSize: 11; elide: Text.ElideRight
    }
    Row {
        anchors { right: parent.right; rightMargin: 10; bottom: parent.bottom; bottomMargin: 12 }
        spacing: 5
        Repeater {
            model: 4
            Rectangle {
                required property int index
                readonly property bool on: (card.ledMask & (1 << index)) !== 0
                width: 9; height: 9; radius: 4.5
                color: on ? Theme.ledOn : Theme.ledOff
                border.color: on ? Theme.ledOnLine : Theme.ledOffLine
                objectName: "led" + index + (on ? "on" : "off")
            }
        }
    }
}
