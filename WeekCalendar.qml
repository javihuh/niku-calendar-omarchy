import QtQuick
import qs.Commons
import qs.Commons as Commons
import "ScheduleView.js" as ScheduleView
import "I18n.js" as I18n

Item {
  id: root
  property var events: []
  property string weekStart: ""
  property string languageCode: "en"
  property date currentTime: new Date()
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property bool busy: false
  readonly property var dates: ScheduleView.weekDates(weekStart)
  readonly property real gutter: Style.space(48)
  readonly property real hourHeight: Style.space(54)
  readonly property real dayWidth: (width - gutter) / 7
  readonly property string today: ScheduleView.isoDate(currentTime)
  signal activityRequested(string activityId)

  function openEvent(event) {
    if (busy) return
    if (event.source === "canvas") {
      if (event.url) Qt.openUrlExternally(event.url)
    } else activityRequested(String(event.activityId || ""))
  }

  Row {
    id: header
    x: root.gutter
    width: root.width - x
    height: Style.space(42)
    Repeater {
      model: root.dates
      Rectangle {
        required property string modelData
        required property int index
        width: root.dayWidth
        height: header.height
        color: modelData === root.today ? Style.selectedFillFor(root.foreground, Commons.Color.accent) : "transparent"
        Text {
          anchors.centerIn: parent
          width: parent.width - Style.space(4)
          textFormat: Text.PlainText
          text: I18n.weekdayLabel(root.languageCode, index).slice(0, 3) + " " + modelData.slice(8)
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
  }

  Flickable {
    id: allDayArea
    anchors.top: header.bottom
    x: root.gutter
    width: parent.width - x
    height: Math.min(Style.space(90), allDayRow.implicitHeight)
    contentWidth: width
    contentHeight: allDayRow.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Row {
    id: allDayRow
    Repeater {
      model: root.dates
      Column {
        id: allDayColumn
        required property string modelData
        width: root.dayWidth
        Repeater {
          model: root.events.filter(function(e) { return e.allDay && e.date === allDayColumn.modelData })
          Rectangle {
            required property var modelData
            width: allDayColumn.width - 2
            height: Style.space(24)
            color: Style.selectedFillFor(root.foreground, Commons.Color.accent)
            Text {
              anchors.fill: parent
              anchors.margins: 3
              textFormat: Text.PlainText
              text: modelData.title
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            MouseArea { anchors.fill: parent; onClicked: root.openEvent(modelData) }
          }
        }
      }
    }
    }
  }

  Flickable {
    id: hours
    anchors.top: allDayArea.bottom
    anchors.bottom: parent.bottom
    width: parent.width
    clip: true
    contentWidth: width
    contentHeight: root.hourHeight * 24
    boundsBehavior: Flickable.StopAtBounds
    Component.onCompleted: contentY = Math.min(Math.max(0, contentHeight - height), root.hourHeight * 7)

    Repeater {
      model: 24
      Item {
        required property int index
        y: index * root.hourHeight
        width: hours.width
        height: root.hourHeight
        Text {
          textFormat: Text.PlainText
          text: String(index).padStart(2, "0") + ":00"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Rectangle {
          x: root.gutter; width: parent.width - x; height: 1
          color: root.foreground; opacity: 0.12
        }
      }
    }
    Repeater {
      model: root.dates
      Item {
        id: day
        required property string modelData
        required property int index
        x: root.gutter + index * root.dayWidth
        width: root.dayWidth
        height: hours.contentHeight
        Rectangle { width: 1; height: parent.height; color: root.foreground; opacity: 0.1 }
        Repeater {
          model: ScheduleView.layoutDay(root.events, day.modelData)
          Rectangle {
            id: block
            required property var modelData
            readonly property var event: modelData.event
            readonly property string stateNow: ScheduleView.temporalState(event, root.currentTime)
            x: modelData.column * day.width / modelData.columns + 2
            y: modelData.start * root.hourHeight / 60
            width: Math.max(1, day.width / modelData.columns - 4)
            height: Math.max(1, (modelData.end - modelData.start) * root.hourHeight / 60 - 2)
            radius: Style.space(4)
            color: Style.selectedFillFor(root.foreground, Commons.Color.accent)
            opacity: stateNow === "occurred" ? 0.55 : 1
            border.width: stateNow === "active" || event.marker ? 1 : 0
            border.color: Commons.Color.accent
            clip: true
            Text {
              anchors.fill: parent
              anchors.margins: Style.space(4)
              textFormat: Text.PlainText
              text: (block.event.marker ? "◇ " : "") + block.event.startTime + " " + block.event.title
              wrapMode: Text.Wrap
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openEvent(block.event)
            }
          }
        }
        Rectangle {
          visible: day.modelData === root.today
          y: (root.currentTime.getHours() * 60 + root.currentTime.getMinutes()) * root.hourHeight / 60
          width: parent.width
          height: 2
          color: Commons.Color.accent
        }
      }
    }
  }
}
