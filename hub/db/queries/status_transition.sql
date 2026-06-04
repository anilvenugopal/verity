-- audit.status_transition — the single append-only history of every mutable *_status_code change
-- (D4). This slice appends one row per intake status change. entity_type/status_field are fixed
-- for intake here; from_code/to_code/actor/acting-role come from the change. Written in the SAME
-- transaction as the core.intake UPDATE (D-INT-1) so the row exists iff the status actually moved.

-- name: insert_status_transition!
INSERT INTO audit.status_transition
    (entity_type, entity_id, status_field, from_code, to_code, actor_id, acting_role_code, reason)
VALUES
    ('intake', %(entity_id)s, 'intake_status_code', %(from_code)s, %(to_code)s,
     %(actor_id)s, %(acting_role_code)s, %(reason)s);
