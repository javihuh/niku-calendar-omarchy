.pragma library

var catalogs = {
  en: {
    "common.activity": "Activity",
    "common.addActivity": "Add activity",
    "common.back": "Back",
    "common.browse": "Browse",
    "common.cancel": "Cancel",
    "common.delete": "Delete",
    "common.links": "LINKS",
    "common.location": "LOCATION",
    "common.notes": "NOTES",
    "common.optional": "Optional",
    "common.save": "Save",
    "common.saving": "Saving...",
    "bar.empty": "{title} - no activities",
    "bar.today.one": "{title} - 1 activity today",
    "bar.today.other": "{title} - {count} activities today",
    "count.activities.one": "1 ACTIVITY",
    "count.activities.other": "{count} ACTIVITIES",
    "count.imported.one": "1 activity imported.",
    "count.imported.other": "{count} activities imported.",
    "count.later.one": "+ 1 later activity",
    "count.later.other": "+ {count} later activities",
    "count.ready.one": "1 activity ready to import.",
    "count.ready.other": "{count} activities ready to import.",
    "count.rows.one": "+ 1 row",
    "count.rows.other": "+ {count} rows",
    "date.from": "From {start} · {end}",
    "date.inputPlaceholder": "YYYY-MM-DD",
    "date.noEnd": "no end date",
    "date.monthDay": "day {day}",
    "date.lastMonthDay": "last day of the month",
    "details.editSeries": "Edit series",
    "details.noLocation": "No location.",
    "details.noNotes": "No notes.",
    "details.unavailable": "This activity is no longer available.",
    "editor.activityName": "Activity name",
    "editor.addContext": "Add context or instructions",
    "editor.addLink": "Add link",
    "editor.allSameName": "All with the same name",
    "editor.allSameNameCount": "All with the same name ({count})",
    "editor.applyLinks": "Apply links to",
    "editor.editActivity": "Edit activity",
    "editor.endDate": "End date",
    "editor.endTime": "End time",
    "editor.link": "Link {number}",
    "editor.linkHelp": "You can add buttons with HTTP or HTTPS links.",
    "editor.linkLabel": "Label",
    "editor.linkScopeAll": "Saving will replace the link list for the {count} days and times named \"{title}\". You can edit one separately afterward.",
    "editor.linkScopeOnly": "Links will appear in every recurrence of this day and time.",
    "editor.linkScopeSingle": "There is no other day or time with this name. Links will appear in every recurrence of this activity.",
    "editor.location": "Location",
    "editor.notes": "Notes",
    "editor.lastMonthDay": "Last day of the month",
    "editor.newActivity": "New activity",
    "editor.onlyThisSlot": "Only this day and time",
    "editor.recurrence": "Recurrence",
    "editor.removeLink": "Remove link",
    "editor.startDate": "Start date",
    "editor.startTime": "Start time",
    "editor.title": "Title",
    "editor.weekday": "Day of the week",
    "editor.monthday": "Day of the month",
    "main.active": "IN PROGRESS",
    "main.browseOpen": "Opened...",
    "main.columns": "Columns: title, weekday, monthday, start_time, end_time, recurrence, start_date, end_date, location, and description.",
    "main.empty": "Add an activity or import a CSV to get started.",
    "main.importHeading": "IMPORT CSV",
    "main.importReplace": "Import and replace activities",
    "main.importWarning": "Importing replaces every activity. Manually added notes and links will also be replaced.",
    "main.importing": "Importing...",
    "main.manage": "Manage activities",
    "main.noToday": "No activities today. Time for a catnap.",
    "main.noWeek": "No activities this week. Time for a catnap.",
    "main.noUpcoming": "No activities during the next 120 days.",
    "main.occurred": "OCCURRED",
    "main.pathPlaceholder": "/path/to/schedule.csv",
    "main.preview": "PREVIEW",
    "main.previewCsv": "Preview CSV",
    "main.rename": "Rename schedule",
    "main.saveName": "Save name",
    "main.upcoming": "UPCOMING ACTIVITIES",
    "main.validating": "Validating...",
    "main.viewDay": "Day",
    "main.viewWeek": "Week",
    "main.todayActivities": "TODAY'S ACTIVITIES",
    "main.weekActivities": "THIS WEEK'S ACTIVITIES",
    "manager.empty": "There are no activities yet. You can add the first one without importing a CSV.",
    "manager.title": "Manage activities",
    "notice.activityCreated": "Activity created.",
    "notice.activityCreatedLinks": "Activity created. Links applied to {count} activities.",
    "notice.activityDeleted": "Activity deleted.",
    "notice.activityMissing": "The activity no longer exists in the updated schedule.",
    "notice.changesSaved": "Changes saved.",
    "notice.changesSavedLinks": "Changes saved. Links applied to {count} activities.",
    "notice.csvPathRequired": "Select or enter the path to a CSV file.",
    "notice.importFailed": "The CSV could not be imported.",
    "notice.openingPicker": "Opening Yazi to select the CSV...",
    "notice.pickerFailed": "The file picker could not be opened.",
    "notice.previewFailed": "The CSV could not be validated.",
    "notice.readFailed": "The schedule could not be read.",
    "notice.reminderFailed": "notification check failed",
    "notice.renameSaved": "Schedule name updated.",
    "notice.revisionConflict": "The schedule changed elsewhere. Review your draft and save again.",
    "notice.saveFailed": "The change could not be saved.",
    "notice.selectionCancelled": "Selection cancelled.",
    "recurrence.once": "Once",
    "recurrence.weekly": "Weekly",
    "recurrence.biweekly": "Every two weeks",
    "recurrence.monthly": "Monthly",
    "row.prefix": "Row {row}: ",
    "dialog.deleteTitle": "Delete \"{title}\"? This action cannot be undone.",
    "dialog.deleteFallback": "Delete this activity?",
    "weekday.0": "Monday",
    "weekday.1": "Tuesday",
    "weekday.2": "Wednesday",
    "weekday.3": "Thursday",
    "weekday.4": "Friday",
    "weekday.5": "Saturday",
    "weekday.6": "Sunday"
  },
  es: {
    "common.activity": "Actividad",
    "common.addActivity": "Añadir actividad",
    "common.back": "Volver",
    "common.browse": "Buscar",
    "common.cancel": "Cancelar",
    "common.delete": "Eliminar",
    "common.links": "ENLACES",
    "common.location": "UBICACIÓN",
    "common.notes": "NOTAS",
    "common.optional": "Opcional",
    "common.save": "Guardar",
    "common.saving": "Guardando...",
    "bar.empty": "{title} - sin actividades",
    "bar.today.one": "{title} - 1 actividad hoy",
    "bar.today.other": "{title} - {count} actividades hoy",
    "count.activities.one": "1 ACTIVIDAD",
    "count.activities.other": "{count} ACTIVIDADES",
    "count.imported.one": "1 actividad importada.",
    "count.imported.other": "{count} actividades importadas.",
    "count.later.one": "+ 1 actividad posterior",
    "count.later.other": "+ {count} actividades posteriores",
    "count.ready.one": "1 actividad lista para importar.",
    "count.ready.other": "{count} actividades listas para importar.",
    "count.rows.one": "+ 1 fila",
    "count.rows.other": "+ {count} filas",
    "date.from": "Desde {start} · {end}",
    "date.inputPlaceholder": "AAAA-MM-DD",
    "date.noEnd": "sin fecha de fin",
    "date.monthDay": "día {day}",
    "date.lastMonthDay": "último día del mes",
    "details.editSeries": "Editar serie",
    "details.noLocation": "Sin ubicación.",
    "details.noNotes": "Sin notas.",
    "details.unavailable": "Esta actividad ya no está disponible.",
    "editor.activityName": "Nombre de la actividad",
    "editor.addContext": "Añade contexto o instrucciones",
    "editor.addLink": "Añadir enlace",
    "editor.allSameName": "Todos con el mismo nombre",
    "editor.allSameNameCount": "Todos con el mismo nombre ({count})",
    "editor.applyLinks": "Aplicar los enlaces a",
    "editor.editActivity": "Editar actividad",
    "editor.endDate": "Fecha de fin",
    "editor.endTime": "Hora de fin",
    "editor.link": "Enlace {number}",
    "editor.linkHelp": "Puedes añadir botones con enlaces HTTP o HTTPS.",
    "editor.linkLabel": "Etiqueta",
    "editor.linkScopeAll": "Al guardar se reemplazará la lista de enlaces de los {count} días y horarios llamados \"{title}\". Después puedes editar uno por separado.",
    "editor.linkScopeOnly": "Los enlaces aparecerán en todas las repeticiones de este día y horario.",
    "editor.linkScopeSingle": "No hay otro día u horario con este nombre. Los enlaces aparecerán en todas las repeticiones de esta actividad.",
    "editor.location": "Ubicación",
    "editor.notes": "Notas",
    "editor.lastMonthDay": "Último día del mes",
    "editor.newActivity": "Nueva actividad",
    "editor.onlyThisSlot": "Solo este día y horario",
    "editor.recurrence": "Repetición",
    "editor.removeLink": "Quitar enlace",
    "editor.startDate": "Fecha de inicio",
    "editor.startTime": "Hora de inicio",
    "editor.title": "Título",
    "editor.weekday": "Día de la semana",
    "editor.monthday": "Día del mes",
    "main.active": "EN CURSO",
    "main.browseOpen": "Abierto...",
    "main.columns": "Columnas: titulo, dia_semana, dia_mes, hora_inicio, hora_fin, repeticion, desde, hasta, ubicacion y descripcion.",
    "main.empty": "Añade una actividad o importa un CSV para empezar.",
    "main.importHeading": "IMPORTAR CSV",
    "main.importReplace": "Importar y reemplazar actividades",
    "main.importWarning": "La importación reemplaza todas las actividades. Las notas y los enlaces añadidos manualmente también se reemplazarán.",
    "main.importing": "Importando...",
    "main.manage": "Gestionar actividades",
    "main.noToday": "No hay actividades hoy. Hora de una siesta.",
    "main.noWeek": "No hay actividades esta semana. Hora de una siesta.",
    "main.noUpcoming": "No hay actividades durante los próximos 120 días.",
    "main.occurred": "OCURRIÓ",
    "main.pathPlaceholder": "/ruta/al/horario.csv",
    "main.preview": "VISTA PREVIA",
    "main.previewCsv": "Previsualizar CSV",
    "main.rename": "Renombrar horario",
    "main.saveName": "Guardar nombre",
    "main.upcoming": "PRÓXIMAS ACTIVIDADES",
    "main.validating": "Validando...",
    "main.viewDay": "Día",
    "main.viewWeek": "Semana",
    "main.todayActivities": "ACTIVIDADES DE HOY",
    "main.weekActivities": "ACTIVIDADES DE ESTA SEMANA",
    "manager.empty": "Todavía no hay actividades. Puedes añadir la primera sin importar un CSV.",
    "manager.title": "Gestionar actividades",
    "notice.activityCreated": "Actividad creada.",
    "notice.activityCreatedLinks": "Actividad creada. Enlaces aplicados a {count} actividades.",
    "notice.activityDeleted": "Actividad eliminada.",
    "notice.activityMissing": "La actividad ya no existe en el horario actualizado.",
    "notice.changesSaved": "Cambios guardados.",
    "notice.changesSavedLinks": "Cambios guardados. Enlaces aplicados a {count} actividades.",
    "notice.csvPathRequired": "Selecciona o escribe la ruta de un archivo CSV.",
    "notice.importFailed": "No se pudo importar el CSV.",
    "notice.openingPicker": "Abriendo Yazi para seleccionar el CSV...",
    "notice.pickerFailed": "No se pudo abrir el selector de archivos.",
    "notice.previewFailed": "No se pudo validar el CSV.",
    "notice.readFailed": "No se pudo leer el horario.",
    "notice.reminderFailed": "falló la comprobación de notificaciones",
    "notice.renameSaved": "Nombre del horario actualizado.",
    "notice.revisionConflict": "El horario cambió en otro lugar. Revisa tu borrador y vuelve a guardarlo.",
    "notice.saveFailed": "No se pudo guardar el cambio.",
    "notice.selectionCancelled": "Selección cancelada.",
    "recurrence.once": "Una vez",
    "recurrence.weekly": "Semanal",
    "recurrence.biweekly": "Quincenal",
    "recurrence.monthly": "Mensual",
    "row.prefix": "Fila {row}: ",
    "dialog.deleteTitle": "¿Eliminar \"{title}\"? Esta acción no se puede deshacer.",
    "dialog.deleteFallback": "¿Eliminar esta actividad?",
    "weekday.0": "Lunes",
    "weekday.1": "Martes",
    "weekday.2": "Miércoles",
    "weekday.3": "Jueves",
    "weekday.4": "Viernes",
    "weekday.5": "Sábado",
    "weekday.6": "Domingo"
  }
}

