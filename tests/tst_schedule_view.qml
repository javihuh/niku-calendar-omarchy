import QtQuick
import QtTest
import "../ScheduleView.js" as ScheduleView

TestCase {
  name: "ScheduleView"

  readonly property var events: [
    { id: "monday", date: "2026-09-14", startTime: "09:00" },
    { id: "wednesday-one", date: "2026-09-16", startTime: "08:00" },
    { id: "wednesday-two", date: "2026-09-16", startTime: "14:00" },
    { id: "sunday", date: "2026-09-20", startTime: "11:00" },
    { id: "next-monday", date: "2026-09-21", startTime: "09:00" }
  ]

  function test_normalizesUnknownViewsToDay() {
    compare(ScheduleView.normalizedView("Week"), "week")
    compare(ScheduleView.normalizedView("unexpected"), "day")
  }

  function test_dayViewIncludesOnlyReferenceDate() {
    var result = ScheduleView.eventsForView(
      events, "day", "2026-09-16", "2026-09-14", "2026-09-20")

    compare(result.length, 2)
    compare(result[0].id, "wednesday-one")
    compare(result[1].id, "wednesday-two")
  }

  function test_weekViewUsesInclusiveMondayAndSunday() {
    var result = ScheduleView.eventsForView(
      events, "week", "2026-09-16", "2026-09-14", "2026-09-20")

    compare(result.length, 4)
    compare(result[0].id, "monday")
    compare(result[3].id, "sunday")
  }

  function test_weekViewGroupsOnlyDatesWithActivities() {
    var groups = ScheduleView.groupsForView(
      events, "week", "2026-09-16", "2026-09-14", "2026-09-20")

    compare(groups.length, 3)
    compare(groups[0].date, "2026-09-14")
    compare(groups[1].date, "2026-09-16")
    compare(groups[1].events.length, 2)
    compare(groups[2].date, "2026-09-20")
  }

  function test_viewDoesNotCapAtEightActivities() {
    var manyEvents = []
    for (var index = 0; index < 10; index++)
      manyEvents.push({ id: String(index), date: "2026-09-16" })

    var result = ScheduleView.eventsForView(
      manyEvents, "day", "2026-09-16", "2026-09-14", "2026-09-20")
    compare(result.length, 10)
  }

  function test_overlapGroupsAndTouchingEndpoints() {
    var date = "2026-11-02"
    var blocks = ScheduleView.layoutDay([
      { id: "a", date: date, startTime: "09:00", endTime: "11:00" },
      { id: "b", date: date, startTime: "10:00", endTime: "12:00" },
      { id: "c", date: date, startTime: "11:00", endTime: "13:00" },
      { id: "d", date: date, startTime: "13:00", endTime: "14:00" }
    ], date)
    compare(blocks.map(function(b) { return b.column }), [0, 1, 0, 0])
    compare(blocks.map(function(b) { return b.columns }), [2, 2, 2, 1])
  }

  function test_shortEventsAndDeadlineAtEndOfDay() {
    var blocks = ScheduleView.layoutDay([
      { date: "2026-11-02", startTime: "23:59", marker: true },
      { date: "2026-11-02", startTime: "invalid" },
      { date: "2026-11-02", startTime: "00:00", allDay: true }
    ], "2026-11-02")
    compare(blocks.length, 1)
    compare(blocks[0].end, 1440)
    compare(blocks[0].start, 1420)
    compare(blocks[0].event.startTime, "23:59")
  }

  function test_weekDatesCrossMonthAndYear() {
    compare(ScheduleView.weekDates("2026-12-28"),
      ["2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02", "2027-01-03"])
    compare(ScheduleView.weekDates(""), [])
  }

  function test_canvasCrossMidnightAndExclusiveEnd() {
    var events = ScheduleView.canvasEvents([], [{ id: "event", title: "Study",
      startAt: "2026-11-02T23:00:00", endAt: "2026-11-04T00:00:00" }])
    compare(events.length, 2)
    compare(events[0].date, "2026-11-02")
    compare(events[0].endMinute, 1440)
    compare(events[1].date, "2026-11-03")
    compare(events[1].startTime, "00:00")
    compare(events[1].endMinute, 1440)
  }

  function test_stateChangesWithoutReloadingData() {
    var event = { date: "2026-11-02", startTime: "09:00", endTime: "10:00" }
    compare(ScheduleView.temporalState(event, new Date(2026, 10, 2, 8, 59)), "upcoming")
    compare(ScheduleView.temporalState(event, new Date(2026, 10, 2, 9, 0)), "active")
    compare(ScheduleView.temporalState(event, new Date(2026, 10, 2, 10, 0)), "occurred")
  }

  function test_allDayUsesCalendarDateInsteadOfUtcMidnight() {
    var events = ScheduleView.canvasEvents([], [{ id: "holiday", title: "Holiday", allDay: true,
      allDayDate: "2026-11-07", startAt: "2026-11-07T00:00:00Z", endAt: "2026-11-08T00:00:00Z" }])
    compare(events.length, 1)
    compare(events[0].date, "2026-11-07")
    compare(events[0].startTime, "00:00")
  }
}
