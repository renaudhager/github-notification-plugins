import QtQuick
import Quickshell
import Quickshell.Io

// Data service for the GitHub notifications widget. The helper script owns
// authentication, pagination and rule matching; this item schedules it and
// exposes one defensive model to the bar icon and the panel.
Item {
  id: root

  property var settings: ({})

  property bool loading: false
  property bool ready: false
  property string state: "loading"     // loading | ok | error
  property string message: ""
  property string login: ""
  property string fetchedAt: ""
  property int counted: 0
  property int acked: 0
  property int ignored: 0
  property int ackedPending: 0
  property var notifications: []
  property var ackedItems: []
  property var errors: []
  property bool marking: false
  property string lastActionStatus: ""

  // Threads a click just marked done, hidden until the next successful fetch
  // reports them gone. Without this the row snaps back while the DELETE is
  // in flight and the bar stays lit for a whole refresh interval.
  property var hiddenIds: ({})
  property bool refreshQueued: false
  property string _stdout: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 300, 60, 3600)
  readonly property var rules: parsedRules()

  // Rows to show in the panel, minus anything the user just marked done.
  readonly property var visibleNotifications: notifications.filter(function(n) {
    return !hiddenIds[n.id]
  })
  readonly property int visibleCount: visibleNotifications.length

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  // The rules setting is a JSON array of {pattern, action}. Accepting it as
  // text keeps it editable from shell.json and from the settings form alike;
  // a bad edit degrades to "no rules" instead of a broken widget, but the
  // panel says so rather than silently counting everything.
  function parsedRules() {
    var raw = setting("rules", [])
    if (Array.isArray(raw)) return raw
    var text = String(raw || "").trim()
    if (text === "") return []
    try {
      var parsed = JSON.parse(text)
      return Array.isArray(parsed) ? parsed : []
    } catch (e) {
      return []
    }
  }

  readonly property bool rulesInvalid: {
    var raw = setting("rules", [])
    if (Array.isArray(raw)) return false
    var text = String(raw || "").trim()
    if (text === "") return false
    try {
      return !Array.isArray(JSON.parse(text))
    } catch (e) {
      return true
    }
  }

  function helperPath() {
    return decodeURIComponent(Qt.resolvedUrl("bin/github-notifications-fetch").toString()
      .replace(/^file:\/\//, ""))
  }

  function refresh() {
    if (fetch.running || mark.running) {
      refreshQueued = true
      return
    }
    refreshQueued = false
    loading = true
    _stdout = ""
    fetch.running = true
  }

  function markDone(id) {
    if (marking || id === undefined || id === null) return
    var next = {}
    for (var key in hiddenIds) next[key] = hiddenIds[key]
    next[String(id)] = true
    hiddenIds = next
    marking = true
    lastActionStatus = ""
    markId = String(id)
    mark.running = true
  }

  property string markId: ""

  // Called after every successful fetch: drop hidden ids the inbox no longer
  // reports, so a thread that comes back unread (new comment) shows up again.
  function reconcileHidden() {
    var present = {}
    var list = notifications.concat(ackedItems)
    for (var i = 0; i < list.length; i++) present[String(list[i].id)] = true
    var next = {}
    var changed = false
    for (var key in hiddenIds) {
      if (present[key]) next[key] = hiddenIds[key]
      else changed = true
    }
    if (changed) hiddenIds = next
  }

  function applyPayload(text) {
    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      state = "error"
      message = "The helper returned something that is not JSON."
      return
    }
    if (!data || data.ok !== true) {
      state = "error"
      message = String((data && data.error) || "Could not fetch GitHub notifications.")
      if (data && data.login) login = String(data.login)
      return
    }
    login = String(data.login || "")
    fetchedAt = String(data.fetchedAt || "")
    counted = Number(data.counted || 0)
    acked = Number(data.acked || 0)
    ignored = Number(data.ignored || 0)
    ackedPending = Number(data.ackedPending || 0)
    notifications = Array.isArray(data.notifications) ? data.notifications : []
    ackedItems = Array.isArray(data.ackedItems) ? data.ackedItems : []
    errors = Array.isArray(data.errors) ? data.errors : []
    state = "ok"
    message = ""
    ready = true
    reconcileHidden()
  }

  readonly property bool failing: state === "error"
  readonly property bool alarming: visibleCount > 0

  function openInBrowser(url) {
    if (!url) return
    Quickshell.execDetached(["xdg-open", String(url)])
  }

  function runHelperCommand(command) {
    Quickshell.execDetached(command)
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // A failed poll is retried sooner than the configured interval: an expired
  // token fixed a minute later should not wait five minutes to light the bar.
  Timer {
    interval: 60000
    running: root.state === "error"
    repeat: false
    onTriggered: root.refresh()
  }

  Process {
    id: fetch
    command: ["bash", root.helperPath(), "--config", JSON.stringify({ rules: root.rules })]
    stdout: StdioCollector {
      onStreamFinished: root._stdout = text
    }
    onExited: function(exitCode) {
      root.loading = false
      root.applyPayload(root._stdout)
      if (root.refreshQueued) root.refresh()
    }
  }

  Process {
    id: mark
    command: ["bash", root.helperPath(), "--mark-done", root.markId]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          root.lastActionStatus = data && data.ok ? "" : String((data && data.error) || "Could not mark it done.")
        } catch (e) {
          root.lastActionStatus = "Could not mark it done."
        }
      }
    }
    onExited: function(exitCode) {
      root.marking = false
      root.refresh()
    }
  }
}