var shortWeekdays = {
  en: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
  es: ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]
}

var shortMonths = {
  en: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
  es: ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
}

var longMonths = {
  en: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"],
  es: ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
}

var dailyEncouragements = {
  en: [
    "You've got this! (=^･ω･^=)",
    "One step at a time. ฅ^•ﻌ•^ฅ",
    "Go get it, clever cat! (•ㅅ•)",
    "Today is yours. /ᐠ｡ꞈ｡ᐟ\\",
    "Steady paws, great progress. ฅ(＾・ω・＾ฅ)",
    "Small steps still count. (=｀ω´=)",
    "Ready to pounce! (ฅ`･ω･´)っ"
  ],
  es: [
    "¡Tú puedes! (=^･ω･^=)",
    "Un paso a la vez. ฅ^•ﻌ•^ฅ",
    "¡A por ello, michi! (•ㅅ•)",
    "Hoy es tuyo. /ᐠ｡ꞈ｡ᐟ\\",
    "Patitas firmes, gran progreso. ฅ(＾・ω・＾ฅ)",
    "Los pequeños pasos también cuentan. (=｀ω´=)",
    "¡Listo para saltar! (ฅ`･ω･´)っ"
  ]
}

function languageCode(value) {
  var normalized = String(value || "").trim().toLowerCase()
  return normalized === "spanish" || normalized === "español" || normalized === "es" ? "es" : "en"
}

