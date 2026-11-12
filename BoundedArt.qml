import QtQuick
import Quickshell.Io

Item {
  id: root
  property string url: ""
  property string dataUrl: ""
  property string pending: ""
  property string requested: ""
  property string output: ""
  property bool cancelled: false

  function reload() {
    dataUrl = ""
    pending = url
    if (worker.running) {
      cancelled = true
      worker.signal(15)
      killLater.restart()
    } else startPending()
  }
  function startPending() {
    if (worker.running || pending === "") return
    requested = pending
    pending = ""
    if (requested.length > 4096) return
    cancelled = false
    output = ""
    worker.command = ["/usr/bin/python3", "-B", decodeURIComponent(Qt.resolvedUrl("artwork.py").toString().replace(/^(file|qs):\/\//, "")), requested]
    worker.running = true
    watchdog.restart()
  }
  onUrlChanged: reload()

  Process {
    id: worker
    // The producer emits at most 2 MiB of artwork encoded as base64, no logs.
    stdout: StdioCollector { onStreamFinished: root.output = text }
    onExited: function(code, status) {
      watchdog.stop()
      killLater.stop()
      if (!root.cancelled && code === 0 && status === 0 && root.requested === root.url
          && root.output.length <= 2796230 && /^data:image\/(png|jpeg);base64,[A-Za-z0-9+/]*={0,2}$/.test(root.output))
        root.dataUrl = root.output
      root.output = ""
      Qt.callLater(root.startPending)
    }
  }
  // Independent wall-clock limit also covers DNS/native calls that might not
  // promptly return to Python's signal handler. No child processes/temp files.
  Timer { id: watchdog; interval: 6000; onTriggered: { root.cancelled = true; worker.signal(9) } }
  Timer { id: killLater; interval: 100; onTriggered: worker.signal(9) }
  Component.onDestruction: worker.signal(9)
}
