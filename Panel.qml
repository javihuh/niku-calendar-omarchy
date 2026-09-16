import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.javihuh.schedule"
  ipcTarget: "io.github.javihuh.schedule"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string helperPath: Qt.resolvedUrl("schedule.py").toString().replace(/^file:\/\//, "")
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  property var scheduleStatus: ({
    configured: false,
    itemCount: 0,
    todayCount: 0,
    events: []
  })
  readonly property bool configured: scheduleStatus.configured === true
  readonly property int todayCount: Number(scheduleStatus.todayCount || 0)
  readonly property var upcomingEvents: scheduleStatus.events || []
  readonly property var visibleEvents: root.first(root.upcomingEvents, 8)

  property string csvPath: ""
  property var previewData: null
  readonly property var previewItems: previewData && previewData.items ? previewData.items : []
  readonly property var previewErrors: previewData && previewData.errors ? previewData.errors : []
  readonly property var previewWarnings: previewData && previewData.warnings ? previewData.warnings : []
  readonly property bool previewReady: previewData && previewData.ok === true

  property string notice: ""
  property bool noticeIsError: false
  property bool refreshQueued: false
  property bool reminderQueued: false

  readonly property bool choosing: chooserProc.running
  readonly property bool previewing: previewProc.running
  readonly property bool importing: importProc.running
  readonly property bool busy: choosing || previewing || importing

  function first(values, count) {
    if (!values || !values.length) return []
    return values.slice(0, Math.min(values.length, count))
  }

  function parsedOutput(text) {
    var raw = String(text || "").trim()
    if (!raw) return null
    try {
      return JSON.parse(raw)
    } catch (error) {
      return null
    }
  }

  function errorText(data, fallback) {
    if (data && data.errors && data.errors.length > 0) {
      var issue = data.errors[0]
      var prefix = Number(issue.row || 0) > 0 ? "Fila " + issue.row + ": " : ""
      return prefix + String(issue.message || fallback)
    }
    return fallback
  }

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0)
      return decodeURIComponent(value.replace(/^file:\/\//, ""))
    return value
  }

  function refresh() {
    if (statusProc.running) {
      root.refreshQueued = true
      return
    }
    statusProc.command = ["python3", root.helperPath, "status", "--days", "120"]
    statusProc.running = true
  }

  function checkReminders() {
    if (reminderProc.running) {
      root.reminderQueued = true
      return
    }
    reminderProc.command = ["python3", root.helperPath, "remind"]
    reminderProc.running = true
  }

  function previewCsv() {
    var path = String(root.csvPath || "").trim()
    if (!path) {
      root.notice = "Selecciona o escribe la ruta de un archivo CSV."
      root.noticeIsError = true
      return
    }
    root.notice = ""
    root.noticeIsError = false
    root.previewData = null
    previewProc.command = ["python3", root.helperPath, "preview", path]
    previewProc.running = true
  }

  function chooseCsv() {
    if (root.busy) return
    root.notice = "Abriendo Yazi para seleccionar el CSV..."
    root.noticeIsError = false
    chooserProc.command = ["python3", root.helperPath, "choose"]
    root.close()
    Qt.callLater(function() { chooserProc.running = true })
  }

  function importCsv() {
    if (!root.previewReady || importProc.running) return
    root.notice = ""
    root.noticeIsError = false
    importProc.command = ["python3", root.helperPath, "import", String(root.csvPath).trim()]
    importProc.running = true
  }

  function open() {
    root.refresh()
    root.controller.show()
  }

  function close() {
    if (pathField.activeFocus) pathField.focus = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function eventDateLabel(isoDate) {
    var parts = String(isoDate || "").split("-")
    if (parts.length !== 3) return String(isoDate || "")
    var value = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0)
    var weekdays = ["dom", "lun", "mar", "mie", "jue", "vie", "sab"]
    var months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
    return weekdays[value.getDay()] + " " + value.getDate() + " " + months[value.getMonth()]
  }

  function recurrenceLabel(item) {
    var recurrence = String(item.recurrence || "")
    if (recurrence === "once") return "una vez"
    if (recurrence === "weekly") return "semanal"
    if (recurrence === "biweekly") return "quincenal"
    if (recurrence === "monthly") return "mensual"
    return recurrence
  }

  Component.onCompleted: Qt.callLater(function() {
    root.refresh()
    root.checkReminders()
  })

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: {
      root.refresh()
      root.checkReminders()
    }
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: statusErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var data = root.parsedOutput(statusOut.text)
      if (exitCode === 0 && data && data.ok === true) {
        root.scheduleStatus = data
      } else if (!root.notice) {
        root.notice = root.errorText(data, String(statusErr.text || "No se pudo leer el horario."))
        root.noticeIsError = true
      }
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: reminderProc
    stdout: StdioCollector {
      id: reminderOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: reminderErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var data = root.parsedOutput(reminderOut.text)
        console.warn("schedule reminders: "
          + root.errorText(data, String(reminderErr.text || "notification check failed")))
      }
      if (root.reminderQueued) {
        root.reminderQueued = false
        Qt.callLater(root.checkReminders)
      }
    }
  }

  Process {
    id: chooserProc
    stdout: StdioCollector {
      id: chooserOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: chooserErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var data = root.parsedOutput(chooserOut.text)
      root.open()
      if (exitCode === 0 && data && data.ok === true && data.path) {
        root.csvPath = String(data.path)
        pathField.text = root.csvPath
        root.notice = ""
        root.noticeIsError = false
        Qt.callLater(root.previewCsv)
      } else if (data && data.cancelled === true) {
        root.notice = "Selección cancelada."
        root.noticeIsError = false
      } else {
        root.notice = root.errorText(data, String(chooserErr.text || "No se pudo abrir el selector de archivos."))
        root.noticeIsError = true
      }
    }
  }

  Process {
    id: previewProc
    stdout: StdioCollector {
      id: previewOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: previewErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var data = root.parsedOutput(previewOut.text)
      root.previewData = data
      if (exitCode === 0 && data && data.ok === true) {
        root.notice = data.validCount + (data.validCount === 1 ? " actividad lista para importar." : " actividades listas para importar.")
        root.noticeIsError = false
      } else {
        root.notice = root.errorText(data, String(previewErr.text || "No se pudo validar el CSV."))
        root.noticeIsError = true
      }
    }
  }

  Process {
    id: importProc
    stdout: StdioCollector {
      id: importOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: importErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var data = root.parsedOutput(importOut.text)
      if (exitCode === 0 && data && data.ok === true) {
        root.scheduleStatus = data
        root.previewData = null
        root.notice = data.importedCount + (data.importedCount === 1 ? " actividad importada." : " actividades importadas.")
        root.noticeIsError = false
        Qt.callLater(root.checkReminders)
      } else {
        root.notice = root.errorText(data, String(importErr.text || "No se pudo importar el CSV."))
        root.noticeIsError = true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: pathField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: {
        if (!root.busy && String(root.csvPath).trim()) root.previewCsv()
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroll.width
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroText.implicitHeight, heroCount.implicitHeight)

            Text {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf073"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.displayLarge
            }

            Column {
              id: heroText
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: heroCount.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: "Horario recurrente"
                elide: Text.ElideRight
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                width: parent.width
                text: root.configured
                  ? root.scheduleStatus.itemCount + " ACTIVIDADES IMPORTADAS"
                  : "SIN HORARIO IMPORTADO"
                elide: Text.ElideRight
                color: Qt.darker(root.contentForeground, 1.45)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }
            }

            Text {
              id: heroCount
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.todayCount
              color: root.contentForeground
              opacity: root.configured ? 1 : 0.35
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          PanelSectionHeader {
            text: "PRÓXIMAS ACTIVIDADES"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Text {
            visible: !root.configured
            width: parent.width
            text: "Importa un CSV para ver aquí tu horario recurrente."
            wrapMode: Text.WordWrap
            color: Qt.darker(root.contentForeground, 1.35)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            visible: root.configured && root.visibleEvents.length === 0
            width: parent.width
            text: "No hay actividades durante los próximos 120 días."
            wrapMode: Text.WordWrap
            color: Qt.darker(root.contentForeground, 1.35)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.visibleEvents

            Rectangle {
              required property var modelData
              readonly property bool activeNow: modelData.active === true
              width: content.width
              implicitHeight: eventContent.implicitHeight + Style.space(14)
              radius: Style.cornerRadius
              color: activeNow
                ? Style.selectedFillFor(root.contentForeground, Color.accent)
                : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.055)
              border.width: activeNow ? Math.max(1, Style.normalBorderWidth) : 0
              border.color: Style.selectedStateColor(root.contentForeground, Color.accent)

              Column {
                id: eventContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(3)

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    id: eventDate
                    width: Style.space(86)
                    text: root.eventDateLabel(modelData.date).toUpperCase()
                    color: activeNow ? root.contentForeground : Qt.darker(root.contentForeground, 1.35)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    width: parent.width - eventDate.width - parent.spacing
                      - (activeStatus.visible ? activeStatus.implicitWidth + parent.spacing : 0)
                    text: modelData.title
                    elide: Text.ElideRight
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    id: activeStatus
                    visible: activeNow
                    text: "EN CLASE"
                    color: Style.selectedStateColor(root.contentForeground, Color.accent)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.8
                  }
                }

                Text {
                  width: parent.width
                  text: modelData.startTime + " - " + modelData.endTime
                    + (modelData.location ? "  ·  " + modelData.location : "")
                  elide: Text.ElideRight
                  color: activeNow ? root.contentForeground : Qt.darker(root.contentForeground, 1.45)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          Text {
            visible: root.upcomingEvents.length > root.visibleEvents.length
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "+ " + (root.upcomingEvents.length - root.visibleEvents.length) + " actividades posteriores"
            color: Qt.darker(root.contentForeground, 1.55)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSeparator { foreground: root.contentForeground }

          PanelSectionHeader {
            text: root.configured ? "REEMPLAZAR HORARIO DESDE CSV" : "IMPORTAR HORARIO DESDE CSV"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: pathField
              width: parent.width - browseButton.width - parent.spacing
              placeholderText: "/ruta/al/horario.csv"
              text: root.csvPath
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              activeFocusOnTab: false
              onTextChanged: root.csvPath = text
              onAccepted: root.previewCsv()
              Keys.onEscapePressed: {
                focus = false
                keyCatcher.forceActiveFocus()
              }
            }

            Button {
              id: browseButton
              text: root.choosing ? "Abierto..." : "Buscar"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              enabled: !root.busy
              opacity: enabled ? 1 : 0.45
              onClicked: root.chooseCsv()
            }
          }

          Button {
            width: parent.width
            text: root.previewing ? "Validando..." : "Previsualizar CSV"
            iconText: root.previewing ? "\uf110" : "\uf06e"
            iconSpinning: root.previewing
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            bordered: true
            enabled: !root.busy && String(root.csvPath).trim() !== ""
            opacity: enabled ? 1 : 0.45
            onClicked: root.previewCsv()
          }

          Text {
            visible: root.notice !== ""
            width: parent.width
            text: root.notice
            wrapMode: Text.WordWrap
            color: root.noticeIsError ? Color.urgent : root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.first(root.previewErrors, 5)

            Text {
              required property var modelData
              width: content.width
              text: (Number(modelData.row || 0) > 0 ? "Fila " + modelData.row + ": " : "") + modelData.message
              wrapMode: Text.WordWrap
              color: Color.urgent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Repeater {
            model: root.first(root.previewWarnings, 3)

            Text {
              required property var modelData
              width: content.width
              text: String(modelData)
              wrapMode: Text.WordWrap
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Column {
            visible: root.previewItems.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "VISTA PREVIA"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Repeater {
              model: root.first(root.previewItems, 6)

              Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(8)

                Text {
                  width: Style.space(88)
                  text: modelData.startTime + " - " + modelData.endTime
                  color: Qt.darker(root.contentForeground, 1.35)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  width: parent.width - Style.space(96)
                  text: modelData.title + "  ·  " + root.recurrenceLabel(modelData)
                  elide: Text.ElideRight
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Text {
              visible: root.previewItems.length > 6
              width: parent.width
              text: "+ " + (root.previewItems.length - 6) + " filas"
              horizontalAlignment: Text.AlignHCenter
              color: Qt.darker(root.contentForeground, 1.55)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Button {
            visible: root.previewItems.length > 0
            width: parent.width
            text: root.importing
              ? "Importando..."
              : (root.configured ? "Importar y reemplazar horario" : "Importar horario")
            iconText: root.importing ? "\uf110" : "\uf56f"
            iconSpinning: root.importing
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            bordered: true
            active: root.previewReady
            enabled: root.previewReady && !root.busy
            opacity: enabled ? 1 : 0.45
            onClicked: root.importCsv()
          }

          Text {
            width: parent.width
            text: "Columnas: titulo, dia_semana, dia_mes, hora_inicio, hora_fin, repeticion, desde, hasta, ubicacion y descripcion."
            wrapMode: Text.WordWrap
            color: Qt.darker(root.contentForeground, 1.65)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
