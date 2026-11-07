import QtQuick
import qs.Commons as Commons

// Desktop layer surfaces need a service lifetime, independent of the bar's
// item hierarchy. The bar supplies its current settings and backend snapshots.
Item {
  id: root


  property bool enabledSetting: false
  property bool compactSetting: false
  property var scheduleStatus: ({ events: [] })
  property var canvasStatus: ({ assignments: [] })
  property string languageCode: "en"
  property color foreground: Commons.Color.bar.text
  readonly property string desktopScreenName: desktop.primaryScreen ? desktop.primaryScreen.name : ""
  readonly property bool widgetVisible: desktop.visible
  signal compactRequested(bool compact)
  signal activityRequested(string activityId)
  signal calendarRequested()
  signal academicRequested()

  DesktopWidget {
    id: desktop
    enabledSetting: root.enabledSetting
    compactSetting: root.compactSetting
    scheduleStatus: root.scheduleStatus
    canvasStatus: root.canvasStatus
    languageCode: root.languageCode
    foreground: root.foreground
    onCompactRequested: function(compact) { root.compactRequested(compact) }
    onActivityRequested: function(activityId) { root.activityRequested(activityId) }
    onCalendarRequested: root.calendarRequested()
    onAcademicRequested: root.academicRequested()
  }
}
