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
