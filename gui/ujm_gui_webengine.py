#!/usr/bin/env python3
"""UJM interface shell: PySide6 + QtWebEngine around ui/index.html (prototype for measuring).

The page cannot read /run/joystickmanager/state.json by itself, so the shell watches the file
and hands it to the page through a QWebChannel object named "ujm". The page may ignore it.
"""
import json
import os
import sys
import time
from pathlib import Path

from PySide6.QtCore import QFileSystemWatcher, QObject, Property, QTimer, QUrl, Signal, Slot
from PySide6.QtWebChannel import QWebChannel
from PySide6.QtWebEngineCore import QWebEnginePage
from PySide6.QtWebEngineWidgets import QWebEngineView
from PySide6.QtWidgets import QApplication

STATE = Path(os.environ.get("JOYMANAGER_RUNTIME_DIR", "/run/joystickmanager")) / "state.json"
PAGE = Path(__file__).resolve().parent.parent / "ui" / "index.html"


class StateBridge(QObject):
    """Exposes the service snapshot to the page; re-reads it when the file is replaced."""

    changed = Signal(str)

    def __init__(self):
        super().__init__()
        self._text = ""
        self._watcher = QFileSystemWatcher(self)
        # the service replaces the file (rename), so the directory is watched too
        self._watcher.directoryChanged.connect(self._reload)
        self._watcher.fileChanged.connect(self._reload)
        self._watch()
        self._reload()

    def _watch(self):
        d, f = str(STATE.parent), str(STATE)
        if os.path.isdir(d) and d not in self._watcher.directories():
            self._watcher.addPath(d)
        if os.path.exists(f) and f not in self._watcher.files():
            self._watcher.addPath(f)

    @Slot()
    def _reload(self, *_):
        self._watch()
        try:
            text = STATE.read_text(encoding="utf-8")
            json.loads(text)
        except (OSError, ValueError):
            text = ""
        if text != self._text:
            self._text = text
            self.changed.emit(text)

    @Property(str, notify=changed)
    def state(self):
        return self._text


def main():
    t0 = time.monotonic()
    app = QApplication(sys.argv)
    app.setApplicationName("ujm-gui-prototype")
    view = QWebEngineView()
    view.resize(1280, 800)
    bridge = StateBridge()
    channel = QWebChannel()
    channel.registerObject("ujm", bridge)
    view.page().setWebChannel(channel)

    def loaded(ok):
        print(f"READY ok={ok} ms={(time.monotonic() - t0) * 1000:.0f}", flush=True)
        if os.environ.get("UJM_EXIT_AFTER_LOAD"):
            QTimer.singleShot(0, app.quit)

    view.loadFinished.connect(loaded)
    view.load(QUrl.fromLocalFile(str(PAGE)))
    view.setWindowTitle("UJM - Universal Joystick Manager (prototype)")
    view.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
