-- audit.auth_event_type  ·  subject: decisions  ·  (enum)

CREATE TYPE audit.auth_event_type   AS ENUM ('login', 'logout', 'session_expiry', 'session_termination', 'authz_denial');
