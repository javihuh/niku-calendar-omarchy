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
}
