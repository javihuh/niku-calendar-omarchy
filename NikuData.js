.pragma library
.import "ScheduleView.js" as ScheduleView

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

function activityTimes(event) {
  var start = new Date(String(event.date || "") + "T" + String(event.startTime || "") + ":00").getTime()
  var end = new Date(String(event.date || "") + "T" + String(event.endTime || "") + ":00").getTime()
  return { start: start, end: end }
}

function prepareActivities(events) {
  var result = []
  for (var i = 0; i < (events || []).length; i++) {
    var event = events[i], times = activityTimes(event)
    if (!isFinite(times.start) || !isFinite(times.end) || times.end <= times.start) continue
    result.push({ event: event, start: times.start, end: times.end, progress: 0 })
  }
  result.sort(function(a, b) { return a.start - b.start || a.end - b.end })
  return result
}

function activitySnapshotPrepared(entries, now) {
  var active = [], upcoming = [], time = now.getTime()
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (entry.start > time) { upcoming = entries.slice(i); break }
    if (time < entry.end) active.push({ event: entry.event, start: entry.start, end: entry.end,
      progress: Math.max(0, Math.min(1, (time - entry.start) / (entry.end - entry.start))) })
  }
  return { active: active, upcoming: upcoming }
}

function activitySnapshot(events, now) { return activitySnapshotPrepared(prepareActivities(events), now) }

function durationLabel(milliseconds) {
  var minutes = Math.max(0, Math.ceil(milliseconds / 60000))
  if (!isFinite(minutes)) return ""
  if (minutes < 60) return minutes + " min"
  if (minutes < 1440) return Math.floor(minutes / 60) + " h" + (minutes % 60 ? " " + minutes % 60 + " min" : "")
  return Math.floor(minutes / 1440) + " d" + (Math.floor(minutes % 1440 / 60) ? " " + Math.floor(minutes % 1440 / 60) + " h" : "")
}

function dayDistance(date, now) {
  return Math.round((Date.UTC(date.getFullYear(), date.getMonth(), date.getDate())
    - Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000)
}

function needsSubmission(assignment) {
  if (assignment.excused) return false
  return typeof assignment.submitted === "boolean" ? !assignment.submitted : !assignment.done
}

function prepareAssignments(assignments) {
  var result = [], seen = {}
  for (var i = 0; i < (assignments || []).length; i++) {
    var assignment = assignments[i], due = new Date(assignment.dueAt)
    if (!assignment.dueAt || !isFinite(due.getTime()) || !needsSubmission(assignment)) continue
    var key = String(assignment.courseId || assignment.course || "") + ":" + String(assignment.id || i)
    if (seen[key]) continue
    seen[key] = true
    result.push({ assignment: assignment, due: due.getTime(),
      day: Date.UTC(due.getFullYear(), due.getMonth(), due.getDate()) / 86400000 })
  }
  result.sort(function(a, b) { return a.due - b.due })
  return result
}

function prioritiesFromPrepared(entries, now) {
  var buckets = [[], [], [], []], time = now.getTime()
  var today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) / 86400000
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i], days = entry.day - today
    var state = entry.due <= time ? "overdue" : days === 0 ? "today" : days === 1 ? "tomorrow" : "upcoming"
    // Today's remaining work first, then overdue work (most recent first).
    var priority = state === "today" ? 0 : state === "overdue" ? 1 : state === "tomorrow" ? 2 : 3
    buckets[priority].push({ assignment: entry.assignment, due: entry.due, days: days, state: state, priority: priority })
  }
  return buckets[0].concat(buckets[1].reverse(), buckets[2], buckets[3])
}

function priorityAssignments(assignments, now) { return prioritiesFromPrepared(prepareAssignments(assignments), now) }

function samePriorities(left, right) {
  if (left.length !== right.length) return false
  for (var i = 0; i < left.length; i++)
    if (left[i].assignment !== right[i].assignment || left[i].due !== right[i].due
        || left[i].state !== right[i].state || left[i].days !== right[i].days) return false
  return true
}

function weekOverview(events, assignments, now) {
  var monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (now.getDay() + 6) % 7)
  var dates = ScheduleView.weekDates(ScheduleView.isoDate(monday))
  var days = dates.map(function(date) { return { date: date, count: 0, minutes: 0, deadlines: 0, load: 0 } })
  for (var i = 0; i < (events || []).length; i++) {
    var event = events[i], index = dates.indexOf(event.date), times = activityTimes(event)
    if (index < 0 || !isFinite(times.start) || !isFinite(times.end) || times.end <= times.start) continue
    days[index].count++
    days[index].minutes += (times.end - times.start) / 60000
  }
  var deadlines = prepareAssignments(assignments)
  for (var j = 0; j < deadlines.length; j++) {
    var day = dates.indexOf(ScheduleView.isoDate(new Date(deadlines[j].due)))
    if (day >= 0) days[day].deadlines++
  }
  var maximum = Math.max.apply(null, days.map(function(d) { return d.minutes }).concat([1]))
  for (var k = 0; k < days.length; k++) days[k].load = days[k].minutes / maximum
  return days
}

function isWebLink(value) {
  return /^https?:\/\/[^\s\/@]+(?:[\/:?#]|$)/i.test(String(value || ""))
}
