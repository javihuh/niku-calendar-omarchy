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
}
