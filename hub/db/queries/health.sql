-- name: count_roles$
-- Readiness probe: reference vocab present (proves the DB is migrated + seeded).
SELECT count(*) FROM reference.role;
