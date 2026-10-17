pragma Singleton
import QtQuick

// Dark only, by design (same palette as the HTML prototype, ui/index.html).
QtObject {
    readonly property color desktop: "#020402"
    readonly property color window: "#050805"
    readonly property color panel: "#080d09"
    readonly property color panel2: "#0b110c"
    readonly property color line: "#294331"
    readonly property color text: "#e3f6e5"
    readonly property color muted: "#91a794"
    readonly property color accent: "#9cff88"
    readonly property color ok: "#71f08e"
    readonly property color warn: "#edc56b"
    readonly property color danger: "#e5534b"
    readonly property color selected: "#102117"
    readonly property color selectedLine: "#65bd73"
    readonly property color ledOff: "#26372a"
    readonly property color ledOffLine: "#52735a"
    readonly property color ledOn: "#2670c2"
    readonly property color ledOnLine: "#174a83"
    readonly property int radius: 2
    readonly property int pad: 12
}
