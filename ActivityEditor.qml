import QtQuick
import QtQml.Models
import qs.Commons
import qs.Ui
import "I18n.js" as I18n

FocusScope {
  id: root

  enabled: !busy

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool busy: false
  property string notice: ""
  property bool noticeIsError: false
  property bool creating: true
  property var activities: []
  property string originalTitle: ""
  property string languageCode: "en"
  readonly property bool inputActive: activeFocus
  readonly property int linkScopeTargetCount: targetCountForTitle(titleField.text)
  readonly property bool requiredReady: String(titleField.text).trim() !== ""
    && String(startDateField.text).trim() !== ""
    && String(startTimeField.text).trim() !== ""
    && String(endTimeField.text).trim() !== ""

  signal saveRequested(var activity, string linkScope)
  signal cancelRequested()
  signal focusReleaseRequested()

  function monthdayOptions() {
    var options = [{ value: "-1", label: I18n.t(languageCode, "editor.lastMonthDay") }]
    for (var day = 1; day <= 31; day++)
      options.push({ value: String(day), label: String(day) })
    return options
  }

  function weekdayForDate(value) {
    var parts = String(value || "").split("-")
    if (parts.length !== 3) return 0
    var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0)
    return (date.getDay() + 6) % 7
  }

  function matchingTitleCount(value) {
    var titleKey = String(value || "").trim().toLowerCase()
    if (!titleKey) return 0
    var count = 0
    for (var index = 0; index < activities.length; index++) {
      if (String(activities[index].title || "").trim().toLowerCase() === titleKey)
        count += 1
    }
    return count
  }

  function targetCountForTitle(value) {
    var titleKey = String(value || "").trim().toLowerCase()
    if (!titleKey) return 0
    var originalKey = String(originalTitle || "").trim().toLowerCase()
    return matchingTitleCount(value) + (creating || titleKey !== originalKey ? 1 : 0)
  }

  function beginCreate(defaultDate) {
    creating = true
    originalTitle = ""
    titleField.text = ""
    recurrenceDropdown.value = "weekly"
    startDateField.text = defaultDate
    endDateField.text = ""
    startTimeField.text = "09:00"
    endTimeField.text = "10:00"
    weekdayDropdown.value = String(weekdayForDate(defaultDate))
    monthdayDropdown.value = String(Number(String(defaultDate).split("-")[2]) || 1)
    locationField.text = ""
    notesField.text = ""
    linksModel.clear()
    linkScopeDropdown.value = "activity"
  }

  function beginEdit(activity) {
    creating = false
    originalTitle = String(activity.title || "")
    titleField.text = String(activity.title || "")
    recurrenceDropdown.value = String(activity.recurrence || "weekly")
    startDateField.text = String(activity.startDate || "")
    endDateField.text = String(activity.endDate || "")
    startTimeField.text = String(activity.startTime || "")
    endTimeField.text = String(activity.endTime || "")
    weekdayDropdown.value = String(activity.weekday === null || activity.weekday === undefined ? 0 : activity.weekday)
    monthdayDropdown.value = String(activity.monthday === null || activity.monthday === undefined ? 1 : activity.monthday)
    locationField.text = String(activity.location || "")
    notesField.text = String(activity.notes || "")
    linksModel.clear()
    var links = activity.links || []
    for (var index = 0; index < links.length; index++) {
      linksModel.append({
        name: String(links[index].label || ""),
        address: String(links[index].url || "")
      })
    }
    linkScopeDropdown.value = "activity"
  }

  function focusFirst() {
    titleField.forceActiveFocus()
  }

  function releaseInput(event) {
    if (event) event.accepted = true
    root.focusReleaseRequested()
  }

  function addLink() {
    if (linksModel.count >= 10) return
    linksModel.append({ name: "", address: "" })
    var newIndex = linksModel.count - 1
    Qt.callLater(function() {
      var row = linksRepeater.itemAt(newIndex)
      if (row) row.focusLabel()
    })
  }

  function activityPayload() {
    var links = []
    for (var index = 0; index < linksModel.count; index++) {
      var link = linksModel.get(index)
      var label = String(link.name || "").trim()
      var url = String(link.address || "").trim()
      if (label !== "" || url !== "") links.push({ label: label, url: url })
    }
    var recurrence = recurrenceDropdown.value
    return {
      title: String(titleField.text).trim(),
      weekday: recurrence === "weekly" || recurrence === "biweekly"
        ? Number(weekdayDropdown.value) : null,
      monthday: recurrence === "monthly" ? Number(monthdayDropdown.value) : null,
      startTime: String(startTimeField.text).trim(),
      endTime: String(endTimeField.text).trim(),
      recurrence: recurrence,
      startDate: String(startDateField.text).trim(),
      endDate: String(endDateField.text).trim() || null,
      location: String(locationField.text).trim(),
      notes: String(notesField.text).trim(),
      links: links
    }
  }

  Keys.onEscapePressed: function(event) {
    root.cancelRequested()
    event.accepted = true
  }

  ListModel { id: linksModel }

  Flickable {
    id: editorScroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: editorContent.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: editorContent
      width: editorScroll.width
      spacing: Style.space(12)

      Row {
        width: parent.width
        spacing: Style.spacing.lg

        PanelActionButton {
          id: backButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf060"
          tooltipText: I18n.t(root.languageCode, "common.cancel")
          foreground: root.foreground
          fontFamily: root.fontFamily
          focusable: true
          enabled: !root.busy
          onClicked: root.cancelRequested()
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width - backButton.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          text: root.creating
            ? I18n.t(root.languageCode, "editor.newActivity")
            : I18n.t(root.languageCode, "editor.editActivity")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }
      }

      PanelSeparator { foreground: root.foreground }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        Text {
          textFormat: Text.PlainText
          text: I18n.t(root.languageCode, "editor.title")
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        TextField {
          id: titleField
          width: parent.width
          placeholderText: I18n.t(root.languageCode, "editor.activityName")
          foreground: root.foreground
          font.family: root.fontFamily
          maximumLength: 200
          activeFocusOnTab: true
          Keys.onEscapePressed: function(event) { root.releaseInput(event) }
        }
      }

      Dropdown {
        id: recurrenceDropdown
        width: parent.width
        label: I18n.t(root.languageCode, "editor.recurrence")
        value: "weekly"
        options: I18n.recurrenceOptions(root.languageCode)
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Dropdown {
        id: weekdayDropdown
        visible: recurrenceDropdown.value === "weekly" || recurrenceDropdown.value === "biweekly"
        width: parent.width
        label: I18n.t(root.languageCode, "editor.weekday")
        value: "0"
        options: I18n.weekdayOptions(root.languageCode)
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Dropdown {
        id: monthdayDropdown
        visible: recurrenceDropdown.value === "monthly"
        width: parent.width
        label: I18n.t(root.languageCode, "editor.monthday")
        value: "1"
        options: root.monthdayOptions()
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Row {
        width: parent.width
        spacing: Style.spacing.lg

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap

          Text {
            textFormat: Text.PlainText
            text: I18n.t(root.languageCode, "editor.startDate")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          TextField {
            id: startDateField
            width: parent.width
            placeholderText: I18n.t(root.languageCode, "date.inputPlaceholder")
            foreground: root.foreground
            font.family: root.fontFamily
            maximumLength: 10
            activeFocusOnTab: true
            inputMethodHints: Qt.ImhDate
            Keys.onEscapePressed: function(event) { root.releaseInput(event) }
          }
        }

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap

          Text {
            textFormat: Text.PlainText
            text: I18n.t(root.languageCode, "editor.endDate")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          TextField {
            id: endDateField
            width: parent.width
            placeholderText: I18n.t(root.languageCode, "common.optional")
            foreground: root.foreground
            font.family: root.fontFamily
            maximumLength: 10
            activeFocusOnTab: true
            inputMethodHints: Qt.ImhDate
            Keys.onEscapePressed: function(event) { root.releaseInput(event) }
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.lg

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap

          Text {
            textFormat: Text.PlainText
            text: I18n.t(root.languageCode, "editor.startTime")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          TextField {
            id: startTimeField
            width: parent.width
            placeholderText: "HH:MM"
            foreground: root.foreground
            font.family: root.fontFamily
            maximumLength: 5
            activeFocusOnTab: true
            inputMethodHints: Qt.ImhTime
            Keys.onEscapePressed: function(event) { root.releaseInput(event) }
          }
        }

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap

          Text {
            textFormat: Text.PlainText
            text: I18n.t(root.languageCode, "editor.endTime")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          TextField {
            id: endTimeField
            width: parent.width
            placeholderText: "HH:MM"
            foreground: root.foreground
            font.family: root.fontFamily
            maximumLength: 5
            activeFocusOnTab: true
            inputMethodHints: Qt.ImhTime
            Keys.onEscapePressed: function(event) { root.releaseInput(event) }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        Text {
          textFormat: Text.PlainText
          text: I18n.t(root.languageCode, "editor.location")
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        TextField {
          id: locationField
          width: parent.width
          placeholderText: I18n.t(root.languageCode, "common.optional")
          foreground: root.foreground
          font.family: root.fontFamily
          maximumLength: 300
          activeFocusOnTab: true
          Keys.onEscapePressed: function(event) { root.releaseInput(event) }
        }
      }

      MultilineField {
        id: notesField
        width: parent.width
        label: I18n.t(root.languageCode, "editor.notes")
        placeholderText: I18n.t(root.languageCode, "editor.addContext")
        maximumLength: 4000
        foreground: root.foreground
        fontFamily: root.fontFamily
        onEscapePressed: root.focusReleaseRequested()
      }

      PanelSeparator { foreground: root.foreground }

      Row {
        width: parent.width

        PanelSectionHeader {
          width: parent.width - linkCount.implicitWidth
          text: I18n.t(root.languageCode, "common.links")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          id: linkCount
          textFormat: Text.PlainText
          text: linksModel.count + "/10"
          color: Qt.darker(root.foreground, 1.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: linksModel.count === 0
        width: parent.width
        text: I18n.t(root.languageCode, "editor.linkHelp")
        wrapMode: Text.WordWrap
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Dropdown {
        id: linkScopeDropdown
        width: parent.width
        label: I18n.t(root.languageCode, "editor.applyLinks")
        value: "activity"
        options: [
          {
            value: "activity",
            label: I18n.t(root.languageCode, "editor.onlyThisSlot")
          },
          {
            value: "same-title",
            label: root.linkScopeTargetCount > 0
              ? I18n.t(root.languageCode, "editor.allSameNameCount", {
                  count: root.linkScopeTargetCount
                })
              : I18n.t(root.languageCode, "editor.allSameName")
          }
        ]
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: linkScopeDropdown.value === "same-title"
          ? (root.linkScopeTargetCount > 1
            ? I18n.t(root.languageCode, "editor.linkScopeAll", {
                count: root.linkScopeTargetCount,
                title: String(titleField.text).trim()
              })
            : I18n.t(root.languageCode, "editor.linkScopeSingle"))
          : I18n.t(root.languageCode, "editor.linkScopeOnly")
        wrapMode: Text.WordWrap
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        id: linksRepeater
        model: linksModel

        delegate: Column {
          id: linkRow
          required property int index
          required property string name
          required property string address
          width: editorContent.width
          spacing: Style.spacing.labelGap

          function focusLabel() { linkLabelField.forceActiveFocus() }

          Text {
            textFormat: Text.PlainText
            text: I18n.t(root.languageCode, "editor.link", {
              number: linkRow.index + 1
            })
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Row {
            width: parent.width
            spacing: Style.spacing.md

            TextField {
              id: linkLabelField
              width: Math.max(Style.space(90), (parent.width - removeLink.width - parent.spacing * 2) * 0.32)
              text: linkRow.name
              placeholderText: I18n.t(root.languageCode, "editor.linkLabel")
              foreground: root.foreground
              font.family: root.fontFamily
              maximumLength: 80
              activeFocusOnTab: true
              onTextEdited: linksModel.setProperty(linkRow.index, "name", text)
              Keys.onEscapePressed: function(event) { root.releaseInput(event) }
            }

            TextField {
              width: parent.width - linkLabelField.width - removeLink.width - parent.spacing * 2
              text: linkRow.address
              placeholderText: "https://..."
              foreground: root.foreground
              font.family: root.fontFamily
              maximumLength: 2048
              activeFocusOnTab: true
              inputMethodHints: Qt.ImhUrlCharactersOnly
              onTextEdited: linksModel.setProperty(linkRow.index, "address", text)
              Keys.onEscapePressed: function(event) { root.releaseInput(event) }
            }

            PanelActionButton {
              id: removeLink
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\uf2ed"
              tooltipText: I18n.t(root.languageCode, "editor.removeLink")
              foreground: root.foreground
              hoverColor: Color.urgent
              fontFamily: root.fontFamily
              focusable: true
              enabled: !root.busy
              onClicked: linksModel.remove(linkRow.index)
            }
          }
        }
      }

      Button {
        visible: linksModel.count < 10
        width: parent.width
        text: I18n.t(root.languageCode, "editor.addLink")
        iconText: "\uf0c1"
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        focusable: true
        enabled: !root.busy
        opacity: enabled ? 1 : 0.45
        onClicked: root.addLink()
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
        width: parent.width
        spacing: Style.spacing.lg

        Button {
          width: (parent.width - parent.spacing) / 2
          text: I18n.t(root.languageCode, "common.cancel")
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          focusable: true
          enabled: !root.busy
          onClicked: root.cancelRequested()
        }

        Button {
          width: (parent.width - parent.spacing) / 2
          text: root.busy
            ? I18n.t(root.languageCode, "common.saving")
            : I18n.t(root.languageCode, "common.save")
          iconText: root.busy ? "\uf110" : "\uf0c7"
          iconSpinning: root.busy
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          active: true
          focusable: true
          enabled: root.requiredReady && !root.busy
          opacity: enabled ? 1 : 0.45
          onClicked: root.saveRequested(
            root.activityPayload(),
            linkScopeDropdown.value)
        }
      }
    }
  }
}
