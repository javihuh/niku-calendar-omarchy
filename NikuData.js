.pragma library

function pending(assignments, now) {
  var result = []
  var reference = now || new Date()
  for (var i = 0; i < (assignments || []).length; i++) {
    var item = assignments[i]
    var due = new Date(item.dueAt)
    if (!item.done && !isNaN(due.getTime()) && due.getTime() > reference.getTime())
      result.push(item)
  }
  result.sort(function(a, b) { return new Date(a.dueAt) - new Date(b.dueAt) })
  return result
}

function dueLabel(dueAt, now, language) {
  var due = new Date(dueAt)
  var reference = now || new Date()
  var start = new Date(reference.getFullYear(), reference.getMonth(), reference.getDate())
  var target = new Date(due.getFullYear(), due.getMonth(), due.getDate())
  var days = Math.round((target - start) / 86400000)
  if (due.getTime() < reference.getTime()) return language === "es" ? "VENCIDA" : "OVERDUE"
  if (days === 0) return language === "es" ? "HOY" : "TODAY"
  if (days === 1) return language === "es" ? "MAÑANA" : "TOMORROW"
  return days + (language === "es" ? " días" : " days")
}

function remainingLabel(dueAt, now, language) {
  var minutes = Math.ceil((new Date(dueAt).getTime() - now.getTime()) / 60000)
  if (!isFinite(minutes) || minutes <= 0) return ""
  var duration
  if (minutes < 60) duration = minutes + " min"
  else if (minutes < 1440) {
    duration = Math.floor(minutes / 60) + " h"
    if (minutes % 60) duration += " " + (minutes % 60) + " min"
  } else {
    duration = Math.floor(minutes / 1440) + " d"
    if (Math.floor((minutes % 1440) / 60))
      duration += " " + Math.floor((minutes % 1440) / 60) + " h"
  }
  return language === "es" ? "Faltan " + duration : duration + " left"
}

function classesToday(events, date) {
  return (events || []).filter(function(event) { return event.date === date })
}

function timeline(events, assignments, now) {
  var all = (events || []).slice()
  var remaining = pending(assignments, now)
  for (var i = 0; i < remaining.length; i++) {
    var assignment = remaining[i]
    var due = new Date(assignment.dueAt)
    var year = String(due.getFullYear())
    var month = String(due.getMonth() + 1).padStart(2, "0")
    var day = String(due.getDate()).padStart(2, "0")
    var hour = String(due.getHours()).padStart(2, "0")
    var minute = String(due.getMinutes()).padStart(2, "0")
    all.push({ id: "canvas:" + assignment.id, source: "canvas", date: year + "-" + month + "-" + day,
      startTime: hour + ":" + minute, title: assignment.title, location: assignment.course,
      url: assignment.url, state: due.getTime() < now.getTime() ? "occurred" : "upcoming" })
  }
  all.sort(function(a, b) {
    var left = a.date + a.startTime
    var right = b.date + b.startTime
    return left < right ? -1 : (left > right ? 1 : 0)
  })
  return all
}
