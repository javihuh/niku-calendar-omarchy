import QtQuick
import QtTest
import "../NikuData.js" as NikuData

TestCase {
  name: "NikuData"

  function test_mergesLocalClassWithCanvasDeadlineInLocalTime() {
    var now = new Date(2026, 9, 6, 8, 0)
    var due = new Date(2026, 9, 6, 23, 59).toISOString()
    var result = NikuData.timeline(
      [{ id: "class", date: "2026-10-06", startTime: "10:20", title: "Math" }],
      [{ id: "1", dueAt: due, title: "Report", done: false }], now)
    compare(result.length, 2)
    compare(result[0].id, "class")
    compare(result[1].date, "2026-10-06")
    compare(result[1].startTime, "23:59")
    compare(result[1].source, "canvas")
    compare(NikuData.dueLabel(due, now, "es"), "HOY")
  }

  function test_onlyShowsUpcomingUnsubmittedItems() {
    var now = new Date(2026, 9, 6, 12, 0)
    var result = NikuData.pending([
      { dueAt: new Date(2026, 8, 20, 11, 0).toISOString(), done: false },
      { dueAt: new Date(2026, 9, 6, 11, 0).toISOString(), done: false },
      { dueAt: now.toISOString(), done: false },
      { dueAt: new Date(2026, 9, 7, 11, 0).toISOString(), done: true },
      { id: "upcoming", dueAt: new Date(2026, 9, 7, 12, 0).toISOString(), done: false }
    ], now)
    compare(result.length, 1)
    compare(result[0].id, "upcoming")
    compare(NikuData.dueLabel(new Date(2026, 9, 6, 11, 0).toISOString(), now, "es"), "VENCIDA")
  }

  function test_remainingLabelUsesLocalDeadlineAndCurrentTime() {
    var now = new Date(2026, 9, 6, 12, 0)
    compare(NikuData.remainingLabel(new Date(2026, 9, 6, 12, 25).toISOString(), now, "es"), "Faltan 25 min")
    compare(NikuData.remainingLabel(new Date(2026, 9, 6, 14, 30).toISOString(), now, "es"), "Faltan 2 h 30 min")
    compare(NikuData.remainingLabel(new Date(2026, 9, 8, 15, 0).toISOString(), now, "en"), "2 d 3 h left")
    compare(NikuData.remainingLabel(now.toISOString(), now, "es"), "")
  }

  function test_activityProgressAndNextDayIgnoreStaleBackendState() {
    var events = [
      { activityId: "tomorrow", date: "2026-11-07", startTime: "08:00", endTime: "09:00", state: "occurred" },
      { activityId: "current", date: "2026-11-06", startTime: "10:00", endTime: "11:00", state: "upcoming" },
      { activityId: "past", date: "2026-11-06", startTime: "08:00", endTime: "09:00", state: "active" }
    ]
    var now = new Date(2026, 10, 6, 10, 30)
    var snapshot = NikuData.activitySnapshot(events, now)
    compare(snapshot.active.length, 1)
    compare(snapshot.active[0].event.activityId, "current")
    compare(snapshot.active[0].progress, 0.5)
    compare(snapshot.upcoming[0].event.activityId, "tomorrow")
    snapshot = NikuData.activitySnapshot(events, new Date(2026, 10, 6, 11, 0))
    compare(snapshot.active.length, 0)
    compare(snapshot.upcoming[0].event.activityId, "tomorrow")
  }

  function test_activitySnapshotHandlesOverlapAndInvalidDates() {
    var snapshot = NikuData.activitySnapshot([
      { date: "2026-11-06", startTime: "10:00", endTime: "11:00" },
      { date: "2026-11-06", startTime: "10:20", endTime: "12:00" },
      { date: "invalid", startTime: "10:00", endTime: "11:00" },
      { date: "2026-11-06", startTime: "12:00", endTime: "11:00" }
    ], new Date(2026, 10, 6, 10, 30))
    compare(snapshot.active.length, 2)
    compare(snapshot.upcoming.length, 0)
    compare(snapshot.active[0].event.startTime, "10:00")
  }

  function test_priorityDeadlinesPreserveOverdueAndPlannerCompletion() {
    var now = new Date(2026, 10, 6, 12)
    var assignments = [
      { id: "future", dueAt: new Date(2026, 10, 10, 12).toISOString() },
      { id: "tomorrow", dueAt: new Date(2026, 10, 7, 12).toISOString() },
      { id: "old", dueAt: new Date(2026, 10, 3, 12).toISOString() },
      { id: "overdue", dueAt: new Date(2026, 10, 5, 12).toISOString(), submitted: false, done: true, markedComplete: true },
      { id: "today", dueAt: new Date(2026, 10, 6, 16).toISOString() },
      { id: "submitted", dueAt: new Date(2026, 10, 5, 12).toISOString(), submitted: true },
      { id: "excused", dueAt: new Date(2026, 10, 5, 12).toISOString(), excused: true },
      { id: "bad", dueAt: "invalid" },
      { id: "undated", dueAt: null }
    ]
    var result = NikuData.priorityAssignments(assignments, now)
    compare(result.map(function(e) { return e.assignment.id }), ["today", "overdue", "old", "tomorrow", "future"])
    compare(result.map(function(e) { return e.state }), ["today", "overdue", "overdue", "tomorrow", "upcoming"])
    // Exact deadlines are overdue, not silently removed.
    compare(NikuData.priorityAssignments([{ dueAt: now.toISOString() }], now)[0].state, "overdue")
  }

  function test_weekSummaryUsesLocalCalendarDatesAndWorkload() {
    var now = new Date(2026, 10, 6, 12)
    var days = NikuData.weekOverview([
      { date: "2026-11-02", startTime: "08:00", endTime: "10:00" },
      { date: "2026-11-02", startTime: "14:00", endTime: "15:00" },
      { date: "2026-11-03", startTime: "08:00", endTime: "09:30" },
      { date: "2026-11-09", startTime: "08:00", endTime: "10:00" }
    ], [{ id: "deadline", dueAt: new Date(2026, 10, 3, 23, 59).toISOString(), submitted: false }], now)
    compare(days.length, 7)
    compare(days[0].date, "2026-11-02")
    compare(days[6].date, "2026-11-08")
    compare(days[0].count, 2)
    compare(days[0].minutes, 180)
    compare(days[0].load, 1)
    compare(days[1].load, 0.5)
    compare(days[1].deadlines, 1)
    compare(days[6].count, 0)
  }

  function test_durationAndExternalLinks() {
    compare(NikuData.durationLabel(25 * 60000), "25 min")
    compare(NikuData.durationLabel(60 * 60000), "1 h")
    compare(NikuData.durationLabel(90 * 60000), "1 h 30 min")
    compare(NikuData.durationLabel(-1000), "0 min")
    verify(NikuData.isWebLink("https://canvas.example.edu/courses/1"))
    verify(!NikuData.isWebLink("javascript:alert(1)"))
    verify(!NikuData.isWebLink("file:///tmp/file"))
    verify(!NikuData.isWebLink("https://user@canvas.example.edu/"))
  }

  function test_preparedActivityDataSurvivesMultipleClockTicks() {
    var entries = NikuData.prepareActivities([
      { date: "2026-11-06", startTime: "11:00", endTime: "12:00", activityId: "next" },
      { date: "2026-11-06", startTime: "10:00", endTime: "11:00", activityId: "now" }
    ])
    var first = NikuData.activitySnapshotPrepared(entries, new Date(2026, 10, 6, 10, 30))
    var second = NikuData.activitySnapshotPrepared(entries, new Date(2026, 10, 6, 10, 45))
    compare(first.active[0].progress, 0.5)
    compare(second.active[0].progress, 0.75)
    compare(entries[0].progress, 0)
    verify(first.upcoming[0] === second.upcoming[0])
  }

  function test_deadlineModelsOnlyChangeWhenPriorityActuallyChanges() {
    var entries = NikuData.prepareAssignments([
      { id: "first", dueAt: new Date(2026, 10, 6, 13).toISOString() },
      { id: "second", dueAt: new Date(2026, 10, 7, 14).toISOString() }
    ])
    var first = NikuData.prioritiesFromPrepared(entries, new Date(2026, 10, 6, 12))
    var tick = NikuData.prioritiesFromPrepared(entries, new Date(2026, 10, 6, 12, 0, 30))
    verify(NikuData.samePriorities(first, tick))
    var expired = NikuData.prioritiesFromPrepared(entries, new Date(2026, 10, 6, 13))
    verify(!NikuData.samePriorities(first, expired))
    compare(expired[0].state, "overdue")
  }
}
