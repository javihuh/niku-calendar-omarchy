import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "NikuData.js" as NikuData

PanelWindow {
  id: root

  property bool enabledSetting: false
  property var scheduleStatus: ({ events: [] })
  property var canvasStatus: ({ assignments: [] })
  property string languageCode: "en"
  property date currentTime: new Date()
  property int savedX: -1
  property int savedY: -1
  property bool positionTouched: false
  property bool positionDirty: false
  property bool directoryReady: false

  readonly property string positionPath: Quickshell.env("HOME") + "/.local/state/omarchy/niku-desktop.json"

  function clampX(value) { return Math.max(0, Math.min(value, Math.max(0, width - card.width))) }
  function clampY(value) { return Math.max(0, Math.min(value, Math.max(0, height - card.height))) }

  function restorePosition(raw) {
    if (positionTouched) return
    try {
      var position = JSON.parse(raw)
      if (position.version !== 1 || !Number.isFinite(position.x) || !Number.isFinite(position.y)) return
      savedX = Math.max(0, Math.round(position.x))
      savedY = Math.max(0, Math.round(position.y))
    } catch (error) { /* No saved position yet; use the bottom-right corner. */ }
  }

  function flushPosition() {
    if (!directoryReady || !positionDirty) return
    positionFile.setText(JSON.stringify({ version: 1, x: savedX, y: savedY }) + "\n")
    positionDirty = false
  }

  function settlePosition() {
    if (!positionTouched) return
    savedX = Math.round(card.x)
    savedY = Math.round(card.y)
    positionDirty = true
    flushPosition()
  }

  Component.onDestruction: flushPosition()

  readonly property var primaryScreen: Quickshell.screens.length ? Quickshell.screens[0] : null
  readonly property var primaryMonitor: primaryScreen ? Hyprland.monitorFor(primaryScreen) : null
  readonly property string today: Qt.formatDate(currentTime, "yyyy-MM-dd")
  readonly property var classes: NikuData.classesToday(scheduleStatus.events, today)
  readonly property var upcoming: classes.filter(function(event) { return event.state === "upcoming" })
  readonly property var activeClass: classes.filter(function(event) { return event.state === "active" })
  readonly property var assignments: NikuData.pending(canvasStatus.assignments, currentTime)
  readonly property bool spanish: languageCode === "es"


  function weekday() {
    var es = ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"]
    var en = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    return (spanish ? es : en)[currentTime.getDay()]
  }

  screen: primaryScreen
  visible: enabledSetting && primaryScreen !== null
    && primaryMonitor !== null && primaryMonitor.activeWorkspace !== null
    && primaryMonitor.activeWorkspace.id === 1
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  WlrLayershell.namespace: "niku-desktop"
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region { x: card.x; y: card.y; width: card.width; height: card.height }

  ScreenMoveRemap { window: root }

  Process {
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/omarchy"]
    running: true
    onExited: {
      root.directoryReady = true
      positionFile.reload()
      root.flushPosition()
    }
  }

  FileView {
    id: positionFile
    path: root.positionPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.restorePosition(text())
    onSaveFailed: function(error) { console.warn("niku: could not save desktop position: " + error) }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.currentTime = new Date()
  }

  Rectangle {
    id: card
    x: root.savedX >= 0 ? root.clampX(root.savedX) : Math.max(0, root.width - width - 28)
    y: root.savedY >= 0 ? root.clampY(root.savedY) : Math.max(0, root.height - height - 28)
    width: 360
    height: content.implicitHeight + 28
    radius: 16
    color: Color.popups.background
    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.22)
    border.width: 1

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 14
      spacing: 10

      Row {
        width: parent.width
        spacing: 8
        Text {
          textFormat: Text.PlainText
          width: parent.width - dateLabel.implicitWidth - parent.spacing
          text: "NIKU ≽(◉˕ ◉ ≼マ"
          color: Color.foreground
          font.family: Style.font.family
          font.bold: true
          font.pixelSize: 16
          elide: Text.ElideRight
        }
        Text {
          id: dateLabel
          textFormat: Text.PlainText
          text: root.weekday().slice(0, 3).toUpperCase()
            + " · " + Qt.formatDate(root.currentTime, "dd/MM")
          color: Color.foreground
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: 11
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Color.foreground
        opacity: 0.2
      }

      Column {
        width: parent.width
        spacing: 5

        Text {
          text: root.spanish ? "AHORA" : "NOW"
          color: Color.accent
          font.family: Style.font.family
          font.bold: true
          font.pixelSize: 11
        }

        Repeater {
          model: root.activeClass.length ? root.activeClass.slice(0, 1) : [null]
          Column {
            required property var modelData
            width: content.width
            spacing: 3
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: modelData ? String(modelData.title || "")
                : (root.spanish ? "Sin clase en curso" : "No class in progress")
              color: Color.foreground
              opacity: modelData ? 1 : 0.7
              font.family: Style.font.family
              font.pixelSize: 14
              font.bold: !!modelData
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
            Text {
              visible: !!modelData
              textFormat: Text.PlainText
              text: modelData ? modelData.startTime + " – " + modelData.endTime
                + (modelData.location ? " · " + modelData.location : "") : ""
              width: parent.width
              color: Color.foreground
              opacity: 0.7
              font.family: Style.font.family
              font.pixelSize: 11
              elide: Text.ElideRight
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: 5

        Text {
          text: root.spanish ? "DESPUÉS" : "NEXT"
          color: Color.accent
          font.family: Style.font.family
          font.bold: true
          font.pixelSize: 11
        }

        Repeater {
          model: root.upcoming.slice(0, 2)
          Row {
            required property var modelData
            width: content.width
            spacing: 9
            Text {
              text: modelData.startTime
              color: Color.foreground
              opacity: 0.7
              font.family: Style.font.family
              font.pixelSize: 12
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width - x
              text: String(modelData.title || "")
              elide: Text.ElideRight
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: 12
            }
          }
        }
        Text {
          visible: root.upcoming.length === 0
          text: root.spanish ? "Sin más clases hoy" : "No more classes today"
          color: Color.foreground
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: 12
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Color.foreground
        opacity: 0.2
      }

      Column {
        width: parent.width
        spacing: 6

        Text {
          text: root.spanish ? "PRÓXIMAS ENTREGAS" : "UPCOMING ASSIGNMENTS"
          color: Color.accent
          font.family: Style.font.family
          font.bold: true
          font.pixelSize: 11
        }

        Repeater {
          model: root.assignments.slice(0, 2)
          Column {
            required property var modelData
            width: content.width
            spacing: 2

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: String(modelData.title || "")
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: 12
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: 8
              Text {
                textFormat: Text.PlainText
                width: parent.width - remaining.implicitWidth - parent.spacing
                text: Qt.formatDateTime(new Date(modelData.dueAt), "dd/MM  HH:mm")
                elide: Text.ElideRight
                color: Color.foreground
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: 11
              }
              Text {
                id: remaining
                text: NikuData.remainingLabel(modelData.dueAt, root.currentTime, root.languageCode)
                color: Color.foreground
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: 11
              }
            }
          }
        }

        Text {
          visible: root.assignments.length === 0
          text: root.spanish ? "Sin entregas próximas" : "No upcoming assignments"
          color: Color.foreground
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: 12
        }
      }
    }

    MouseArea {
      id: dragArea
      anchors.fill: parent
      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
      property real pressX: 0
      property real pressY: 0
      onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
      onPositionChanged: function(mouse) {
        if (!pressed) return
        var nextX = root.clampX(card.x + mouse.x - pressX)
        var nextY = root.clampY(card.y + mouse.y - pressY)
        if (nextX === card.x && nextY === card.y) return
        root.positionTouched = true
        root.savedX = Math.round(nextX)
        root.savedY = Math.round(nextY)
      }
      onReleased: root.settlePosition()
      onCanceled: root.settlePosition()
    }
  }
}
