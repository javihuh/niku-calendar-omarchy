.pragma library

function normalizedView(value) {
  return String(value || "").toLowerCase() === "week" ? "week" : "day"
}

function eventsForView(events, view, referenceDate, weekStart, weekEnd) {
  var source = events || []
  var selectedView = normalizedView(view)
  var result = []
  for (var index = 0; index < source.length; index++) {
    var event = source[index]
    var eventDate = String(event.date || "")
    var included = selectedView === "week"
      ? eventDate >= String(weekStart || "") && eventDate <= String(weekEnd || "")
      : eventDate === String(referenceDate || "")
    if (included) result.push(event)
  }
  return result
}

function groupsForView(events, view, referenceDate, weekStart, weekEnd) {
  var filtered = eventsForView(events, view, referenceDate, weekStart, weekEnd)
  return groupEvents(filtered)
}

function groupEvents(filtered) {
  var groups = []
  for (var index = 0; index < filtered.length; index++) {
    var event = filtered[index]
    var eventDate = String(event.date || "")
    var group = groups.length > 0 ? groups[groups.length - 1] : null
    if (!group || group.date !== eventDate) {
      group = { date: eventDate, events: [] }
      groups.push(group)
    }
    group.events.push(event)
  }
  return groups
}

function isoDate(date) {
  return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0")
    + "-" + String(date.getDate()).padStart(2, "0")
}

function weekDates(start) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(start)) return []
  var parts = start.split("-")
  var result = []
  for (var i = 0; i < 7; i++)
    result.push(isoDate(new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]) + i)))
  return result
}

function minutes(time) {
  var match = /^(\d{2}):(\d{2})$/.exec(String(time || ""))
  if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) return -1
  return Number(match[1]) * 60 + Number(match[2])
}

// Interval partitioning. Touching endpoints don't overlap; transitive overlap
// groups share a column count so blocks never cover one another.
function layoutDay(events, date) {
  var blocks = []
  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    if (event.date !== date || event.allDay) continue
    var start = minutes(event.startTime)
    if (start < 0) continue
    var end = event.endMinute !== undefined ? event.endMinute : minutes(event.endTime)
    end = Math.min(1440, Math.max(start + 20, end))
    blocks.push({ event: event, start: Math.min(start, 1420), end: end, column: 0, columns: 1 })
  }
  blocks.sort(function(a, b) { return a.start - b.start || b.end - a.end })
  var group = [], ends = [], groupEnd = -1
  function finish() {
    for (var j = 0; j < group.length; j++) group[j].columns = ends.length
    group = []; ends = []; groupEnd = -1
  }
  for (var k = 0; k < blocks.length; k++) {
    var block = blocks[k]
    if (block.start >= groupEnd) finish()
    var column = 0
    while (column < ends.length && ends[column] > block.start) column++
    block.column = column
    ends[column] = block.end
    group.push(block)
    groupEnd = Math.max(groupEnd, block.end)
  }
  finish()
  return blocks
}

function canvasEvents(assignments, calendar) {
  var result = []
  for (var i = 0; i < (assignments || []).length; i++) {
    var a = assignments[i], due = new Date(a.dueAt)
    if (!a.dueAt || isNaN(due.getTime())) continue
    result.push({ id: "canvas-assignment:" + a.id, source: "canvas", marker: true,
      date: isoDate(due), startTime: String(due.getHours()).padStart(2, "0") + ":" + String(due.getMinutes()).padStart(2, "0"),
      title: a.title, url: a.url, location: a.course || "Canvas", submitted: a.submitted })
  }
  for (var j = 0; j < (calendar || []).length; j++) {
    var e = calendar[j], start = new Date(e.startAt || NaN), end = new Date(e.endAt || e.startAt || NaN)
    if (e.allDay && /^\d{4}-\d{2}-\d{2}$/.test(String(e.allDayDate || ""))) {
      var span = Math.max(1, Math.ceil((end.getTime() - start.getTime()) / 86400000) || 1)
      start = new Date(e.allDayDate + "T00:00:00")
      end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + span)
    }
    if (isNaN(start.getTime()) || isNaN(end.getTime())) continue
    var cursor = new Date(start.getFullYear(), start.getMonth(), start.getDate())
    for (var day = 0; day < 32; day++) {
      var next = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1)
      var from = Math.max(start.getTime(), cursor.getTime())
      var to = Math.min(Math.max(end.getTime(), start.getTime()), next.getTime())
      var local = new Date(from)
      result.push({ id: "canvas-event:" + e.id + ":" + day, source: "canvas", allDay: e.allDay,
        date: isoDate(cursor), startTime: String(local.getHours()).padStart(2, "0") + ":" + String(local.getMinutes()).padStart(2, "0"),
        endMinute: to === next.getTime() ? 1440 : new Date(to).getHours() * 60 + new Date(to).getMinutes(),
        title: e.title, url: e.url, location: e.location })
      if (next.getTime() >= end.getTime()) break
      cursor = next
    }
  }
  return result
}

function temporalState(event, now) {
  if (event.submitted) return "occurred"
  var today = isoDate(now)
  if (event.date < today) return "occurred"
  if (event.date > today) return "upcoming"
  var minute = now.getHours() * 60 + now.getMinutes()
  var start = minutes(event.startTime)
  var end = event.endMinute !== undefined ? event.endMinute : minutes(event.endTime)
  if (event.marker) return minute >= start ? "occurred" : "upcoming"
  if (minute >= end && end >= 0) return "occurred"
  return minute >= start ? "active" : "upcoming"
}
