import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "NikuData.js" as NikuData

Item {
  id: root
  property string languageCode: "en"
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property string section: "assignments"
  property string courseId: ""
  property string assignmentFilter: "pending"
  property var courses: []
  property var snapshot: ({})
  property string expandedId: ""
  property bool forceNext: false
  property bool loading: false
  property date currentTime: new Date()
  readonly property string helper: Qt.resolvedUrl("canvas.py").toString().replace(/^file:\/\//, "")
  readonly property string queryKey: section + ":" + (section === "courses" ? "" : courseId)
  readonly property bool inputActive: coursePicker.popupOpen || statusPicker.popupOpen
  readonly property var shownItems: {
    var now = currentTime.getTime()
    return (snapshot.items || []).filter(function(item) {
    if (root.section !== "assignments" || root.assignmentFilter === "all") return true
    if (root.assignmentFilter === "submitted") return item.submitted === true
    if (item.excused) return false
    if (root.assignmentFilter === "overdue")
      return !item.submitted && item.dueAt && new Date(item.dueAt).getTime() < now
    return !item.submitted
    })
  }
  signal calendarRequested()

  function tr(en, es) { return languageCode === "es" ? es : en }
  function parse(text) { try { return JSON.parse(text) } catch (e) { return null } }
  function refresh() { forceNext = true; requestTimer.restart() }
  function begin() {
    if (resourceProc.running) return
    snapshot = ({})
    expandedId = ""
    loading = true
    resourceProc.key = queryKey
    resourceProc.selectedSection = section
    resourceProc.selectedCourse = section === "courses" ? "" : courseId
    resourceProc.forced = forceNext
    forceNext = false
    resourceProc.cached = true
    resourceProc.run()
  }
  function dateLabel(value) {
    if (!value) return tr("No due date", "Sin fecha límite")
    var date = new Date(value)
    return isNaN(date.getTime()) ? "" : Qt.formatDateTime(date, "dd/MM/yyyy HH:mm")
  }
  function subtitle(item) {
    if (section === "grades") {
      if (item.excused) return tr("Excused", "Eximida")
      var grade = item.grade !== null && item.grade !== undefined ? String(item.grade) : ""
      var score = item.score !== null && item.score !== undefined
        ? String(item.score) + (item.points !== null && item.points !== undefined ? " / " + item.points : "") : ""
      return [grade, score].filter(function(v) { return v !== "" }).join(" · ") || tr("Not published", "Sin publicar")
    }
    if (section === "assignments") {
      var state = item.excused ? tr("Excused", "Eximida") : item.submitted ? tr("Submitted", "Entregada")
        : item.dueAt && new Date(item.dueAt).getTime() < currentTime.getTime() ? tr("Overdue", "Vencida") : tr("Pending", "Pendiente")
      return [item.course, dateLabel(item.dueAt), state,
        !item.submitted && item.dueAt ? NikuData.remainingLabel(item.dueAt, currentTime, languageCode) : "",
        item.markedComplete ? tr("Marked complete in planner", "Marcada como completada en agenda") : ""].filter(Boolean).join(" · ")
    }
    var course = courses.find(function(c) { return c.id === item.courseId })
    return item.subtitle || (item.date ? (course ? course.title + " · " : "") + dateLabel(item.date) : "")
  }

  onQueryKeyChanged: {
    snapshot = ({})
    loading = true
    requestTimer.restart()
  }
  Component.onCompleted: {
    coursesProc.cached = true
    coursesProc.run()
    requestTimer.restart()
  }
  Timer { id: requestTimer; interval: 0; onTriggered: root.begin() }
  Timer { interval: 60000; running: root.visible; repeat: true; onTriggered: root.currentTime = new Date() }
  Timer { interval: 900000; running: root.visible; repeat: true; onTriggered: requestTimer.restart() }

  Process {
    id: coursesProc
    property bool cached: true
    function run() {
      command = ["python3", root.helper, "--academic", "courses"].concat(cached ? ["--cached"] : [])
      running = true
    }
    stdout: StdioCollector { id: coursesOutput; waitForEnd: true }
    onExited: {
      var result = root.parse(coursesOutput.text)
      if (result && result.ok) root.courses = result.items || []
      if (cached) { cached = false; Qt.callLater(run) }
    }
  }
  Process {
    id: resourceProc
    property string key: ""
    property string selectedSection: ""
    property string selectedCourse: ""
    property bool cached: true
    property bool forced: false
    function run() {
      command = ["python3", root.helper, "--academic", selectedSection, "--course", selectedCourse]
        .concat(cached ? ["--cached"] : forced ? ["--refresh"] : [])
      running = true
    }
    stdout: StdioCollector { id: resourceOutput; waitForEnd: true }
    onExited: {
      if (key !== root.queryKey) { Qt.callLater(root.begin); return }
      var result = root.parse(resourceOutput.text)
      if (result) {
        root.snapshot = result
        if (selectedSection === "courses" && result.ok) root.courses = result.items || []
      }
      if (cached) { cached = false; Qt.callLater(run) }
      else {
        root.loading = false
        if (root.forceNext) Qt.callLater(root.begin)
      }
    }
  }

  Column {
    id: controls
    width: parent.width
    spacing: Style.spacing.md
    Flow {
      width: parent.width
      spacing: Style.spacing.xs
      Repeater {
        model: [
          { key: "assignments", label: root.tr("Assignments", "Entregas") },
          { key: "announcements", label: root.tr("Announcements", "Anuncios") },
          { key: "courses", label: root.tr("Courses", "Cursos") },
          { key: "grades", label: root.tr("Grades", "Calificaciones") },
          { key: "materials", label: root.tr("Materials", "Materiales") },
          { key: "calendar", label: root.tr("Calendar", "Calendario") }
        ]
        Button {
          required property var modelData
          text: modelData.label
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          active: root.section === modelData.key
          onClicked: {
            if (modelData.key === "calendar") root.calendarRequested()
            else root.section = modelData.key
          }
        }
      }
    }
    Dropdown {
      id: coursePicker
      visible: root.section !== "courses"
      width: parent.width
      foreground: root.foreground
      fontFamily: root.fontFamily
      value: root.courseId
      options: [{ value: "", label: root.tr("All courses", "Todos los cursos") }].concat(root.courses.map(function(c) {
        return { value: c.id, label: c.title }
      }))
      onChanged: function(value) { root.courseId = value }
    }
    Dropdown {
      id: statusPicker
      visible: root.section === "assignments"
      width: parent.width
      foreground: root.foreground
      fontFamily: root.fontFamily
      value: root.assignmentFilter
      options: [
        { value: "pending", label: root.tr("Pending", "Pendientes") },
        { value: "overdue", label: root.tr("Overdue", "Vencidas sin entregar") },
        { value: "submitted", label: root.tr("Submitted", "Entregadas") },
        { value: "all", label: root.tr("All", "Todas") }
      ]
      onChanged: function(value) { root.assignmentFilter = value }
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: root.loading ? root.tr("Updating…", "Actualizando…")
        : root.snapshot.chooseCourse ? root.tr("Choose a course above.", "Selecciona un curso arriba.")
        : root.snapshot.error ? root.tr("Could not update. Saved data is shown when available.", "No se pudo actualizar. Se muestran datos guardados cuando están disponibles.")
        : root.snapshot.partial ? root.tr("Some resources could not be loaded.", "Algunos recursos no se pudieron cargar.")
        : root.snapshot.updatedAt ? root.tr("Updated: ", "Actualizado: ") + root.dateLabel(root.snapshot.updatedAt * 1000)
          + (root.snapshot.stale ? root.tr(" · offline", " · sin conexión") : "") : ""
      color: root.foreground
      opacity: 0.65
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
  ListView {
    id: list
    anchors.top: controls.bottom
    anchors.topMargin: Style.spacing.md
    anchors.bottom: parent.bottom
    width: parent.width
    clip: true
    spacing: Style.spacing.md
    reuseItems: true
    model: root.shownItems
    Text {
      visible: list.count === 0 && !root.loading && !root.snapshot.chooseCourse
      width: parent.width
      textFormat: Text.PlainText
      text: root.tr("No items to show.", "No hay elementos para mostrar.")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    delegate: Rectangle {
      id: card
      required property var modelData
      width: list.width
      height: content.implicitHeight + Style.space(20)
      radius: Style.cornerRadius
      color: Style.normalFillFor(root.foreground, Commons.Color.accent)
      Column {
        id: content
        anchors.left: parent.left
        anchors.right: external.left
        anchors.top: parent.top
        anchors.margins: Style.space(10)
        spacing: Style.spacing.xs
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: card.modelData.average ? root.tr("Course average · Canvas", "Promedio del curso · Canvas") : String(card.modelData.title || "")
          wrapMode: Text.WordWrap
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.subtitle(card.modelData)
          wrapMode: Text.WordWrap
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          visible: root.section === "announcements"
          width: parent.width
          textFormat: Text.PlainText
          text: String(card.modelData.body || "")
          wrapMode: Text.WordWrap
          maximumLineCount: root.expandedId === card.modelData.id ? 1000 : 3
          elide: Text.ElideRight
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
      MouseArea {
        anchors.fill: content
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (root.section === "announcements") root.expandedId = root.expandedId === card.modelData.id ? "" : card.modelData.id
          else if (root.section === "courses") { root.courseId = card.modelData.id; root.section = "assignments" }
          else if (card.modelData.url) Qt.openUrlExternally(card.modelData.url)
        }
      }
      PanelActionButton {
        id: external
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(8)
        iconText: "\uf08e"
        tooltipText: root.tr("Open in Canvas", "Abrir en Canvas")
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !!card.modelData.url
        onClicked: Qt.openUrlExternally(card.modelData.url)
      }
    }
  }
}
