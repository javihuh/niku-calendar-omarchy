import QtQuick
import Quickshell.Io
import Quickshell
import qs.Commons
import qs.Ui
import "I18n.js" as I18n

BarWidget {
  id: root
  moduleName: "io.github.javihuh.schedule"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool configured: panelLoader.item ? panelLoader.item.configured === true : false
  readonly property int todayCount: panelLoader.item ? panelLoader.item.todayCount : 0
  readonly property string languageCode: I18n.languageCode(setting("language", "English"))
  readonly property string scheduleTitle: panelLoader.item
    ? String(panelLoader.item.scheduleTitle || "Schedule")
    : "Schedule"
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false
  readonly property var scheduleStatus: panelLoader.item ? panelLoader.item.scheduleStatus : ({ events: [] })
  readonly property var canvasStatus: panelLoader.item ? panelLoader.item.canvasStatus : ({ assignments: [] })
  readonly property var desktopService: bar && bar.shell && bar.shell.serviceFor
    ? bar.shell.serviceFor(root.moduleName) : null

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function refresh() {
    if (panelLoader.item) panelLoader.item.refresh()
  }

  function chooseCsv() {
    if (panelLoader.item) panelLoader.item.chooseCsv()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Binding {
    target: root.desktopService
    property: "enabledSetting"
    value: root.setting("desktopWidget", "Off") === "On"
    when: root.desktopService !== null
  }
  Binding {
    target: root.desktopService
    property: "scheduleStatus"
    value: root.scheduleStatus
    when: root.desktopService !== null
  }
  Binding {
    target: root.desktopService
    property: "canvasStatus"
    value: root.canvasStatus
    when: root.desktopService !== null
  }
  Binding {
    target: root.desktopService
    property: "languageCode"
    value: root.languageCode
    when: root.desktopService !== null
  }

  IpcHandler {
    target: "io.github.javihuh.schedule"

    function refresh(): void { root.refresh() }
    function choose(): void { root.chooseCsv() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: 15
    text: "\uDB80\uDD1B"
    active: root.opened
    dimmed: !root.configured
    tooltipText: !root.configured
      ? I18n.t(root.languageCode, "bar.empty", { title: root.scheduleTitle })
      : I18n.plural(root.languageCode, "bar.today", root.todayCount, {
          title: root.scheduleTitle
        })
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
