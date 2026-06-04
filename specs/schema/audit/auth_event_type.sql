-- audit.auth_event_type  ·  subject: decisions  ·  (enum)

CREATE TYPE audit.auth_event_type   AS ENUM ('login', 'logout', 'session_expiry', 'session_termination', 'authz_denial');
COMMENT ON TYPE audit.auth_event_type IS
'The kind of authentication/authorization event (audit.auth_event).

@subject decisions
@lifecycle enum';
