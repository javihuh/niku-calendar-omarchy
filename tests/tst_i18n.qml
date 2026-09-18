import QtQuick
import QtTest
import "../I18n.js" as I18n

TestCase {
  name: "ScheduleI18n"

  function test_language_normalization() {
    compare(I18n.languageCode("English"), "en")
    compare(I18n.languageCode("Español"), "es")
    compare(I18n.languageCode("unknown"), "en")
  }

  function test_catalogs_have_the_same_keys() {
    var english = Object.keys(I18n.catalogs.en).sort()
    var spanish = Object.keys(I18n.catalogs.es).sort()
    compare(JSON.stringify(spanish), JSON.stringify(english))
    for (var index = 0; index < english.length; index++) {
      var key = english[index]
      var englishFields = I18n.catalogs.en[key].match(/\{[^}]+\}/g) || []
      var spanishFields = I18n.catalogs.es[key].match(/\{[^}]+\}/g) || []
      compare(JSON.stringify(spanishFields.sort()), JSON.stringify(englishFields.sort()))
    }
  }

  function test_lookup_interpolation_and_plural() {
    compare(I18n.t("en", "common.save"), "Save")
    compare(I18n.t("es", "common.save"), "Guardar")
    compare(I18n.plural("en", "count.activities", 1), "1 ACTIVITY")
    compare(I18n.plural("es", "count.activities", 3), "3 ACTIVIDADES")
    compare(
      I18n.t("en", "editor.allSameNameCount", { count: 4 }),
      "All with the same name (4)")
    compare(
      I18n.plural("en", "bar.today", 2, { title: "Plan {count}" }),
      "Plan {count} - 2 activities today")
  }

  function test_dates_and_stable_options() {
    compare(I18n.shortDate("en", "2026-09-23"), "Wed, Sep 23")
    compare(I18n.shortDate("es", "2026-09-23"), "mié 23 sep")
    compare(I18n.longDate("en", "2026-09-23"), "September 23, 2026")
    compare(I18n.longDate("es", "2026-09-23"), "23 de septiembre de 2026")
    compare(I18n.longDate("en", "0099-09-23"), "September 23, 0099")
    compare(I18n.recurrenceOptions("en")[1].value, "weekly")
    compare(I18n.recurrenceOptions("es")[1].label, "Semanal")
    compare(I18n.weekdayOptions("en")[2].value, "2")
    compare(I18n.weekdayOptions("es")[2].label, "Miércoles")
  }
}
