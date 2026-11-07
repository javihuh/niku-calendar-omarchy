pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "NikuData.js" as NikuData
import "ScheduleView.js" as ScheduleView
import "I18n.js" as I18n

Item {
  id: root
  property var scheduleStatus: ({ events: [] })
  property var canvasStatus: ({ assignments: [] })
  property string languageCode: "en"
  property bool compact: false
  property date currentTime: new Date()
  property color foreground: Commons.Color.bar.text
  property color accent: foreground
  readonly property bool spanish: languageCode === "es"
  readonly property string today: ScheduleView.isoDate(currentTime)
  readonly property var preparedActivities: NikuData.prepareActivities(scheduleStatus.events)
  readonly property var preparedAssignments: NikuData.prepareAssignments(canvasStatus.assignments)
  readonly property var activityState: NikuData.activitySnapshotPrepared(preparedActivities, currentTime)
  readonly property var currentActivity: activityState.active.length ? activityState.active[0] : null
  readonly property var nextActivity: activityState.upcoming.length ? activityState.upcoming[0] : null
  readonly property var focusActivity: currentActivity || nextActivity
  readonly property bool inProgress: currentActivity !== null
  readonly property real nextStart: nextActivity ? nextActivity.start : -1
  readonly property var followingActivities: nextStart < 0 ? []
    : preparedActivities.filter(function(entry) { return entry.start >= root.nextStart })
  readonly property var rankedPriorities: NikuData.prioritiesFromPrepared(preparedAssignments, currentTime)
  property var priorities: []
  // Keep delegates alive when only countdown text changes.
  onRankedPrioritiesChanged: if (!NikuData.samePriorities(priorities, rankedPriorities)) priorities = rankedPriorities
  // Workload depends on the calendar day, not on the 30-second clock tick.
  readonly property var week: compact ? [] : NikuData.weekOverview(scheduleStatus.events, canvasStatus.assignments,
    new Date(today + "T12:00:00"))
  implicitHeight: header.height + Style.space(16) + body.implicitHeight

  signal compactRequested(bool compact)
  signal activityRequested(string activityId)
  signal calendarRequested()
  signal academicRequested()
  signal dragStarted(real sceneX, real sceneY)
  signal dragMoved(real sceneX, real sceneY)
  signal dragFinished()

  function tr(en, es) { return spanish ? es : en }
  function dateLabel(value) {
    var parts = value.split("-")
    var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    var distance = NikuData.dayDistance(date, currentTime)
    return distance === 0 ? tr("Today", "Hoy") : distance === 1 ? tr("Tomorrow", "Mañana")
      : I18n.shortDate(languageCode, value)
  }
  function dueLabel(entry) {
    if (entry.state === "overdue") return tr("OVERDUE", "VENCIDA")
    if (entry.state === "today") return tr("TODAY", "HOY")
    if (entry.state === "tomorrow") return tr("TOMORROW", "MAÑANA")
    return tr("IN ", "EN ") + entry.days + tr(" DAYS", " DÍAS")
  }
  function openAssignment(entry) {
    if (NikuData.isWebLink(entry.assignment.url)) Qt.openUrlExternally(entry.assignment.url)
    else academicRequested()
  }
  onCompactChanged: bodyScroll.contentY = 0

  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }
  component Caption: Label {
    font.pixelSize: Style.font.caption
    opacity: 0.65
  }
  component Heading: Label {
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0.7
    color: root.accent
  }

  Item {
    id: header
    width: parent.width
    height: Math.max(heading.implicitHeight, modeButton.implicitHeight)
    Column {
      id: heading
      anchors.left: parent.left
      anchors.right: modeButton.left
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(3)
      Label {
        width: parent.width
        text: "Niku  ≽(◉˕ ◉ ≼マ"
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Caption {
        width: parent.width
        text: I18n.longDate(root.languageCode, root.today)
        elide: Text.ElideRight
      }
    }
    MouseArea {
      id: headerDrag
      anchors.left: parent.left
      anchors.right: modeButton.left
      anchors.rightMargin: Style.space(8)
      height: parent.height
      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
      property point origin
      property bool moved: false
      onPressed: function(mouse) {
        origin = mapToItem(null, mouse.x, mouse.y)
        moved = false
        root.dragStarted(origin.x, origin.y)
      }
      onPositionChanged: function(mouse) {
        if (!pressed) return
        var position = mapToItem(null, mouse.x, mouse.y)
        if (Math.abs(position.x - origin.x) + Math.abs(position.y - origin.y) >= Qt.styleHints.startDragDistance)
          moved = true
        if (moved) root.dragMoved(position.x, position.y)
      }
      onReleased: root.dragFinished()
      onCanceled: root.dragFinished()
    }
    Button {
      id: modeButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.compact ? root.tr("Expand", "Ampliar") : root.tr("Compact", "Compacto")
      iconText: root.compact ? "\uf107" : "\uf106"
      tooltipText: root.compact ? root.tr("Show the daily and weekly summary", "Mostrar el resumen diario y semanal")
        : root.tr("Show only the essentials", "Mostrar solo lo esencial")
      foreground: root.foreground
      accent: root.accent
      fontSize: Style.font.caption
      horizontalPadding: Style.space(8)
      bordered: true
      onClicked: root.compactRequested(!root.compact)
    }
  }

  Flickable {
    id: bodyScroll
    anchors.top: header.bottom
    anchors.topMargin: Style.space(16)
    anchors.bottom: parent.bottom
    width: parent.width
    contentWidth: width
    contentHeight: body.implicitHeight
    clip: true
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: body
      width: parent.width
      spacing: Style.space(16)

      Rectangle {
        id: nowCard
        width: parent.width
        height: nowContent.implicitHeight + Style.space(20)
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, nowMouse.containsMouse ? 0.10 : 0.045)
        MouseArea {
          id: nowMouse
          anchors.fill: parent
          enabled: root.focusActivity !== null
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activityRequested(String(root.focusActivity.event.activityId || ""))
        }
        Column {
          id: nowContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(10)
          spacing: Style.space(6)
          Heading { text: root.currentActivity ? root.tr("IN PROGRESS", "EN CURSO") : root.tr("FREE TIME", "TIEMPO LIBRE") }
          Label {
            width: parent.width
            text: root.focusActivity ? String(root.focusActivity.event.title || "")
              : root.tr("No upcoming activities", "Sin actividades próximas")
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
          Caption {
            width: parent.width
            visible: root.focusActivity !== null
            text: root.focusActivity ? root.dateLabel(root.focusActivity.event.date) + " · "
              + root.focusActivity.event.startTime + " – " + root.focusActivity.event.endTime
              + (root.focusActivity.event.location ? " · " + root.focusActivity.event.location : "") : ""
            elide: Text.ElideRight
          }
          Label {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.currentActivity
              ? root.tr("Ends in ", "Termina en ") + NikuData.durationLabel(root.currentActivity.end - root.currentTime.getTime())
              : root.nextActivity
                ? root.tr("Your next activity starts in ", "Tu próxima actividad empieza en ")
                  + NikuData.durationLabel(root.nextActivity.start - root.currentTime.getTime())
                : root.tr("Enjoy a little breathing room.", "Un momento para respirar con calma.")
            opacity: 0.85
          }
          Rectangle {
            visible: root.currentActivity !== null
            width: parent.width
            height: Style.space(4)
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            Rectangle {
              width: parent.width * (root.currentActivity ? root.currentActivity.progress : 0)
              height: parent.height
              radius: height / 2
              color: root.accent
              Behavior on width { NumberAnimation { duration: Style.duration(180) } }
            }
          }
          Caption {
            visible: root.activityState.active.length > 1
            text: root.tr("Activities happening now: ", "Actividades en curso: ") + root.activityState.active.length
          }
        }
      }

      Column {
        visible: !root.compact && root.activityState.upcoming.length > (root.currentActivity ? 0 : 1)
        width: parent.width
        spacing: Style.space(8)
        Heading { text: root.tr("UP NEXT", "LO QUE VIENE") }
        Repeater {
          // The free-time card already presents the first upcoming activity.
          model: root.compact ? [] : root.followingActivities.slice(root.inProgress ? 0 : 1, root.inProgress ? 2 : 3)
          Rectangle {
            id: upcomingCard
            required property var modelData
            width: body.width
            height: upcomingText.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: nextMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07) : "transparent"
            Column {
              id: upcomingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(6)
              spacing: Style.space(3)
              Caption {
                width: parent.width
                text: root.dateLabel(upcomingCard.modelData.event.date) + " · " + upcomingCard.modelData.event.startTime
                elide: Text.ElideRight
              }
              Label {
                width: parent.width
                text: String(upcomingCard.modelData.event.title || "")
                elide: Text.ElideRight
              }
            }
            MouseArea {
              id: nextMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.activityRequested(String(upcomingCard.modelData.event.activityId || ""))
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(8)
        Heading { text: root.tr("PRIORITY DEADLINES", "ENTREGAS PRIORITARIAS") }
        Repeater {
          model: root.priorities.slice(0, root.compact ? 1 : 3)
          Rectangle {
            id: delivery
            required property var modelData
            readonly property bool overdue: modelData.state === "overdue"
            readonly property color accent: overdue ? Commons.Color.urgent : root.accent
            width: body.width
            height: deliveryContent.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Qt.rgba(accent.r, accent.g, accent.b, deliveryMouse.containsMouse ? 0.12 : 0.055)
            Rectangle {
              width: Style.space(3)
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(8)
              x: 0
              radius: width / 2
              color: delivery.accent
              opacity: delivery.modelData.state === "upcoming" ? 0.35 : 0.8
            }
            Column {
              id: deliveryContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(4)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Caption {
                  width: parent.width - dueBadge.implicitWidth - parent.spacing
                  text: String(delivery.modelData.assignment.course || "Canvas")
                  elide: Text.ElideRight
                }
                Heading {
                  id: dueBadge
                  text: root.dueLabel(delivery.modelData)
                  color: delivery.accent
                }
              }
              Label {
                width: parent.width
                text: String(delivery.modelData.assignment.title || "")
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.bold: true
              }
              Caption {
                width: parent.width
                text: Qt.formatDateTime(new Date(delivery.modelData.due), "dd/MM · HH:mm")
                  + (delivery.overdue ? " · " + root.tr("Not submitted", "Sin entregar") : " · "
                    + NikuData.remainingLabel(delivery.modelData.due, root.currentTime, root.languageCode))
                wrapMode: Text.WordWrap
              }
            }
            MouseArea {
              id: deliveryMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openAssignment(delivery.modelData)
            }
          }
        }
        Label {
          visible: root.priorities.length === 0
          width: parent.width
          text: root.canvasStatus.configured ? root.tr("No pending deadlines", "Sin entregas pendientes")
            : root.tr("Connect Canvas in the academic panel", "Conecta Canvas desde el panel académico")
          wrapMode: Text.WordWrap
          opacity: 0.65
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.academicRequested() }
        }
        Caption {
          visible: root.canvasStatus.stale === true
          width: parent.width
          text: root.tr("Offline · showing saved deadlines", "Sin conexión · entregas guardadas")
          wrapMode: Text.WordWrap
        }
      }

      Column {
        visible: !root.compact
        width: parent.width
        spacing: Style.space(8)
        Heading { text: root.tr("YOUR WEEK", "TU SEMANA") }
        Row {
          id: weekRow
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: root.compact ? [] : root.week
            Rectangle {
              id: dayCell
              required property var modelData
              required property int index
              width: (weekRow.width - weekRow.spacing * 6) / 7
              height: Style.space(72)
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                dayMouse.containsMouse ? 0.12 : modelData.date === root.today ? 0.07 : 0.02)
              Column {
                anchors.centerIn: parent
                width: parent.width - Style.space(6)
                spacing: Style.space(6)
                Caption {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: I18n.weekdayLabel(root.languageCode, dayCell.index).slice(0, 2)
                  opacity: dayCell.modelData.date === root.today ? 1 : 0.65
                }
                Item {
                  width: parent.width
                  height: Style.space(18)
                  Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(14)
                    height: Style.space(2) + Style.space(16) * dayCell.modelData.load
                    radius: Style.space(2)
                    color: root.accent
                    opacity: dayCell.modelData.count ? 0.7 : 0.15
                  }
                }
                Caption {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: dayCell.modelData.count + (dayCell.modelData.deadlines ? " •" : "")
                  opacity: dayCell.modelData.count || dayCell.modelData.deadlines ? 1 : 0.4
                }
              }
              MouseArea {
                id: dayMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.calendarRequested()
              }
            }
          }
        }
        Caption {
          width: parent.width
          text: root.tr("Activity load · • pending deadline", "Carga de actividades · • entrega pendiente")
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
