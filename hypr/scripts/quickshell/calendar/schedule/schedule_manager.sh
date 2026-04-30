#!/usr/bin/env bash
# JSON for the calendar bottom strip (header + optional timetable + deep link).
# Daily note path matches Obsidian core plugin: ~/.config/obsidian/Cyber/.obsidian/daily-notes.json
#   → folder "Notes/Daily", default filename YYYY-MM-DD.md
#
# Override vault name: export OBSIDIAN_CALENDAR_VAULT="MyVault"

python3 <<'PY'
import json
import os
from datetime import date
from urllib.parse import quote

vault = os.environ.get("OBSIDIAN_CALENDAR_VAULT", "Cyber")
day = date.today().isoformat()
rel_path = f"Notes/Daily/{day}.md"
link = f"obsidian://open?vault={vault}&file={quote(rel_path, safe='')}"

print(
    json.dumps(
        {
            "header": f"Cyber · Daily · {day}",
            "link": link,
            "lessons": [],
        },
        separators=(",", ":"),
    )
)
PY
