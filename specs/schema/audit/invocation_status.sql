-- audit.invocation_status  ·  subject: decisions  ·  (enum)

CREATE TYPE audit.invocation_status AS ENUM ('complete', 'error', 'timeout');
COMMENT ON TYPE audit.invocation_status IS
'The outcome of a single model call (audit.model_invocation_log): complete, error, or timeout.

@subject decisions
@lifecycle enum';
