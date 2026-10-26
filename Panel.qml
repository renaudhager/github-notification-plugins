import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The setting key the helper reads must match Service.parsedRules(); both
// live in this plugin and change together.
Panel {
  id: root
  moduleName: "renaudhager.github-notifications"
  ipcTarget: "renaudhager.github-notifications"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool cursorActive: false
  property int cursorIndex: 0
  property bool ackedExpanded: false

  readonly property var rows: service.visibleNotifications

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function clampCursor() {
    cursorIndex = rows.length === 0 ? 0 : clamp(cursorIndex, 0, rows.length - 1)
  }

  function clearStatus() { service.lastActionStatus = "" }

  function openSelected() {
    var row = rows[cursorIndex]
    if (!row) return
    service.openInBrowser(row.url)
    root.close()
  }

  function markSelectedDone() {
    var row = rows[cursorIndex]
    if (!row) return
    clearStatus()
    service.markDone(row.id)
    clampCursor()
  }

  function openInbox() {
    service.openInBrowser("https://github.com/notifications")
    root.close()
  }

  function countLabel(n) {
    return n > 999 ? "999+" : String(n)
  }

  function tooltipText() {
    if (service.state === "loading" && !service.ready) return "GitHub notifications: loading"
    if (service.failing) return "GitHub notifications: " + service.message
    var text = service.visibleCount === 0
      ? "GitHub notifications: nothing unread"
      : service.visibleCount + " unread"
    if (service.acked + service.ignored > 0)
      text += " · " + (service.acked + service.ignored) + " hidden by rules"
    return text
  }

  function relativeTime(iso) {
    var then = new Date(String(iso || "")).getTime()
    if (!isFinite(then)) return ""
    var minutes = Math.floor((Date.now() - then) / 60000)
    if (minutes < 1) return "now"
    if (minutes < 60) return minutes + "m"
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h"
    var days = Math.floor(hours / 24)
    if (days < 30) return days + "d"
    return Math.floor(days / 30) + "mo"
  }

  // Reason tokens read better as verbs; anything unrecognised falls back to
  // the raw token so a new GitHub reason is still legible.
  function reasonLabel(reason) {
    var table = {
      "review_requested": "review requested",
      "assign": "assigned",
      "author": "you authored",
      "comment": "commented",
      "ci_activity": "CI activity",
      "invitation": "invitation",
      "manual": "manual",
      "mention": "mentioned",
      "security_alert": "security alert",
      "state_change": "state changed",
      "subscribed": "subscribed",
      "team_mention": "team mentioned"
    }
    return table[reason] || String(reason || "")
  }

  function typeLabel(type) {
    var table = {
      "PullRequest": "PR",
      "Issue": "Issue",
      "Discussion": "Discussion",
      "Release": "Release",
      "Commit": "Commit",
      "CheckSuite": "Checks",
      "RepositoryVulnerabilityAlert": "Security"
    }
    return table[type] || "Thread"
  }

  // Stay visible on error: the "!" badge and the panel message are how a
  // broken token or helper gets noticed at all.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onRowsChanged: clampCursor()

  onOpenedChanged: {
    if (!opened) return
    cursorActive = false
    clampCursor()
    service.refresh()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  Service {
    id: service
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { service.refresh(); return "ok" }
  }

  // ---------------------------------------------------------------- bar icon
  //
  // The count sits in the bar next to the bell, the way the clock carries its
  // own text: a glyph alone would leave the user clicking to learn the number.
  readonly property int fontSize: Style.font.bodySmall
  // Estimated from the digit count: the bar needs the slot width before the
  // inner Text has ever been laid out, so measuring it here would recurse.
  readonly property int badgeSlot: {
    var text = countLabel(service.visibleCount)
    return Math.ceil(text.length * fontSize * 0.62) + Style.space(6)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontFamily: root.fontFamily
    active: service.alarming
    tooltipText: root.tooltipText()
    fixedWidth: vertical ? Style.bar.iconSlot : Style.bar.iconSlot + badgeSlot
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openInbox()
      else root.toggle()
    }
    onWheelMoved: function(delta) { if (delta > 0) service.refresh() }

    iconComponent: Component {
      // The button sizes this to its square icon canvas. The row is centred on
      // it and overflows both sides evenly into the badgeSlot extra width.
      Item {
        id: badgeCanvas

        Row {
          id: badgeRow
          anchors.centerIn: parent
          spacing: Style.space(3)

          // OpticalGlyph has no implicit size; give it the icon canvas.
          OpticalGlyph {
            id: bell
            width: Style.bar.iconCanvas
            height: Style.bar.iconCanvas
            text: "󰊤"
            fontFamily: root.fontFamily
            fontSize: Style.bar.iconFont
            color: button.active && button.useActiveColor ? button.activeColor : button.foreground
          }

          Text {
            id: badgeText
            anchors.verticalCenter: parent.verticalCenter
            text: root.countLabel(service.visibleCount)
            color: button.active ? button.activeColor : button.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
          }
        }

        Text {
          visible: service.failing
          anchors.top: badgeRow.top
          anchors.right: badgeRow.right
          text: "!"
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
  }

  // ---------------------------------------------------------------- popup
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy === 0) return
        if (root.rows.length === 0) return
        root.cursorActive = true
        var next = root.clamp(root.cursorIndex + dy, 0, root.rows.length - 1)
        root.cursorIndex = next
        var row = rowRepeater.itemAt(next)
        if (row && panelFlick) {
          var top = row.y
          var bottom = row.y + row.height
          if (top < panelFlick.contentY) panelFlick.contentY = top
          else if (bottom > panelFlick.contentY + panelFlick.height)
            panelFlick.contentY = bottom - panelFlick.height
        }
      }
      onActivateRequested: root.openSelected()
      onCloseRequested: root.close()
      onDeleteRequested: root.markSelectedDone()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") service.refresh()
        else if (t === "a" || t === "A") root.openInbox()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          // ---------- Header: count, account ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroTitle.implicitHeight, heroMeta.implicitHeight)

            Text {
              id: heroTitle
              textFormat: Text.PlainText
              text: service.visibleCount === 1 ? "1 unread notification"
                : service.visibleCount + " unread notifications"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodyLarge !== undefined ? Style.font.bodyLarge : Style.font.body
              font.bold: true
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            PanelActionButton {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.foreground
              tooltipText: "Refresh (r)"
              iconText: "󰑐"
              focusable: false
              enabled: !service.loading
              onClicked: service.refresh()
            }

            Text {
              id: heroMeta
              textFormat: Text.PlainText
              // Sits left of the refresh button so a long login cannot run
              // under it.
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (service.login === "") return ""
                var when = root.relativeTime(service.fetchedAt)
                return "@" + service.login + (when === "" ? "" : " · " + when)
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideLeft
              width: Math.max(0, Math.min(implicitWidth, parent.width - 120))
            }
          }

          // ---------- Problems ----------
          BorderSurface {
            visible: service.failing || service.rulesInvalid
            width: parent.width
            implicitHeight: problemText.implicitHeight + Style.spacing.xl * 2
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
            borderSpec: Border.flat(Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: problemText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: service.rulesInvalid
                ? "The rules setting is not a JSON list, so no rules are applied. Fix it in the plugin settings."
                : service.message
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Text {
            visible: service.lastActionStatus !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: service.lastActionStatus
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // ---------- Empty state ----------
          Text {
            visible: !service.failing && service.ready && root.rows.length === 0
            width: parent.width
            topPadding: Style.space(16)
            bottomPadding: Style.space(8)
            textFormat: Text.PlainText
            text: service.acked + service.ignored > 0
              ? "Inbox clear. " + (service.acked + service.ignored) + " notification"
                + (service.acked + service.ignored === 1 ? " is" : "s are") + " hidden by your rules."
              : "Inbox clear."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Notification rows ----------
          Column {
            id: rowList
            width: parent.width
            spacing: Style.spacing.xxs

            Repeater {
              id: rowRepeater
              model: root.rows

              delegate: CursorSurface {
                id: rowItem
                required property var modelData
                required property int index

                width: rowList.width
                implicitHeight: rowContent.implicitHeight + Style.space(12)
                hasCursor: root.cursorActive && index === root.cursorIndex
                foreground: root.foreground

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                  onEntered: {
                    root.cursorActive = true
                    root.cursorIndex = rowItem.index
                  }
                  onClicked: function(mouse) {
                    root.cursorIndex = rowItem.index
                    if (mouse.button === Qt.MiddleButton) root.markSelectedDone()
                    else root.openSelected()
                  }
                }

                Column {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: actionsRow.left
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  spacing: Style.spacing.xxs

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: String(rowItem.modelData.title || "(no title)")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: [
                      String(rowItem.modelData.repo || ""),
                      root.typeLabel(rowItem.modelData.type),
                      root.reasonLabel(rowItem.modelData.reason)
                    ].filter(function(part) { return part !== "" }).join(" · ")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Row {
                  id: actionsRow
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  // Hidden until the row is the cursor: a wall of X buttons
                  // would fight the titles for attention.
                  readonly property bool revealed: root.cursorActive && rowItem.index === root.cursorIndex

                  PanelActionButton {
                    visible: actionsRow.revealed
                    foreground: root.foreground
                    hoverColor: root.urgent
                    tooltipText: "Mark done (x)"
                    iconText: "󰄬"
                    enabled: !service.marking
                    onClicked: {
                      root.cursorIndex = rowItem.index
                      root.markSelectedDone()
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    visible: rowItem.index === root.cursorIndex || !actionsRow.revealed
                    text: root.relativeTime(rowItem.modelData.updatedAt)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // ---------- Hidden by rules ----------
          PanelSeparator {
            visible: service.acked + service.ignored > 0
            foreground: root.foreground
          }

          Item {
            visible: service.acked + service.ignored > 0
            width: parent.width
            implicitHeight: hiddenLabel.implicitHeight

            Text {
              id: hiddenLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: {
                var parts = []
                if (service.acked > 0) parts.push(service.acked + " acked")
                if (service.ignored > 0) parts.push(service.ignored + " ignored")
                return "Hidden by your rules · " + parts.join(" · ")
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.ackedExpanded ? "hide" : "show"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.ackedExpanded = !root.ackedExpanded
            }
          }

          Column {
            visible: root.ackedExpanded
            width: parent.width
            spacing: Style.spacing.xxs

            Repeater {
              model: service.ackedItems

              delegate: Item {
                id: hiddenRow
                required property var modelData
                width: parent.width
                implicitHeight: hiddenContent.implicitHeight + Style.space(8)

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    service.openInBrowser(hiddenRow.modelData.url)
                    root.close()
                  }
                }

                Column {
                  id: hiddenContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  spacing: 0

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: String(hiddenRow.modelData.title || "(no title)")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: [
                      String(hiddenRow.modelData.repo || ""),
                      root.typeLabel(hiddenRow.modelData.type),
                      root.reasonLabel(hiddenRow.modelData.reason)
                    ].filter(function(part) { return part !== "" }).join(" · ")
                    color: Qt.darker(root.dim, 1.2)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }

          // ---------- Footer hints ----------
          Text {
            width: parent.width
            textFormat: Text.PlainText
            topPadding: Style.space(4)
            text: service.visibleCount > 0
              ? "Enter opens the thread · x marks done · r refreshes · a opens the inbox"
              : "r refreshes · a opens the inbox · right-click the icon for the inbox"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
