#!/usr/bin/env python3
"""Smallest useful Qt Quick window: the floor a native QML interface could reach (for measuring)."""
import sys
import time

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

QML = b"""
import QtQuick
import QtQuick.Controls
ApplicationWindow {
    visible: true; width: 1280; height: 800; title: "UJM (QML baseline)"; color: "#14161a"
    Column { anchors.centerIn: parent; spacing: 12
        Repeater { model: 4
            Rectangle { width: 420; height: 64; radius: 8; color: "#22262d"
                Text { anchors.centerIn: parent; color: "#e6e8ec"; text: "Player " + (index + 1) + "  -  Pro Controller  -  87%" } } } }
}
"""

t0 = time.monotonic()
app = QGuiApplication(sys.argv)
# the default (platform) style stalled in the test environment; Basic is also the lightest
QQuickStyle.setStyle("Basic")
engine = QQmlApplicationEngine()
engine.loadData(QML, QUrl("baseline.qml"))
print(f"READY ok={bool(engine.rootObjects())} ms={(time.monotonic() - t0) * 1000:.0f}", flush=True)
sys.exit(app.exec())
