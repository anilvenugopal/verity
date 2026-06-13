-- audit.auth_event_outcome  ·  subject: decisions  ·  (enum)

CREATE TYPE audit.auth_event_outcome AS ENUM ('success', 'failure', 'denied');
COMMENT ON TYPE audit.auth_event_outcome IS
'The result of an auth event: success, failure, or denied.

@subject decisions
@lifecycle enum';
