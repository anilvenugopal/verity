-- name: count_roles^
-- Readiness probe: reference vocab present (proves the DB is migrated + seeded).
SELECT count(*) AS n FROM reference.role;
