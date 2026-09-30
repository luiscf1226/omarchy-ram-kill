import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// RAM bar widget. Click opens a panel listing every Claude session on its own
// row (tick several and kill them together) plus the biggest apps. Every kill
// button asks once: first click arms it, second click kills.
Panel {
  id: root
  moduleName: "io.github.luiscf1226.ram-kill"
  ipcTarget: "io.github.luiscf1226.ram-kill"

  property real used: 0
  property real total: 0
  property var sessions: []
  property var apps: []
  property var selected: ({})      // pid -> true
  property string armed: ""        // key of the kill button waiting for confirmation
  readonly property real ratio: root.total > 0 ? root.used / root.total : 0
  // The helper script ships next to this file.
  readonly property string ramKill: String(Qt.resolvedUrl("ram-kill")).replace("file://", "")
  readonly property var selectedPids: root.sessions.filter(function(s) { return root.selected[s.pid] }).map(function(s) { return s.pid })
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color danger: root.bar ? root.bar.urgent : Color.urgent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (root.opened) { if (!jsonProc.running) jsonProc.running = true }
    else if (!statusProc.running) statusProc.running = true
  }

  function mb(v) { return v >= 1024 ? (v / 1024).toFixed(1) + " GB" : v + " MB" }

  function toggleSelected(pid) {
    var next = Object.assign({}, root.selected)
    if (next[pid]) delete next[pid]
    else next[pid] = true
    root.selected = next
  }

  // First click arms, second click (within 3s) runs the kill.
  function confirmKill(key, pids) {
    if (root.armed !== key) {
      root.armed = key
      disarmTimer.restart()
      return
    }
    root.armed = ""
    if (!pids || pids.length === 0) return
    killProc.command = ["python3", root.ramKill, "kill"].concat(pids.map(String))
    killProc.running = true
  }

  onOpenedChanged: {
    root.armed = ""
    if (opened) { root.selected = ({}); refresh() }
  }

  Component.onCompleted: refresh()

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍛 " + root.used.toFixed(1) + "G"
    fontSize: Style.font.caption
    active: root.ratio >= 0.85
    tooltipText: root.opened ? "" : "RAM: " + root.used.toFixed(1) + " / " + root.total.toFixed(1) + " GB ("
      + Math.round(root.ratio * 100) + "%)\nClick: processes & Claude sessions"
    onPressed: function(b) { root.toggle() }
  }

  Timer {
    interval: root.opened ? 2500 : 3000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer { id: disarmTimer; interval: 3000; onTriggered: root.armed = "" }

  Process {
    id: statusProc
    command: ["python3", root.ramKill, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split(" ")
        root.used = parseFloat(parts[0]) || 0
        root.total = parseFloat(parts[1]) || 0
      }
    }
  }

  Process {
    id: jsonProc
    command: ["python3", root.ramKill, "json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text || ""))
          root.used = d.used
          root.total = d.total
          root.sessions = d.claude || []
          root.apps = d.apps || []
          // Drop selections for sessions that are gone.
          var next = {}
          root.sessions.forEach(function(s) { if (root.selected[s.pid]) next[s.pid] = true })
          root.selected = next
        } catch (e) {}
      }
    }
  }

  Process {
    id: killProc
    onExited: { if (!jsonProc.running) jsonProc.running = true }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: memory used ----------
        Item {
          width: parent.width
          implicitHeight: heroTitle.implicitHeight

          Text {
            id: heroTitle
            text: "󰍛  Memory"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.used.toFixed(1) + " / " + root.total.toFixed(1) + " GB  ·  " + Math.round(root.ratio * 100) + "%"
            color: root.ratio >= 0.85 ? root.danger : root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: track
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
          }
          Rectangle {
            height: track.height
            radius: track.radius
            width: Math.max(track.height, track.width * root.ratio)
            color: root.ratio >= 0.85 ? root.danger : root.fg
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Claude sessions ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(claudeHeader.implicitHeight, bulkRow.implicitHeight)

          PanelSectionHeader {
            id: claudeHeader
            anchors.verticalCenter: parent.verticalCenter
            text: "CLAUDE SESSIONS · " + root.sessions.length
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Row {
            id: bulkRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              visible: root.selectedPids.length > 0
              text: root.armed === "selected" ? "Confirm?" : "Kill " + root.selectedPids.length + " selected"
              fontSize: Style.font.caption
              fontFamily: root.fontFamily
              foreground: root.armed === "selected" ? root.danger : root.fg
              bordered: true
              onClicked: root.confirmKill("selected", root.selectedPids)
            }

            Button {
              visible: root.sessions.length > 1
              text: root.armed === "all" ? "Confirm?" : "Kill all"
              fontSize: Style.font.caption
              fontFamily: root.fontFamily
              foreground: root.armed === "all" ? root.danger : root.fg
              bordered: true
              onClicked: root.confirmKill("all", root.sessions.map(function(s) { return s.pid }))
            }
          }
        }

        Text {
          visible: root.sessions.length === 0
          text: "No Claude sessions running"
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Column {
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.sessions

            ProcRow {
              required property var modelData
              width: parent.width
              checkable: true
              checked: !!root.selected[modelData.pid]
              icon: "󰚩"
              title: modelData.project
              subtitle: modelData.cwd + "  ·  " + (String(modelData.where).indexOf("pts/") === 0 ? "terminal " + modelData.where : modelData.where) + "  ·  " + modelData.age
              amount: root.mb(modelData.mb)
              killKey: "c" + modelData.pid
              pids: [modelData.pid]
              onToggled: root.toggleSelected(modelData.pid)
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Top apps ----------
        PanelSectionHeader {
          text: "TOP APPS"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.apps

            ProcRow {
              required property var modelData
              width: parent.width
              icon: "󰣆"
              title: modelData.name
              subtitle: modelData.count + (modelData.count === 1 ? " process" : " processes")
              amount: root.mb(modelData.mb)
              killKey: "a" + modelData.name
              pids: modelData.pids
            }
          }
        }

        Text {
          width: parent.width
          text: "Kill asks twice: click, then Confirm.  Esc closes."
          color: Qt.darker(root.fg, 1.8)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  // One process row: [checkbox] icon · title / subtitle · memory · kill.
  component ProcRow: Rectangle {
    id: row
    property bool checkable: false
    property bool checked: false
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string amount: ""
    property string killKey: ""
    property var pids: []
    readonly property bool isArmed: root.armed === killKey
    signal toggled()

    implicitHeight: Math.max(Style.space(44), texts.implicitHeight + Style.space(12))
    radius: Style.cornerRadius
    color: isArmed ? Qt.rgba(root.danger.r, root.danger.g, root.danger.b, 0.15)
      : (checked ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
      : (rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : "transparent"))

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.checkable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (row.checkable) row.toggled()
    }

    Text {
      id: lead
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: row.checkable ? (row.checked ? "󰄵" : "󰄱") : row.icon
      color: row.checked ? Color.accent : root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
    }

    Column {
      id: texts
      anchors.left: lead.right
      anchors.leftMargin: Style.space(10)
      anchors.right: amountText.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: row.title
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        width: parent.width
        text: row.subtitle
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        color: Qt.darker(root.fg, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      id: amountText
      anchors.right: killButton.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: row.amount
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Button {
      id: killButton
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: row.isArmed ? "Confirm?" : "Kill"
      fontSize: Style.font.caption
      fontFamily: root.fontFamily
      foreground: row.isArmed ? root.danger : root.fg
      bordered: true
      onClicked: root.confirmKill(row.killKey, row.pids)
    }
  }
}
