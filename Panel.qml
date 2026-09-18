import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "I18n.js" as I18n

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
  readonly property string languageCode: I18n.languageCode(setting("language", "English"))

  property var scheduleStatus: ({
    ok: true,
    revision: 0,
    title: "Schedule",
    configured: false,
    items: [],
    itemCount: 0,
    todayCount: 0,
    events: []
  })
  readonly property bool configured: scheduleStatus.configured === true
  readonly property int todayCount: Number(scheduleStatus.todayCount || 0)
  readonly property string scheduleTitle: String(scheduleStatus.title || "Schedule")

  property string viewMode: "main"
  property string selectedActivityId: ""
  property string detailReturnMode: "main"
  property string editorCancelMode: "main"
  property int editorRevision: 0

  property var previewData: null
  property string notice: ""
  property bool noticeIsError: false
  property bool refreshQueued: false
  property bool reminderQueued: false
  property bool componentReady: false
  property int languageRevision: 0
  property bool repreviewAfterLanguageChange: false
  property bool editorNeedsRevisionSync: false
  property bool editorConflictRefreshPending: false
  property int statusGeneration: 0
  property int editorRevisionSyncGeneration: 0

  property string mutationKind: ""
  property string mutationTargetId: ""
  property string mutationReturnMode: "main"
  property var createBaselineIds: []

  readonly property bool choosing: chooserProc.running
  readonly property bool previewing: previewProc.running
  readonly property bool importing: importProc.running
  readonly property bool mutating: mutationProc.running
  readonly property bool busy: choosing || previewing || importing || mutating
  readonly property var selectedActivity: activityById(selectedActivityId)

  onLanguageCodeChanged: {
    if (!componentReady) return
    var hadPreview = previewData !== null || previewProc.running
    languageRevision += 1
    clearNotice()
    previewData = null
    if (reminderProc.running) reminderQueued = true
    if (hadPreview && !importProc.running && !mutationProc.running
        && !chooserProc.running) {
      repreviewAfterLanguageChange = true
      Qt.callLater(rerunPreviewForLanguage)
    }
    if (opened) Qt.callLater(refresh)
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
      var prefix = Number(issue.row || 0) > 0
        ? I18n.t(languageCode, "row.prefix", { row: issue.row }) : ""
      return prefix + String(issue.message || fallback)
    }
    return fallback
  }

  function isRevisionConflict(data, message) {
    var errors = data && data.errors ? data.errors : []
    if (errors.length > 0 && String(errors[0].code || "") === "revision_conflict")
      return true
    return String(message || "").indexOf("Revision conflict") !== -1
      || String(message || "").indexOf("Conflicto de revisión") !== -1
  }

  function backendCommand(parts) {
    return ["python3", helperPath, "--language", languageCode].concat(parts)
  }

  function rerunPreviewForLanguage() {
    if (!repreviewAfterLanguageChange || previewProc.running) return
    repreviewAfterLanguageChange = false
    previewCsv()
  }

  function currentRevision() {
    var revision = Number(scheduleStatus.revision || 0)
    return isFinite(revision) && revision >= 0 ? revision : 0
  }

  function activityById(activityId) {
    var items = scheduleStatus.items || []
    for (var index = 0; index < items.length; index++) {
      if (String(items[index].id || "") === String(activityId || "")) return items[index]
    }
    return null
  }

  function activityInStatus(data, activityId) {
    var items = data && data.items ? data.items : []
    for (var index = 0; index < items.length; index++) {
      if (String(items[index].id || "") === String(activityId || "")) return items[index]
    }
    return null
  }

  function applyStatus(data) {
    if (!data || data.ok !== true || !data.items || !data.events) return false
    var incomingRevision = Number(data.revision || 0)
    var knownRevision = currentRevision()
    if (!isFinite(incomingRevision) || incomingRevision < knownRevision) return false

    scheduleStatus = data
    if (viewMode === "detail" && selectedActivityId !== ""
        && !activityInStatus(data, selectedActivityId)) {
      selectedActivityId = ""
      viewMode = "manage"
      notice = I18n.t(languageCode, "notice.activityMissing")
      noticeIsError = true
      Qt.callLater(focusKeyCatcher)
    }
    return true
  }

  function todayIso() {
    var date = new Date()
    var month = String(date.getMonth() + 1).padStart(2, "0")
    var day = String(date.getDate()).padStart(2, "0")
    return date.getFullYear() + "-" + month + "-" + day
  }

  function clearNotice() {
    notice = ""
    noticeIsError = false
  }

  function focusKeyCatcher() {
    if (root.opened && keyCatcher) keyCatcher.forceActiveFocus()
  }

  function setView(nextMode) {
    if (nextMode !== "main") mainView.renameActive = false
    viewMode = nextMode
    Qt.callLater(focusKeyCatcher)
  }

  function showMain() {
    clearNotice()
    mainView.renameActive = false
    setView("main")
  }

  function showManage() {
    clearNotice()
    setView("manage")
  }

  function openActivity(activityId, returnMode) {
    if (!activityById(activityId)) return
    clearNotice()
    selectedActivityId = String(activityId)
    detailReturnMode = returnMode === "manage" ? "manage" : "main"
    setView("detail")
  }

  function startCreate(returnMode) {
    if (busy) return
    clearNotice()
    editorNeedsRevisionSync = false
    editorConflictRefreshPending = false
    editorRevisionSyncGeneration = 0
    editorRevision = currentRevision()
    editorCancelMode = returnMode === "manage" ? "manage" : "main"
    viewMode = "edit"
    activityEditor.beginCreate(todayIso())
    Qt.callLater(activityEditor.focusFirst)
  }

  function startEdit() {
    if (busy || !selectedActivity) return
    clearNotice()
    editorNeedsRevisionSync = false
    editorConflictRefreshPending = false
    editorRevisionSyncGeneration = 0
    editorRevision = currentRevision()
    editorCancelMode = "detail"
    viewMode = "edit"
    activityEditor.beginEdit(selectedActivity)
    Qt.callLater(activityEditor.focusFirst)
  }

  function cancelEditor() {
    if (mutating) return
    clearNotice()
    editorNeedsRevisionSync = false
    editorConflictRefreshPending = false
    editorRevisionSyncGeneration = 0
    if (editorCancelMode === "detail" && !selectedActivity)
      setView("manage")
    else
      setView(editorCancelMode)
  }

  function goBackOrClose() {
    if (deleteDialog.opened) {
      cancelDelete()
      return
    }
    if (viewMode === "edit") {
      cancelEditor()
    } else if (viewMode === "detail") {
      setView(detailReturnMode)
    } else if (viewMode === "manage") {
      setView("main")
    } else {
      close()
    }
  }

  function refresh() {
    if (statusProc.running) {
      refreshQueued = true
      return
    }
    statusGeneration += 1
    statusProc.requestStatusGeneration = statusGeneration
    statusProc.requestLanguageRevision = languageRevision
    statusProc.command = backendCommand(["status", "--days", "120"])
    statusProc.running = true
  }

  function checkReminders() {
    if (reminderProc.running) {
      reminderQueued = true
      return
    }
    reminderProc.requestLanguageRevision = languageRevision
    reminderProc.command = backendCommand(["remind"])
    reminderProc.running = true
  }

  function previewCsv() {
    var path = String(mainView.csvPath || "").trim()
    if (!path) {
      notice = I18n.t(languageCode, "notice.csvPathRequired")
      noticeIsError = true
      return
    }
    clearNotice()
    previewData = null
    previewProc.requestLanguageRevision = languageRevision
    previewProc.command = backendCommand(["preview", path])
    previewProc.running = true
  }

  function chooseCsv() {
    if (busy) return
    notice = I18n.t(languageCode, "notice.openingPicker")
    noticeIsError = false
    chooserProc.requestLanguageRevision = languageRevision
    chooserProc.command = backendCommand(["choose"])
    close()
    Qt.callLater(function() { chooserProc.running = true })
  }

  function importCsv() {
    if (!mainView.previewReady || busy) return
    clearNotice()
    importProc.requestLanguageRevision = languageRevision
    importProc.command = backendCommand([
      "import", String(mainView.csvPath).trim(),
      "--expected-revision", String(currentRevision())
    ])
    importProc.running = true
  }

  function startMutation(kind, commandParts, payload, targetId, returnMode) {
    if (mutationProc.running || importProc.running) return
    clearNotice()
    mutationKind = kind
    mutationTargetId = String(targetId || "")
    mutationReturnMode = String(returnMode || "main")
    mutationProc.requestLanguageRevision = languageRevision
    mutationProc.payload = JSON.stringify(payload)
    mutationProc.command = backendCommand(commandParts)
    mutationProc.running = true
  }

  function renameSchedule(title) {
    if (busy) return
    startMutation("rename", ["rename-schedule"], {
      expectedRevision: currentRevision(),
      title: title
    }, "", "main")
  }

  function saveEditor(activity, linkScope) {
    if (busy) return
    if (editorConflictRefreshPending) return
    if (editorNeedsRevisionSync) {
      editorConflictRefreshPending = true
      editorRevisionSyncGeneration = statusGeneration + 1
      refresh()
      return
    }
    if (activityEditor.creating) {
      var items = scheduleStatus.items || []
      var existingIds = []
      for (var index = 0; index < items.length; index++)
        existingIds.push(String(items[index].id || ""))
      createBaselineIds = existingIds
      startMutation("create", ["create-activity"], {
        expectedRevision: editorRevision,
        activity: activity,
        linkScope: linkScope || "activity"
      }, "", editorCancelMode)
    } else {
      startMutation("update", ["update-activity", selectedActivityId], {
        expectedRevision: editorRevision,
        changes: activity,
        linkScope: linkScope || "activity"
      }, selectedActivityId, detailReturnMode)
    }
  }

  function requestDelete() {
    if (busy || !selectedActivity) return
    deleteDialog.selectedIndex = 0
    deleteDialog.opened = true
    Qt.callLater(function() { deleteDialogFocus.forceActiveFocus() })
  }

  function cancelDelete() {
    deleteDialog.opened = false
    Qt.callLater(focusKeyCatcher)
  }

  function confirmDelete() {
    if (busy || !selectedActivity) {
      cancelDelete()
      return
    }
    var activityId = selectedActivityId
    deleteDialog.opened = false
    startMutation("delete", ["delete-activity", activityId], {
      expectedRevision: currentRevision()
    }, activityId, "manage")
  }

  function mutationSucceeded(data) {
    var kind = mutationKind
    var targetId = mutationTargetId
    var returnMode = mutationReturnMode
    editorNeedsRevisionSync = false
    editorConflictRefreshPending = false
    editorRevisionSyncGeneration = 0
    applyStatus(data)

    if (kind === "rename") {
      notice = I18n.t(languageCode, "notice.renameSaved")
      noticeIsError = false
      setView("main")
    } else if (kind === "create") {
      var createdId = ""
      var items = data.items || []
      for (var index = 0; index < items.length; index++) {
        var candidateId = String(items[index].id || "")
        if (createBaselineIds.indexOf(candidateId) === -1) {
          createdId = candidateId
          break
        }
      }
      if (!createdId && items.length > 0) createdId = String(items[items.length - 1].id || "")
      selectedActivityId = createdId
      detailReturnMode = returnMode === "manage" ? "manage" : "main"
      var createdLinksUpdatedCount = Number(data.linksUpdatedCount || 0)
      notice = data.linkScope === "same-title" && createdLinksUpdatedCount > 1
        ? I18n.t(languageCode, "notice.activityCreatedLinks", {
            count: createdLinksUpdatedCount
          })
        : I18n.t(languageCode, "notice.activityCreated")
      noticeIsError = false
      setView("detail")
    } else if (kind === "update") {
      selectedActivityId = targetId
      var linksUpdatedCount = Number(data.linksUpdatedCount || 0)
      notice = data.linkScope === "same-title" && linksUpdatedCount > 1
        ? I18n.t(languageCode, "notice.changesSavedLinks", {
            count: linksUpdatedCount
          })
        : I18n.t(languageCode, "notice.changesSaved")
      noticeIsError = false
      setView("detail")
    } else if (kind === "delete") {
      selectedActivityId = ""
      notice = I18n.t(languageCode, "notice.activityDeleted")
      noticeIsError = false
      setView("manage")
    }
    Qt.callLater(checkReminders)
  }

  function mutationFailed(data, stderrText) {
    var conflict = isRevisionConflict(data, stderrText)
    var message = conflict
      ? I18n.t(languageCode, "notice.revisionConflict")
      : errorText(data, String(stderrText
          || I18n.t(languageCode, "notice.saveFailed")))
    notice = message
    noticeIsError = true
    if (conflict) {
      if (viewMode === "edit") {
        editorNeedsRevisionSync = true
        editorConflictRefreshPending = true
        editorRevisionSyncGeneration = statusGeneration + 1
      }
      refresh()
    }
  }

  function open() {
    viewMode = "main"
    mainView.renameActive = false
    refresh()
    controller.show()
  }

  function close() {
    deleteDialog.opened = false
    mainView.renameActive = false
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  Component.onCompleted: Qt.callLater(function() {
    componentReady = true
    refresh()
    checkReminders()
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
    property int requestLanguageRevision: 0
    property int requestStatusGeneration: 0
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
      var staleLanguage = requestLanguageRevision !== root.languageRevision
      if (exitCode === 0 && data && data.ok === true) {
        root.applyStatus(data)
        if (root.editorNeedsRevisionSync
            && requestStatusGeneration >= root.editorRevisionSyncGeneration) {
          root.editorConflictRefreshPending = false
          if (root.viewMode !== "edit") {
            root.editorNeedsRevisionSync = false
            root.editorRevisionSyncGeneration = 0
          } else if (activityEditor.creating
              || root.activityById(root.selectedActivityId)) {
            root.editorRevision = root.currentRevision()
            root.editorNeedsRevisionSync = false
            root.editorRevisionSyncGeneration = 0
          } else {
            root.editorNeedsRevisionSync = false
            root.editorRevisionSyncGeneration = 0
            root.selectedActivityId = ""
            root.setView("manage")
            root.notice = I18n.t(root.languageCode, "notice.activityMissing")
            root.noticeIsError = true
          }
        }
      } else if (!root.notice) {
        root.notice = staleLanguage
          ? I18n.t(root.languageCode, "notice.readFailed")
          : root.errorText(data, String(statusErr.text
              || I18n.t(root.languageCode, "notice.readFailed")))
        root.noticeIsError = true
      }
      if (exitCode !== 0 && root.editorNeedsRevisionSync
          && requestStatusGeneration >= root.editorRevisionSyncGeneration)
        root.editorConflictRefreshPending = false
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: reminderProc
    property int requestLanguageRevision: 0
    stdout: StdioCollector {
      id: reminderOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: reminderErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && requestLanguageRevision === root.languageRevision) {
        var data = root.parsedOutput(reminderOut.text)
        console.warn("schedule reminders: "
          + root.errorText(data, String(reminderErr.text
            || I18n.t(root.languageCode, "notice.reminderFailed"))))
      }
      if (root.reminderQueued) {
        root.reminderQueued = false
        Qt.callLater(root.checkReminders)
      }
    }
  }

  Process {
    id: chooserProc
    property int requestLanguageRevision: 0
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
      var staleLanguage = requestLanguageRevision !== root.languageRevision
      root.open()
      if (exitCode === 0 && data && data.ok === true && data.path) {
        mainView.csvPath = String(data.path)
        root.clearNotice()
        Qt.callLater(root.previewCsv)
      } else if (data && data.cancelled === true) {
        root.notice = I18n.t(root.languageCode, "notice.selectionCancelled")
        root.noticeIsError = false
      } else {
        root.notice = staleLanguage
          ? I18n.t(root.languageCode, "notice.pickerFailed")
          : root.errorText(data, String(chooserErr.text
              || I18n.t(root.languageCode, "notice.pickerFailed")))
        root.noticeIsError = true
      }
    }
  }

  Process {
    id: previewProc
    property int requestLanguageRevision: 0
    stdout: StdioCollector {
      id: previewOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: previewErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (requestLanguageRevision !== root.languageRevision) {
        root.repreviewAfterLanguageChange = true
        Qt.callLater(root.rerunPreviewForLanguage)
        return
      }
      var data = root.parsedOutput(previewOut.text)
      root.previewData = data
      if (exitCode === 0 && data && data.ok === true) {
        root.notice = I18n.plural(root.languageCode, "count.ready",
          Number(data.validCount || 0))
        root.noticeIsError = false
      } else {
        root.notice = root.errorText(data, String(previewErr.text
          || I18n.t(root.languageCode, "notice.previewFailed")))
        root.noticeIsError = true
      }
    }
  }

  Process {
    id: importProc
    property int requestLanguageRevision: 0
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
      var staleLanguage = requestLanguageRevision !== root.languageRevision
      if (exitCode === 0 && data && data.ok === true) {
        root.applyStatus(data)
        root.previewData = null
        root.notice = I18n.plural(root.languageCode, "count.imported",
          Number(data.importedCount || 0))
        root.noticeIsError = false
        Qt.callLater(root.checkReminders)
      } else {
        var message = staleLanguage
          ? I18n.t(root.languageCode, "notice.importFailed")
          : root.errorText(data, String(importErr.text
              || I18n.t(root.languageCode, "notice.importFailed")))
        root.notice = message
        root.noticeIsError = true
        if (root.isRevisionConflict(data, message)) root.refresh()
      }
    }
  }

  Process {
    id: mutationProc
    property string payload: ""
    property int requestLanguageRevision: 0
    stdinEnabled: true
    stdout: StdioCollector {
      id: mutationOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: mutationErr
      waitForEnd: true
    }
    onStarted: write(payload + "\n")
    onExited: function(exitCode) {
      var data = root.parsedOutput(mutationOut.text)
      if (exitCode === 0 && data && data.ok === true)
        root.mutationSucceeded(data)
      else if (requestLanguageRevision !== root.languageRevision
          && !root.isRevisionConflict(data, ""))
        root.mutationFailed(null, I18n.t(root.languageCode, "notice.saveFailed"))
      else
        root.mutationFailed(data, mutationErr.text)
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
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: deleteDialog.opened
        || (root.viewMode === "main" && mainView.inputActive)
        || (root.viewMode === "edit" && activityEditor.inputActive)
      onCloseRequested: root.goBackOrClose()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.viewMode === "manage") activityManager.moveSelection(dy !== 0 ? dy : dx)
      }
      onActivateRequested: {
        if (root.viewMode === "manage") activityManager.activateSelection()
      }

      ScheduleMain {
        id: mainView
        anchors.fill: parent
        visible: root.viewMode === "main"
        scheduleStatus: root.scheduleStatus
        languageCode: root.languageCode
        previewData: root.previewData
        notice: root.notice
        noticeIsError: root.noticeIsError
        choosing: root.choosing
        previewing: root.previewing
        importing: root.importing
        busy: root.busy
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        onRenameRequested: function(title) { root.renameSchedule(title) }
        onAddRequested: root.startCreate("main")
        onManageRequested: root.showManage()
        onActivityRequested: function(activityId) { root.openActivity(activityId, "main") }
        onChooseRequested: root.chooseCsv()
        onPreviewRequested: root.previewCsv()
        onImportRequested: root.importCsv()
        onPathEdited: {
          root.previewData = null
          root.clearNotice()
        }
        onFocusReleaseRequested: Qt.callLater(root.focusKeyCatcher)
      }

      ActivityManager {
        id: activityManager
        anchors.fill: parent
        visible: root.viewMode === "manage"
        items: root.scheduleStatus.items || []
        languageCode: root.languageCode
        scheduleTitle: root.scheduleTitle
        notice: root.notice
        noticeIsError: root.noticeIsError
        busy: root.busy
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        onBackRequested: root.showMain()
        onAddRequested: root.startCreate("manage")
        onActivityRequested: function(activityId) { root.openActivity(activityId, "manage") }
      }

      ActivityDetails {
        id: activityDetails
        anchors.fill: parent
        visible: root.viewMode === "detail"
        activity: root.selectedActivity || ({})
        languageCode: root.languageCode
        notice: root.notice
        noticeIsError: root.noticeIsError
        busy: root.busy
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        onBackRequested: root.setView(root.detailReturnMode)
        onEditRequested: root.startEdit()
        onDeleteRequested: root.requestDelete()
      }

      ActivityEditor {
        id: activityEditor
        anchors.fill: parent
        visible: root.viewMode === "edit"
        notice: root.notice
        noticeIsError: root.noticeIsError
        busy: root.busy || root.editorConflictRefreshPending
        activities: root.scheduleStatus.items || []
        languageCode: root.languageCode
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        onSaveRequested: function(activity, linkScope) {
          root.saveEditor(activity, linkScope)
        }
        onCancelRequested: root.cancelEditor()
        onFocusReleaseRequested: Qt.callLater(root.focusKeyCatcher)
      }

      ConfirmDialog {
        id: deleteDialog
        anchors.fill: parent
        z: 20
        opened: false
        selectedIndex: 0
        message: root.selectedActivity
          ? I18n.t(root.languageCode, "dialog.deleteTitle", {
              title: String(root.selectedActivity.title || "")
            })
          : I18n.t(root.languageCode, "dialog.deleteFallback")
        cancelText: I18n.t(root.languageCode, "common.cancel")
        confirmText: I18n.t(root.languageCode, "common.delete")
        background: Color.popups.background
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        onCanceled: root.cancelDelete()
        onConfirmed: root.confirmDelete()

        Item {
          id: deleteDialogFocus
          anchors.fill: parent
          focus: deleteDialog.opened
          Keys.onPressed: function(event) {
            event.accepted = deleteDialog.handleKey(event)
          }
        }
      }
    }
  }
}
