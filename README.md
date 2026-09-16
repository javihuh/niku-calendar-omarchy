# Recurring Schedule for Omarchy

An independent Omarchy bar plugin that imports a CSV schedule, validates it
before saving, and expands one-time, weekly, biweekly, and monthly activities.
It does not replace or modify the built-in clock or other calendar widgets.

![Recurring Schedule panel with an active class](preview.png)

## Features

- Native Omarchy bar widget and themed popup.
- Yazi file picker in an external terminal plus manual path input.
- Preview and row-level validation before an import is saved.
- One-time, weekly, biweekly, and monthly recurrence.
- Automatic accent highlight and `EN CLASE` label for the current activity.
- Native Omarchy notification five minutes before every activity.
- Comma, semicolon, and tab delimiter detection.
- Spanish and English column aliases.
- UTF-8 and Latin-1 input support.
- Local-only processing with no network requests or third-party Python packages.

## Requirements

- Omarchy Quattro with the stock Omarchy shell.
- Python 3; the helper uses only the standard library.
- `yazi` and `xdg-terminal-exec` for the optional terminal file picker. A CSV
  path can still be entered manually when either command is unavailable.
- The built-in Omarchy notification service for five-minute class reminders.

The plugin requires no elevated privileges, package manager, background daemon,
or network access.

## Install

Install and enable the plugin with:

```bash
omarchy plugin add https://github.com/javihuh/recurring-schedule-omarchy.git --enable
```

The widget defaults to the right section of the bar. Move it if desired:

```bash
omarchy bar move io.github.javihuh.schedule --section center
```

Update an installed copy with:

```bash
omarchy plugin update io.github.javihuh.schedule
```

## CSV Format

Save the file as UTF-8 CSV with this header:

```csv
titulo,dia_semana,dia_mes,hora_inicio,hora_fin,repeticion,desde,hasta,ubicacion,descripcion
Matematicas,lunes,,08:00,09:30,semanal,2026-09-21,2026-12-18,Aula 3,Clase semanal
Gimnasio,miercoles,,18:00,19:30,semanal,2026-09-23,,Centro deportivo,
Pago de alquiler,,5,09:00,09:15,mensual,2026-10-05,,Casa,Recordatorio mensual
Turno medico,,,11:00,12:00,una_vez,2026-10-14,2026-10-14,Clinica,Control
```

An editable example is included at `examples/horario.csv`.

### Columns

| Column | Required | Meaning |
| --- | --- | --- |
| `titulo` | Yes | Activity name |
| `dia_semana` | Weekly/biweekly | `lunes` through `domingo`; inferred from `desde` when empty |
| `dia_mes` | Monthly | `1` through `31` or `ultimo`; inferred from `desde` when empty |
| `hora_inicio` | Yes | Start time in 24-hour `HH:MM` format |
| `hora_fin` | Yes | End time in 24-hour `HH:MM` format |
| `repeticion` | Yes | `una_vez`, `semanal`, `quincenal`, or `mensual` |
| `desde` | Yes | First valid date in `YYYY-MM-DD` format |
| `hasta` | No | Inclusive final date; empty means no end |
| `ubicacion` | No | Location |
| `descripcion` | No | Notes |

English aliases such as `title`, `weekday`, `monthday`, `start_time`,
`end_time`, `recurrence`, `start_date`, `end_date`, `location`, and
`description` are also accepted. English recurrence values (`once`, `weekly`,
`biweekly`, and `monthly`) work as well.

Monthly day `29`, `30`, or `31` activities are skipped in months that do not
contain that date. Use `ultimo` to run an activity on every month's final day.

## Usage

1. Click the calendar icon in the Omarchy bar.
2. Select a `.csv` file or enter its path.
3. Choose **Previsualizar CSV**.
4. Correct any reported row errors.
5. Choose **Importar horario**.

Importing another CSV replaces the prior schedule atomically, so repeated
imports never create duplicate activities.

The plugin checks for upcoming classes every 30 seconds while the Omarchy shell
is running. A native notification containing the class name, time, and location
is sent during the five-minute window before the class starts. Notifications
use normal urgency and respect Do Not Disturb.

## Local Data

The imported normalized schedule is stored at:

```text
~/.local/state/omarchy/recurring-schedule/schedule.json
```

The source CSV is never modified. The stored schedule is created with user-only
permissions (`0600`).

Sent reminder occurrences are tracked in
`~/.local/state/omarchy/recurring-schedule/reminders.json` so shell reloads and
multiple monitors do not create duplicate notifications.

No schedule content is transmitted over the network. The plugin only reads the
CSV selected by the user and writes its normalized local state.

## Remove

Remove the plugin with:

```bash
omarchy plugin remove io.github.javihuh.schedule
```

Omarchy intentionally leaves imported schedule data in place. To remove that
data as well, run:

```bash
rm -r -- "$HOME/.local/state/omarchy/recurring-schedule"
```

The original CSV is never modified or removed.

## Development

Validate the manifest and run the tests:

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml
python3 -m unittest discover -s tests -v
```

The helper can also be exercised directly:

```bash
python3 schedule.py preview examples/horario.csv
python3 schedule.py import examples/horario.csv
python3 schedule.py status
python3 schedule.py remind
```

Planned import adapters include spreadsheets, iCalendar, PDF, images, and OCR.
CSV is intentionally the first format because it is deterministic and can be
fully validated before changing saved data.

## License

MIT, copyright 2026 javihuh.
