import QtQuick
import qs.Commons
import qs.Ui
import "I18n.js" as I18n

Item {
  id: root

  property var items: []
  property string scheduleTitle: "Schedule"
  property string languageCode: "en"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool busy: false
  property string notice: ""
  property bool noticeIsError: false
  property int selectedIndex: items.length > 0 ? 0 : -1

  signal backRequested()
  signal addRequested()
  signal activityRequested(string activityId)

  function recurrenceLabel(item) {
    return I18n.recurrenceLabel(languageCode, item.recurrence)
  }

  function normalizeSelection() {
    if (items.length === 0) selectedIndex = -1
    else selectedIndex = Math.max(0, Math.min(selectedIndex, items.length - 1))
  }

  function moveSelection(delta) {
    if (items.length === 0 || delta === 0) return
    selectedIndex = Math.max(0, Math.min(items.length - 1, selectedIndex + delta))
    Qt.callLater(revealSelection)
  }

  function revealSelection() {
    var row = activityRepeater.itemAt(selectedIndex)
    if (!row) return
    var top = activityList.y + row.y
    var bottom = top + row.height
    if (top < manageScroll.contentY)
      manageScroll.contentY = Math.max(0, top)
    else if (bottom > manageScroll.contentY + manageScroll.height)
      manageScroll.contentY = Math.min(manageScroll.contentHeight - manageScroll.height, bottom - manageScroll.height)
  }

  function activateSelection() {
    if (selectedIndex < 0 || selectedIndex >= items.length) return
    activityRequested(String(items[selectedIndex].id || ""))
  }

  onItemsChanged: normalizeSelection()
  onVisibleChanged: if (visible) normalizeSelection()

  Flickable {
    id: manageScroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: manageContent.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: manageContent
      width: manageScroll.width
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

        Column {
          width: parent.width - backButton.width - addButton.width - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: I18n.t(root.languageCode, "manager.title")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.scheduleTitle
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        PanelActionButton {
          id: addButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf067"
          tooltipText: I18n.t(root.languageCode, "common.addActivity")
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: !root.busy
          onClicked: root.addRequested()
        }
      }

      PanelSeparator { foreground: root.foreground }

      Text {
        textFormat: Text.PlainText
        visible: root.items.length === 0
        width: parent.width
        text: I18n.t(root.languageCode, "manager.empty")
        wrapMode: Text.WordWrap
        color: Qt.darker(root.foreground, 1.35)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Button {
        visible: root.items.length === 0
        width: parent.width
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

      Column {
        id: activityList
        visible: root.items.length > 0
        width: parent.width
        spacing: Style.spacing.md

        PanelSectionHeader {
          text: I18n.plural(root.languageCode, "count.activities", root.items.length)
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          id: activityRepeater
          model: root.items

          Rectangle {
            id: activityRow
            required property var modelData
            required property int index
            readonly property bool selected: index === root.selectedIndex
            width: activityList.width
            implicitHeight: rowContent.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: selected
              ? Style.selectedFillFor(root.foreground, Color.accent)
              : (rowMouse.containsMouse
                ? Style.hoverFillFor(root.foreground, Color.accent)
                : Style.normalFillFor(root.foreground, Color.accent))
            border.width: selected ? Math.max(1, Style.normalBorderWidth) : 0
            border.color: Style.selectedStateColor(root.foreground, Color.accent)

            Column {
              id: rowContent
              anchors.left: parent.left
              anchors.right: chevron.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(11)
              anchors.rightMargin: Style.space(8)
              spacing: Style.spacing.xs

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: String(activityRow.modelData.title || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.recurrenceLabel(activityRow.modelData) + " · "
                  + String(activityRow.modelData.startTime || "") + " - "
                  + String(activityRow.modelData.endTime || "")
                color: Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                visible: String(activityRow.modelData.location || "") !== ""
                width: parent.width
                text: String(activityRow.modelData.location || "")
                color: Qt.darker(root.foreground, 1.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Text {
              id: chevron
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf054"
              color: activityRow.selected ? root.foreground : Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: !root.busy
              onClicked: {
                root.selectedIndex = activityRow.index
                root.activityRequested(String(activityRow.modelData.id || ""))
              }
            }
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
    }
  }
}
