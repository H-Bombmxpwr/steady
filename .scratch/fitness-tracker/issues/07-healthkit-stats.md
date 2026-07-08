# HealthKit two-way + Stats tab

Status: resolved
Type: task

Write weight/water/nutrition/workouts to Health (replace-then-save per day);
read steps, sleep, external weigh-ins (Garmin bridge). Stats tab with
7D/30D/90D/YTD/All/custom ranges and charts for every series + measurements.

## Answer
Done in the phase-5 commit. Garmin connects via Apple Health, not a direct API
(direct Garmin API needs an approved cloud OAuth app — out of scope for a
local-first app).