function t(language, key, values) {
  var code = languageCode(language)
  var template = catalogs[code][key]
  if (template === undefined) template = catalogs.en[key]
  if (template === undefined) return key
  var replacements = values || {}
  return String(template).replace(/\{([^}]+)\}/g, function(match, name) {
    return Object.prototype.hasOwnProperty.call(replacements, name)
      ? String(replacements[name]) : match
  })
}

function plural(language, key, count, values) {
  var replacements = {}
  var source = values || {}
  for (var name in source) replacements[name] = source[name]
  replacements.count = count
  return t(language, key + (Number(count) === 1 ? ".one" : ".other"), replacements)
}

function recurrenceLabel(language, value) {
  var key = "recurrence." + String(value || "")
  var translated = t(language, key)
  return translated === key ? String(value || "") : translated
}

function recurrenceOptions(language) {
  return [
    { value: "once", label: t(language, "recurrence.once") },
    { value: "weekly", label: t(language, "recurrence.weekly") },
    { value: "biweekly", label: t(language, "recurrence.biweekly") },
    { value: "monthly", label: t(language, "recurrence.monthly") }
  ]
}

function weekdayLabel(language, value) {
  var index = Number(value)
  if (!isFinite(index) || index < 0 || index > 6 || Math.floor(index) !== index)
    return ""
  return t(language, "weekday." + index)
}

