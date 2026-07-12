# Today range in Body/Food stats

Status: resolved
Type: small feature (2026-07-12)

User request: Body and Food stats should also have a Today option.

## Resolution

- `StatsRange` gains `.day` ("Today") as the first segment; interval is
  (startOfToday, startOfToday). Both tabs share the range picker, so
  Body and Food each get it. Single-day bar charts render fine; the
  weight trend needs 2+ points and shows its empty hint instead.

Build: ** BUILD SUCCEEDED **.
