-- core.outbox_status  ·  subject: runs  ·  (enum)

CREATE TYPE core.outbox_status         AS ENUM ('pending', 'published', 'claimed', 'failed');
