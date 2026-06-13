-- core.run_entity_kind  ·  subject: runs  ·  (enum)

CREATE TYPE core.run_entity_kind       AS ENUM ('agent', 'task');
COMMENT ON TYPE core.run_entity_kind IS
'Whether a run executed an agent or a task. Denormalized onto execution_run and the decision log so the hot paths branch on it without joining executable_version.

@subject runs
@lifecycle enum';
