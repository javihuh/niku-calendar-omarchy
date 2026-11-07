import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

PanelWindow {
  id: root
  property bool enabledSetting: false
  property bool compactSetting: false
  property var scheduleStatus: ({ events: [] })
  property var canvasStatus: ({ assignments: [] })
  property string languageCode: "en"
  property color foreground: Commons.Color.bar.text
  property date currentTime: new Date()
  property int savedX: -1
  property int savedY: -1
  property bool positionTouched: false
  property bool positionDirty: false
  property bool directoryReady: false
  property point dragOrigin
  property point dragPosition

  signal compactRequested(bool compact)
  signal activityRequested(string activityId)
  signal calendarRequested()
  signal academicRequested()

  readonly property string positionPath: Quickshell.env("HOME") + "/.local/state/omarchy/niku-desktop.json"
  readonly property var primaryScreen: Quickshell.screens.length ? Quickshell.screens[0] : null
  readonly property var primaryMonitor: primaryScreen ? Hyprland.monitorFor(primaryScreen) : null

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
  onVisibleChanged: if (visible) currentTime = new Date()

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
    running: root.enabledSetting
    onExited: function(exitCode) {
      if (exitCode !== 0) return
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
    running: root.visible
    repeat: true
    onTriggered: root.currentTime = new Date()
  }

  BorderSurface {
    id: card
    x: root.savedX >= 0 ? root.clampX(root.savedX) : Math.max(0, root.width - width - Style.space(28))
    y: root.savedY >= 0 ? root.clampY(root.savedY) : Math.max(0, root.height - height - Style.space(28))
    width: Math.min(Style.space(340), Math.max(0, root.width - Style.space(24)))
    height: Math.min((content.item ? content.item.implicitHeight : 0) + Style.space(28), Math.max(0, root.height - Style.space(56)))
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    borderSpec: Commons.Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)

    Loader {
      id: content
      anchors.fill: parent
      anchors.margins: Style.space(14)
      active: root.visible
      sourceComponent: Component {
        DesktopCard {
          scheduleStatus: root.scheduleStatus
          canvasStatus: root.canvasStatus
          languageCode: root.languageCode
          foreground: root.foreground
          currentTime: root.currentTime
          compact: root.compactSetting
          onCompactRequested: function(compact) { root.compactRequested(compact) }
          onActivityRequested: function(activityId) { root.activityRequested(activityId) }
          onCalendarRequested: root.calendarRequested()
          onAcademicRequested: root.academicRequested()
          onDragStarted: function(sceneX, sceneY) {
            root.dragOrigin = Qt.point(sceneX, sceneY)
            root.dragPosition = Qt.point(card.x, card.y)
          }
          onDragMoved: function(sceneX, sceneY) {
            root.positionTouched = true
            root.savedX = Math.round(root.clampX(root.dragPosition.x + sceneX - root.dragOrigin.x))
            root.savedY = Math.round(root.clampY(root.dragPosition.y + sceneY - root.dragOrigin.y))
          }
          onDragFinished: root.settlePosition()
        }
      }
    }
  }
}
