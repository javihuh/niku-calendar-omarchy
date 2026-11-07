import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "I18n.js" as I18n
import "ScheduleView.js" as ScheduleView
import "NikuData.js" as NikuData

Item {
  id: root

  property var scheduleStatus: ({})
  property var canvasStatus: ({ assignments: [] })
  property bool desktopEnabled: false
  property date currentTime: new Date()
  property string languageCode: "en"
  property string periodView: "day"
  property string weekLayout: "list"
  property bool showCanvasCalendar: false
  property var canvasCalendarEvents: []
  property bool panelOpen: false
  property bool importOpen: false
  readonly property bool calendarVisible: !canvasView && periodView === "week" && weekLayout === "calendar"
  property bool canvasView: false
  property bool canvasSetupOpen: false
  property bool canvasHasToken: false
  property bool canvasSaving: false
  property string canvasBaseUrl: ""
  property string canvasSetupError: ""
  property var previewData: null
  property string csvPath: ""
  property string notice: ""
  property bool noticeIsError: false
  property bool choosing: false
  property bool previewing: false
  property bool importing: false
  property bool busy: false
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property bool renameActive: false

  readonly property bool configured: scheduleStatus.configured === true
  readonly property int todayCount: Number(scheduleStatus.todayCount || 0)
  readonly property string referenceDate: String(scheduleStatus.referenceDate || "")
  readonly property string weekStart: String(scheduleStatus.weekStart || "")
  readonly property string weekEnd: String(scheduleStatus.weekEnd || "")
  readonly property var pendingAssignments: NikuData.pending(canvasStatus.assignments, currentTime)
  readonly property var timelineEvents: (scheduleStatus.events || []).concat(showCanvasCalendar
    ? ScheduleView.canvasEvents(canvasStatus.assignments, canvasCalendarEvents) : []).sort(function(a, b) {
      return (a.date + a.startTime).localeCompare(b.date + b.startTime)
    })
  readonly property var periodEvents: ScheduleView.eventsForView(
    timelineEvents, periodView, referenceDate, weekStart, weekEnd)
  readonly property var eventGroups: ScheduleView.groupEvents(periodEvents)
  readonly property var previewItems: previewData && previewData.items ? previewData.items : []
  readonly property var previewErrors: previewData && previewData.errors ? previewData.errors : []
  readonly property var previewWarnings: previewData && previewData.warnings ? previewData.warnings : []
  readonly property bool previewReady: previewData && previewData.ok === true
  readonly property bool canvasUrlActive: canvasUrlField.activeFocus
  readonly property bool inputActive: renameField.activeFocus || (importOpen && pathField.activeFocus)
    || (academicLoader.item && academicLoader.item.inputActive)
    || (canvasView && (canvasUrlField.activeFocus || canvasTokenField.activeFocus))

  signal renameRequested(string title)
  signal addRequested()
  signal manageRequested()
  signal periodViewRequested(string value)
  signal weekLayoutRequested(string value)
  signal canvasCalendarToggleRequested()
  signal activityRequested(string activityId)
  signal chooseRequested()
  signal previewRequested()
  signal importRequested()
  signal desktopToggleRequested()
  signal canvasRefreshRequested()
  signal canvasConfigureRequested(string baseUrl, string token)
  signal pathEdited()
  signal focusReleaseRequested()

  function first(values, count) {
    if (!values || !values.length) return []
    return values.slice(0, Math.min(values.length, count))
  }

  function eventDateLabel(isoDate) {
    return I18n.shortDate(languageCode, isoDate)
  }

  function recurrenceLabel(item) {
    return I18n.recurrenceLabel(languageCode, item.recurrence).toLowerCase()
  }

  function clearCanvasToken() { canvasTokenField.text = "" }
  onPanelOpenChanged: if (panelOpen) currentTime = new Date()
  onCanvasViewChanged: mainScroll.contentY = 0
  onWeekLayoutChanged: mainScroll.contentY = 0
  onPeriodViewChanged: mainScroll.contentY = 0
  onImportOpenChanged: if (importOpen) Qt.callLater(function() {
    mainScroll.contentY = Math.min(Math.max(0, mainScroll.contentHeight - mainScroll.height), importSection.y)
  })

  onCanvasBaseUrlChanged: if (!canvasUrlField.activeFocus) canvasUrlField.text = canvasBaseUrl
  onCanvasSetupOpenChanged: if (!canvasSetupOpen && canvasHasToken) clearCanvasToken()

  function canvasErrorText(code) {
    var spanish = languageCode === "es"
    if (code === "invalid_url") return spanish ? "Ingresa solo el dominio HTTPS de Canvas." : "Enter the HTTPS Canvas domain only."
    if (code === "missing_token" || code === "invalid_token")
      return spanish ? "Ingresa un token de Canvas válido." : "Enter a valid Canvas token."
    return spanish ? "No se pudo guardar la configuración de Canvas." : "Could not save Canvas settings."
  }

  function startRename() {
    if (busy) return
    renameField.text = String(scheduleStatus.title || "Schedule")
    renameActive = true
    Qt.callLater(function() {
      renameField.forceActiveFocus()
      renameField.selectAll()
    })
  }

  function cancelRename() {
    renameActive = false
    focusReleaseRequested()
  }

  function commitRename() {
    var title = String(renameField.text || "").trim()
    if (!title || busy) return
    renameActive = false
    renameRequested(title)
    focusReleaseRequested()
  }

  Timer {
    interval: 30000
    running: root.panelOpen
    repeat: true
    onTriggered: root.currentTime = new Date()
  }

  Flickable {
    id: mainScroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: mainContent.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: mainContent
      width: mainScroll.width
      spacing: Style.space(16)

      Item {
        width: parent.width
        implicitHeight: Math.max(heroIcon.implicitHeight, heroText.implicitHeight, heroCount.implicitHeight)

        PanelActionButton {
          id: desktopAction
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          iconText: root.desktopEnabled ? "\uf070" : "\uf06e"
          tooltipText: root.desktopEnabled
            ? (root.languageCode === "es" ? "Ocultar widget de escritorio" : "Hide desktop widget")
            : (root.languageCode === "es" ? "Mostrar widget de escritorio" : "Show desktop widget")
          foreground: root.foreground
          fontFamily: root.fontFamily
          focusable: true
          onClicked: root.desktopToggleRequested()
        }

        Text {
          id: heroIcon
          textFormat: Text.PlainText
          anchors.left: desktopAction.right
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          text: "\uDB80\uDD1B"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge
        }

        Column {
          id: heroText
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: renameAction.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs

          Text {
            textFormat: Text.PlainText
            visible: !root.renameActive
            width: parent.width
            text: String(root.scheduleStatus.title || "Schedule")
            elide: Text.ElideRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          TextField {
            id: renameField
            visible: root.renameActive
            width: parent.width
            foreground: root.foreground
            font.family: root.fontFamily
            maximumLength: 200
            enabled: !root.busy
            activeFocusOnTab: false
            onAccepted: root.commitRename()
            Keys.onEscapePressed: function(event) {
              root.cancelRename()
              event.accepted = true
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: !root.renameActive
            width: parent.width
            text: I18n.plural(root.languageCode, "count.activities",
              Number(root.scheduleStatus.itemCount || 0))
            elide: Text.ElideRight
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }
        }

        PanelActionButton {
          id: renameAction
          anchors.right: heroCount.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          iconText: root.renameActive ? "\uf00c" : "\uf044"
          tooltipText: root.renameActive
            ? I18n.t(root.languageCode, "main.saveName")
            : I18n.t(root.languageCode, "main.rename")
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: !root.busy
          onClicked: root.renameActive ? root.commitRename() : root.startRename()
        }

        Rectangle {
          id: heroCount
          anchors.right: headerActions.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: todayLabel.implicitWidth + Style.space(16)
          implicitHeight: Style.space(30)
          radius: Style.cornerRadius
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
          Text {
            id: todayLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.todayCount + (root.languageCode === "es" ? " hoy" : " today")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      Row {
        id: headerActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)
        Button {
          anchors.verticalCenter: parent.verticalCenter
          text: "Canvas"
          iconText: "\uf19d"
          tooltipText: root.languageCode === "es" ? "Panel académico · Canvas" : "Academic panel · Canvas"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          active: root.canvasView
          bordered: true
          focusable: true
          onClicked: root.canvasView = !root.canvasView
        }
        PanelActionButton {
          visible: !root.canvasView
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf093"
          size: Style.space(32)
          bordered: true
          focusable: true
          tooltipText: I18n.t(root.languageCode, "main.importHeading")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.importOpen = !root.importOpen
        }
      }
      }

      PanelSeparator { foreground: root.foreground }

      Row {
        visible: !root.canvasView
        width: parent.width
        spacing: Style.space(12)
      Button {
        visible: !root.canvasView
        width: (parent.width - parent.spacing) / 2
        text: I18n.t(root.languageCode, "common.addActivity")
        iconText: "\uf067"
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        active: true
        enabled: !root.busy
        opacity: enabled ? 1 : 0.45
        onClicked: root.addRequested()
      }

      Button {
        visible: !root.canvasView
        width: (parent.width - parent.spacing) / 2
        text: I18n.t(root.languageCode, "main.manage")
        iconText: "\uf03a"
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: false
        enabled: !root.busy
        opacity: enabled ? 1 : 0.45
        onClicked: root.manageRequested()
      }
      }

      Column {
        visible: !root.canvasView
        width: parent.width
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(12)
          Text {
            width: Style.space(60)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.languageCode === "es" ? "Vista" : "View"
            color: root.foreground
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          ViewSelector {
            width: parent.width - Style.space(72)
            value: root.periodView
            options: [
              { value: "day", label: I18n.t(root.languageCode, "main.viewDay") },
              { value: "week", label: I18n.t(root.languageCode, "main.viewWeek") }
            ]
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !root.busy
            onChosen: function(value) { root.periodViewRequested(value) }
          }
        }
        Row {
          visible: root.periodView === "week"
          width: parent.width
          spacing: Style.space(12)
          Text {
            width: Style.space(60)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.languageCode === "es" ? "Diseño" : "Layout"
            color: root.foreground
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          ViewSelector {
            width: parent.width - Style.space(72)
            value: root.weekLayout
            options: [
              { value: "list", label: root.languageCode === "es" ? "Lista" : "List", icon: "\uf03a" },
              { value: "calendar", label: root.languageCode === "es" ? "Calendario" : "Calendar", icon: "\uf073" }
            ]
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChosen: function(value) { root.weekLayoutRequested(value) }
          }
        }
        Item {
          visible: root.periodView === "week"
          width: parent.width
          implicitHeight: canvasToggle.implicitHeight
          Text {
            anchors.left: parent.left
            anchors.right: canvasToggle.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.languageCode === "es" ? "Entregas y eventos de Canvas" : "Canvas deadlines and events"
            color: root.foreground
            opacity: 0.8
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          ToggleSwitch {
            id: canvasToggle
            anchors.right: parent.right
            checked: root.showCanvasCalendar
            foreground: root.foreground
            onToggled: root.canvasCalendarToggleRequested()
          }
        }
      }

      PanelSectionHeader {
        visible: !root.canvasView
        text: root.periodView === "week"
          ? I18n.t(root.languageCode, "main.weekActivities") + " · "
            + I18n.shortDate(root.languageCode, root.weekStart) + " – " + I18n.shortDate(root.languageCode, root.weekEnd)
          : I18n.t(root.languageCode, "main.todayActivities")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        textFormat: Text.PlainText
        visible: !root.canvasView && root.configured && root.periodView === "day"
          && root.periodEvents.length > 0
        width: parent.width
        text: I18n.dailyEncouragement(root.languageCode, root.referenceDate)
        wrapMode: Text.WordWrap
        color: root.foreground
        opacity: 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }

      Text {
        textFormat: Text.PlainText
        visible: !root.canvasView && !root.configured && root.periodEvents.length === 0
        width: parent.width
        text: I18n.t(root.languageCode, "main.empty")
        wrapMode: Text.WordWrap
        color: Qt.darker(root.foreground, 1.35)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        textFormat: Text.PlainText
        visible: !root.canvasView && root.periodEvents.length === 0 && root.configured
        width: parent.width
        text: root.periodView === "week"
          ? I18n.t(root.languageCode, "main.noWeek")
          : I18n.t(root.languageCode, "main.noToday")
        wrapMode: Text.WordWrap
        color: Qt.darker(root.foreground, 1.35)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Column {
        visible: !root.canvasView && !root.calendarVisible && root.eventGroups.length > 0
        width: parent.width
        spacing: Style.space(12)

        Repeater {
          model: root.panelOpen && !root.canvasView && !root.calendarVisible ? root.eventGroups : []

          Column {
            id: dayGroup
            required property var modelData
            width: mainContent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              visible: root.periodView === "week"
              width: parent.width
              text: I18n.longDate(root.languageCode, dayGroup.modelData.date)
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: dayGroup.modelData.events

              Rectangle {
                id: eventCard
                required property var modelData
                readonly property string temporalState: ScheduleView.temporalState(modelData, root.currentTime)
                readonly property bool activeNow: temporalState === "active"
                readonly property bool occurred: temporalState === "occurred"
                width: dayGroup.width
                implicitHeight: eventContent.implicitHeight + Style.space(14)
                radius: Style.cornerRadius
                color: activeNow
                  ? Style.selectedFillFor(root.foreground, Commons.Color.accent)
                  : occurred
                    ? (eventMouse.containsMouse
                      ? Style.hoverFillFor(Commons.Color.muted, Commons.Color.muted)
                      : Style.normalFillFor(Commons.Color.muted, Commons.Color.muted))
                    : (eventMouse.containsMouse
                      ? Style.hoverFillFor(root.foreground, Commons.Color.accent)
                      : Qt.rgba(root.foreground.r, root.foreground.g,
                          root.foreground.b, 0.055))
                border.width: activeNow ? Math.max(1, Style.normalBorderWidth) : 0
                border.color: Style.selectedStateColor(root.foreground, Commons.Color.accent)

                Column {
                  id: eventContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.spacing.xs

                  Row {
                    width: parent.width
                    spacing: Style.spacing.lg

                    Text {
                      id: eventDate
                      textFormat: Text.PlainText
                      width: Style.space(86)
                      text: root.eventDateLabel(eventCard.modelData.date).toUpperCase()
                      color: eventCard.activeNow ? root.foreground
                        : (eventCard.occurred ? Commons.Color.muted
                          : Qt.darker(root.foreground, 1.35))
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width - eventDate.width - parent.spacing
                        - (eventStatus.visible
                          ? eventStatus.implicitWidth + parent.spacing : 0)
                      text: (eventCard.modelData.source === "canvas" ? "◈ " : "")
                        + String(eventCard.modelData.title || "")
                      elide: Text.ElideRight
                      color: eventCard.occurred ? Commons.Color.muted : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Text {
                      id: eventStatus
                      textFormat: Text.PlainText
                      visible: eventCard.activeNow || eventCard.occurred
                      text: "\uf1b0  " + (eventCard.activeNow
                        ? I18n.t(root.languageCode, "main.active")
                        : I18n.t(root.languageCode, "main.occurred"))
                      color: eventCard.activeNow
                        ? Style.selectedStateColor(root.foreground, Commons.Color.accent)
                        : Commons.Color.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 0.8
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: String(eventCard.modelData.startTime || "")
                      + (eventCard.modelData.endTime ? " - " + eventCard.modelData.endTime : "")
                      + (eventCard.modelData.location
                        ? " · " + String(eventCard.modelData.location) : "")
                    elide: Text.ElideRight
                    color: eventCard.activeNow ? root.foreground
                      : (eventCard.occurred ? Commons.Color.muted
                        : Qt.darker(root.foreground, 1.45))
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  id: eventMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  enabled: !root.busy
                  onClicked: {
                    if (eventCard.modelData.source === "canvas") {
                      if (eventCard.modelData.url) Qt.openUrlExternally(eventCard.modelData.url)
                    } else root.activityRequested(String(eventCard.modelData.activityId || ""))
                  }
                }
              }
            }
          }
        }
      }

      Loader {
        active: root.panelOpen && root.calendarVisible
        visible: active
        width: parent.width
        height: active ? Math.max(Style.space(220), root.height - y) : 0
        sourceComponent: Component {
          WeekCalendar {
            events: root.periodEvents
            weekStart: root.weekStart
            languageCode: root.languageCode
            currentTime: root.currentTime
            foreground: root.foreground
            fontFamily: root.fontFamily
            busy: root.busy
            onActivityRequested: function(activityId) { root.activityRequested(activityId) }
          }
        }
      }

      Column {
        visible: root.canvasView
        width: parent.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.spacing.md
          PanelSectionHeader {
            width: parent.width - canvasRefresh.width - canvasSetupAction.width - canvasBack.width - parent.spacing * 3
            text: root.languageCode === "es" ? "Panel académico" : "Academic panel"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          PanelActionButton {
            id: canvasBack
            iconText: "\uf060"
            tooltipText: root.languageCode === "es" ? "Volver al calendario" : "Back to calendar"
            foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: root.canvasView = false
          }
          PanelActionButton {
            id: canvasSetupAction
            iconText: "\uf013"
            tooltipText: root.languageCode === "es" ? "Configurar Canvas" : "Set up Canvas"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.canvasSetupOpen = !root.canvasSetupOpen
          }
          PanelActionButton {
            id: canvasRefresh
            iconText: "\uf021"
            tooltipText: root.languageCode === "es" ? "Actualizar Canvas" : "Refresh Canvas"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              root.canvasRefreshRequested()
              if (academicLoader.item) academicLoader.item.refresh()
            }
          }
        }

        Column {
          visible: root.canvasSetupOpen || !root.canvasHasToken
          width: parent.width
          spacing: Style.spacing.md

          Text {
            textFormat: Text.PlainText
            text: root.languageCode === "es" ? "Dirección de Canvas" : "Canvas address"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          TextField {
            id: canvasUrlField
            width: parent.width
            text: root.canvasBaseUrl
            placeholderText: "https://canvas.example.edu"
            foreground: root.foreground
            font.family: root.fontFamily
            enabled: !root.canvasSaving
            activeFocusOnTab: false
            onTextEdited: root.canvasBaseUrl = text
            onActiveFocusChanged: if (!activeFocus) text = root.canvasBaseUrl
          }

          Text {
            textFormat: Text.PlainText
            text: root.languageCode === "es" ? "Token de acceso" : "Access token"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          TextField {
            id: canvasTokenField
            width: parent.width
            password: true
            placeholderText: root.canvasHasToken
              ? (root.languageCode === "es" ? "Vacío para mantener el token" : "Leave blank to keep your token")
              : (root.languageCode === "es" ? "Pega tu token aquí" : "Paste your token here")
            foreground: root.foreground
            font.family: root.fontFamily
            enabled: !root.canvasSaving
            activeFocusOnTab: false
          }

          Text {
            textFormat: Text.PlainText
            visible: root.canvasSetupError !== ""
            width: parent.width
            text: root.canvasSetupError
            wrapMode: Text.WordWrap
            color: Commons.Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            width: parent.width
            text: root.canvasSaving
              ? (root.languageCode === "es" ? "Guardando..." : "Saving...")
              : (root.languageCode === "es" ? "Guardar y sincronizar" : "Save and sync")
            iconText: "\uf0c7"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: !root.canvasSaving && root.canvasBaseUrl.trim() !== ""
              && (root.canvasHasToken || canvasTokenField.text.trim() !== "")
            onClicked: root.canvasConfigureRequested(root.canvasBaseUrl, canvasTokenField.text)
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: !root.canvasStatus.configured || root.canvasStatus.stale === true
            || root.canvasStatus.ok === false
          width: parent.width
          text: !root.canvasStatus.configured
            ? (root.languageCode === "es" ? "Configura Canvas para ver entregas." : "Configure Canvas to see assignments.")
            : (root.languageCode === "es" ? "Datos de Canvas sin conexión; se muestra la caché."
                : "Canvas is offline; showing cached data.")
          color: Qt.darker(root.foreground, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Loader {
          id: academicLoader
          active: root.panelOpen && root.canvasView && root.canvasHasToken && !root.canvasSetupOpen
          visible: active
          width: parent.width
          height: active ? Math.max(Style.space(260), root.height - parent.y - y) : 0
          sourceComponent: Component {
            AcademicPanel {
              languageCode: root.languageCode
              foreground: root.foreground
              fontFamily: root.fontFamily
              onCalendarRequested: {
                root.canvasView = false
                root.periodViewRequested("week")
                root.weekLayoutRequested("calendar")
                if (!root.showCanvasCalendar) root.canvasCalendarToggleRequested()
              }
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: !root.canvasView && root.notice !== ""
        width: parent.width
        text: root.notice
        wrapMode: Text.WordWrap
        color: root.noticeIsError ? Commons.Color.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Column {
      id: importSection
      visible: root.importOpen && !root.canvasView
      width: parent.width
      spacing: Style.spacing.md
      PanelSeparator { visible: !root.canvasView; foreground: root.foreground }

      PanelSectionHeader {
        visible: !root.canvasView
        text: I18n.t(root.languageCode, "main.importHeading")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Row {
        visible: !root.canvasView
        width: parent.width
        spacing: Style.spacing.lg

        TextField {
          id: pathField
          width: parent.width - browseButton.width - previewButton.width
            - parent.spacing * 2
          placeholderText: I18n.t(root.languageCode, "main.pathPlaceholder")
          text: root.csvPath
          foreground: root.foreground
          font.family: root.fontFamily
          enabled: !root.busy
          activeFocusOnTab: false
          onTextEdited: {
            root.csvPath = text
            root.pathEdited()
          }
          onAccepted: root.previewRequested()
          Keys.onEscapePressed: function(event) {
            root.focusReleaseRequested()
            event.accepted = true
          }
        }

        Button {
          id: browseButton
          iconText: "\uf07c"
          tooltipText: root.choosing
            ? I18n.t(root.languageCode, "main.browseOpen")
            : I18n.t(root.languageCode, "common.browse")
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          enabled: !root.busy
          opacity: enabled ? 1 : 0.45
          onClicked: root.chooseRequested()
        }

        Button {
          id: previewButton
          iconText: root.previewing ? "\uf110" : "\uf06e"
          iconSpinning: root.previewing
          tooltipText: root.previewing
            ? I18n.t(root.languageCode, "main.validating")
            : I18n.t(root.languageCode, "main.previewCsv")
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          enabled: !root.busy && String(root.csvPath).trim() !== ""
          opacity: enabled ? 1 : 0.45
          onClicked: root.previewRequested()
        }
      }

      Repeater {
        model: root.canvasView ? [] : root.first(root.previewErrors, 5)

        Text {
          required property var modelData
          textFormat: Text.PlainText
          width: mainContent.width
          text: (Number(modelData.row || 0) > 0
            ? I18n.t(root.languageCode, "row.prefix", { row: modelData.row })
            : "")
            + String(modelData.message || "")
          wrapMode: Text.WordWrap
          color: Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Repeater {
        model: root.canvasView ? [] : root.first(root.previewWarnings, 3)

        Text {
          required property var modelData
          textFormat: Text.PlainText
          width: mainContent.width
          text: String(modelData)
          wrapMode: Text.WordWrap
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Column {
        visible: !root.canvasView && root.previewItems.length > 0
        width: parent.width
        spacing: Style.spacing.md

        PanelSectionHeader {
          text: I18n.t(root.languageCode, "main.preview")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          model: root.first(root.previewItems, 6)

          Row {
            required property var modelData
            width: parent.width
            spacing: Style.spacing.lg

            Text {
              textFormat: Text.PlainText
              width: Style.space(88)
              text: String(modelData.startTime || "") + " - " + String(modelData.endTime || "")
              color: Qt.darker(root.foreground, 1.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width - Style.space(96)
              text: String(modelData.title || "") + " · " + root.recurrenceLabel(modelData)
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.previewItems.length > 6
          width: parent.width
          text: I18n.plural(root.languageCode, "count.rows",
            root.previewItems.length - 6)
          horizontalAlignment: Text.AlignHCenter
          color: Qt.darker(root.foreground, 1.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: !root.canvasView && root.previewItems.length > 0
        width: parent.width
        text: I18n.t(root.languageCode, "main.importWarning")
        wrapMode: Text.WordWrap
        color: Commons.Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Button {
        visible: !root.canvasView && root.previewItems.length > 0
        width: parent.width
        text: root.importing
          ? I18n.t(root.languageCode, "main.importing")
          : I18n.t(root.languageCode, "main.importReplace")
        iconText: root.importing ? "\uf110" : "\uf093"
        iconSpinning: root.importing
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        active: root.previewReady
        enabled: root.previewReady && !root.busy
        opacity: enabled ? 1 : 0.45
        onClicked: root.importRequested()
      }

      Text {
        textFormat: Text.PlainText
        visible: !root.canvasView && pathField.activeFocus
        width: parent.width
        text: I18n.t(root.languageCode, "main.columns")
        wrapMode: Text.WordWrap
        color: Qt.darker(root.foreground, 1.65)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      }
    }
  }
}
