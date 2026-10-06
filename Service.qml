import QtQuick

// Desktop layer surfaces need a service lifetime, independent of the bar's
// item hierarchy. The bar supplies its current settings and backend snapshots.
Item {
  id: root


  property bool enabledSetting: false
  property var scheduleStatus: ({ events: [] })
  property var canvasStatus: ({ assignments: [] })
  property string languageCode: "en"

  DesktopWidget {
    enabledSetting: root.enabledSetting
    scheduleStatus: root.scheduleStatus
    canvasStatus: root.canvasStatus
    languageCode: root.languageCode
  }
}
