import QtQuick
import qs.Commons
import qs.Ui
import "I18n.js" as I18n

Item {
  id: root

  property var activity: ({})
  property string languageCode: "en"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool busy: false
  property string notice: ""
  property bool noticeIsError: false
  readonly property bool hasActivity: !!activity && String(activity.id || "") !== ""

  signal backRequested()
  signal editRequested()
  signal deleteRequested()

  function recurrenceLabel(value) {
    return I18n.recurrenceLabel(languageCode, value)
  }

  function weekdayLabel(value) {
    return I18n.weekdayLabel(languageCode, value)
  }

  function dateLabel(value) {
    return I18n.longDate(languageCode, value)
  }

  function recurrenceDetail() {
    var recurrence = String(activity.recurrence || "")
    if (recurrence === "weekly" || recurrence === "biweekly")
      return recurrenceLabel(recurrence) + " · " + weekdayLabel(activity.weekday)
    if (recurrence === "monthly")
      return recurrenceLabel(recurrence) + " · "
        + (Number(activity.monthday) === -1
          ? I18n.t(languageCode, "date.lastMonthDay")
          : I18n.t(languageCode, "date.monthDay", { day: activity.monthday }))
    return recurrenceLabel(recurrence)
  }

  function dateRange() {
    var start = dateLabel(activity.startDate)
    var end = activity.endDate
      ? dateLabel(activity.endDate)
      : I18n.t(languageCode, "date.noEnd")
    if (String(activity.recurrence || "") === "once") return start
    return I18n.t(languageCode, "date.from", { start: start, end: end })
  }

  Flickable {
    id: detailsScroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: detailsContent.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: detailsContent
      width: detailsScroll.width
      spacing: Style.space(12)

      Row {
        width: parent.width
        spacing: Style.spacing.lg

        PanelActionButton {
          id: backButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf060"
          tooltipText: I18n.t(root.languageCode, "common.back")
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: !root.busy
          onClicked: root.backRequested()
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width - backButton.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          text: root.hasActivity
            ? String(root.activity.title || "")
            : I18n.t(root.languageCode, "common.activity")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.WordWrap
        }
      }

      PanelSeparator { foreground: root.foreground }

      Text {
        textFormat: Text.PlainText
        visible: !root.hasActivity
        width: parent.width
        text: I18n.t(root.languageCode, "details.unavailable")
        wrapMode: Text.WordWrap
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      BorderSurface {
        visible: root.hasActivity
        width: parent.width
        implicitHeight: summaryContent.implicitHeight + Style.space(20)
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        Column {
          id: summaryContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.spacing.md

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.recurrenceDetail()
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.dateRange()
            color: Qt.darker(root.foreground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: String(root.activity.startTime || "") + " - " + String(root.activity.endTime || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      Column {
        visible: root.hasActivity
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          text: I18n.t(root.languageCode, "common.location")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: String(root.activity.location || "")
            || I18n.t(root.languageCode, "details.noLocation")
          color: String(root.activity.location || "") === ""
            ? Qt.darker(root.foreground, 1.45) : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
      }

      Column {
        visible: root.hasActivity
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          text: I18n.t(root.languageCode, "common.notes")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: String(root.activity.notes || "")
            || I18n.t(root.languageCode, "details.noNotes")
          color: String(root.activity.notes || "") === ""
            ? Qt.darker(root.foreground, 1.45) : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
      }

      Column {
        visible: root.hasActivity && (root.activity.links || []).length > 0
        width: parent.width
        spacing: Style.spacing.md

        PanelSectionHeader {
          text: I18n.t(root.languageCode, "common.links")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          model: root.activity.links || []

          Button {
            required property var modelData
            width: detailsContent.width
            text: String(modelData.label || "")
            iconText: "\uf35d"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            leftAlign: true
            onClicked: Qt.openUrlExternally(String(modelData.url || ""))
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.notice !== ""
        width: parent.width
        text: root.notice
        wrapMode: Text.WordWrap
        color: root.noticeIsError ? Color.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        visible: root.hasActivity
        width: parent.width
        spacing: Style.spacing.lg

        Button {
          width: (parent.width - parent.spacing) / 2
          text: I18n.t(root.languageCode, "details.editSeries")
          iconText: "\uf044"
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          enabled: !root.busy
          opacity: enabled ? 1 : 0.45
          onClicked: root.editRequested()
        }

        Button {
          width: (parent.width - parent.spacing) / 2
          text: I18n.t(root.languageCode, "common.delete")
          iconText: "\uf2ed"
          foreground: root.foreground
          accent: Color.urgent
          fontFamily: root.fontFamily
          bordered: true
          enabled: !root.busy
          opacity: enabled ? 1 : 0.45
          onClicked: root.deleteRequested()
        }
      }
    }
  }
}
