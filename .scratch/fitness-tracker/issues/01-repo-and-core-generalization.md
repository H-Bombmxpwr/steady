# Repo restructure + core generalization

Status: resolved
Type: task

Move .git to repo root; organize source folders. Replace hardcoded 75 Hard with
plan-based models (UserProfile/Plan/DayLog), Mifflin-St Jeor TDEE engine, and a
4-step onboarding.

## Answer
Done in commits 85aaf5b, b5ea4be, 3d41cda. New store file Fitness.store;
legacy store left on disk; photos dir unchanged.