function weekdayOptions(language) {
  var options = []
  for (var index = 0; index < 7; index++)
    options.push({ value: String(index), label: weekdayLabel(language, index) })
  return options
}

function parsedDate(value) {
  var parts = String(value || "").split("-")
  if (parts.length !== 3) return null
  var year = Number(parts[0])
  var month = Number(parts[1]) - 1
  var day = Number(parts[2])
  var date = new Date(0)
  date.setHours(12, 0, 0, 0)
  date.setFullYear(year, month, day)
  if (date.getFullYear() !== year || date.getMonth() !== month || date.getDate() !== day)
    return null
  return date
}

function shortDate(language, value) {
  var date = parsedDate(value)
  if (!date) return String(value || "")
  var code = languageCode(language)
  if (code === "es")
    return shortWeekdays.es[date.getDay()] + " " + date.getDate() + " " + shortMonths.es[date.getMonth()]
  return shortWeekdays.en[date.getDay()] + ", " + shortMonths.en[date.getMonth()] + " " + date.getDate()
}

function longDate(language, value) {
  var date = parsedDate(value)
  if (!date) return String(value || "")
  var code = languageCode(language)
  var year = String(date.getFullYear()).padStart(4, "0")
  if (code === "es")
    return date.getDate() + " de " + longMonths.es[date.getMonth()] + " de " + year
  return longMonths.en[date.getMonth()] + " " + date.getDate() + ", " + year
}

function dailyEncouragement(language, value) {
  var date = parsedDate(value)
  if (!date) return ""
  var messages = dailyEncouragements[languageCode(language)]
  var dayNumber = Math.floor(Date.UTC(
    date.getFullYear(), date.getMonth(), date.getDate()) / 86400000)
  return messages[dayNumber % messages.length]
}
