import QtQuick

// A small rounded label with a coloured dot.
Rectangle {
    id: pill
    property string text: ""
    property color dot: Theme.ok
    implicitHeight: 24
    implicitWidth: label.implicitWidth + 36
    radius: 12
    color: Theme.panel2
    border.color: Theme.line
    Row {
        anchors.centerIn: parent
        spacing: 7
        Rectangle { width: 9; height: 9; radius: 4.5; color: pill.dot; anchors.verticalCenter: parent.verticalCenter }
        Text { id: label; text: pill.text; color: Theme.text; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: text
}
