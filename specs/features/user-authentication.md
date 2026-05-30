# Feature Spec — User Authentication & Authorization

- **Status:** Draft
- **Date:** 2026-05-30
- **Related:** [[verity_v2_pcr]], [[0003-harness-governance-api]],
  [[0005-schema-hardening]], [[binding-grammar]], [[constitution]]
- **Purpose:** Replace v1's no-auth, cookie-persona demo with real identity and
  DB-managed authorization in `verity-governance`. Users authenticate via Microsoft
  Entra ID (OIDC Authorization Code + PKCE); the governance API is the single
  enforcement point for auth, validation, and audit (Principle IV); authorization is
  decoupled from the IdP and resolved from hardened, append-only tables keyed on the
  immutable `microsoft_oid`. This is a **local-dev-first** spec that calls out the
  delta for production. It is platform plumbing, not a *product* vertical slice — it
  underpins every governed surface that the equity-research slice
  ([[equity-research-slice]]) and the full API exercise.
- **Traceability:** Honors Principle I (Spec Precedes Implementation) — intent →
  decision → spec → code. Intent traces to the PCR ([[verity_v2_pcr]]): §2 *What
  Changes* moves authentication from *None* → "API keys + sessions (OIDC optional)" —
  this spec realizes that as **user OIDC sessions** (Entra) plus the harness's
  **app-scoped API credential** (FR-020). It **resolves PCR §7 Open Decision #5
  (Authentication provider) as "OIDC via external IdP = Microsoft Entra, plus an
  env-var-gated local mock-auth mode for dev/test" (FR-030)** — per product-owner
  directive 2026-05-30; the PCR §7 row is updated to match. The role taxonomy and
  action matrix trace to v1 `web/middleware/persona.py`. The SQL below is
  **illustrative**: the canonical schema lives in `specs/schema/verity_schema.sql`,
  which **does not yet exist** (schema gate, Principle II) — this spec is the source of
  the shapes until that artifact is authored. NB: where the PCR (v0.2) predates the
  hardening decisions — "schema carried verbatim" (§1/§9) and "Docker Compose for local
  dev" (§3.1) — the constitution and ADR-0005 govern, so this spec hardens the schema
  (append-only grants, renamed identifiers) and presupposes no Compose (NFR-006).

---

## User story

> As a governance user, I sign in with my Microsoft work account and land in Verity
> already known to it — my identity is provisioned on first login and my roles come
> from Verity's own records, not from my Entra groups. As an administrator, I grant and
> revoke roles in Verity and the change takes effect within seconds, with every grant
> recorded as an immutable event. As the platform, I refuse every unauthenticated or
> unauthorized call at the API boundary, fail closed to least privilege, and never
> trust a mutable email as anyone's identity.

## Domain

Platform identity and access control for the `verity-governance` service. The
authoritative identity key is the **composite `(tenant_id, microsoft_oid)`** — the Entra
`tid` plus the immutable per-user-per-tenant `oid`. Email, UPN, and
`preferred_username` are mutable, non-authoritative, and **display-only**. Two
orthogonal authorization dimensions hang off this identity:

- **Platform / governance roles** — global governance personas (carried from v1's
  `studio_role`), authorizing action codes across the governance lifecycle.
- **App-team roles** — a **v2-new** per-application dimension scoped to a specific
  `application_id`.

The composite key is *capable* of representing multiple tenants, but this deployment is
**single-tenant by enforcement**: provisioning is restricted to one configured home
tenant (FR-022). Multi-tenant operation is a future decision, not an enabled capability
here.

## Service ownership

Auth and identity belong to **`verity-governance`**. ADR-0003 ([[0003-harness-governance-api]])
makes the governance API the single enforcement point for auth/validation/audit and the
owner of every write to the Tier-1 system-of-record. Identity, role grants, and HITL
`created_by` attribution are governance-metamodel concerns. `verity-runtime` (the
execution/harness side) holds only an **application-scoped API credential**, never a
governance DB credential, and never owns central identity. `verity-vault` (document
storage) and `verity-relay` (transport seam) are out of scope for identity.

## Entities (governed by Verity)

Auth introduces no tasks or agents and therefore no Source/Target Bindings, tools, or
MCP — the [[binding-grammar]] terminology is referenced only to confirm that the
**naming gate** (one snake_case convention across schema, models, API field names, UI,
and docs; v1 names retired) applies identically to the identity/role tables defined
below. The governed entities here are the **identity principal**, the **role-grant
events** that authorize it, and the **append-only auth-event log** that records its use.

### 1. Identity principal `user`
- **Identity key:** composite `(tenant_id, microsoft_oid)`, UNIQUE. Never keyed on
  email.
- **Provenance:** created by JIT provisioning on first valid login; display fields
  (`display_name`, `email`, `upn`) upserted on each login, authoritative for **display
  only**.
- **Account state:** carries `disabled_at` — a non-null value fails the principal closed
  on the next role refresh (FR-021).
- **Notes:** carries a `session_epoch` (a.k.a. token version) bumped on any role change
  to force re-authorization (no client-held privileges).

### 2. Role grant `platform_role_grant`  *(append-only)*
- **Subject:** a `user`.
- **Grant:** one `platform_role` enum value (10 v1 values, verbatim).
- **Attribution:** `granted_by` (server-resolved, never client-supplied), `granted_at`,
  `revoked` event semantics — current roles are a **view over the latest grant/revoke
  event**, never an in-place update (Principle II, [[0005-schema-hardening]]).

### 3. Role grant `app_team_role_grant`  *(append-only, v2-new)*
- **Subject:** a `user`, scoped to a specific `application_id`.
- **Grant:** one `app_team_role` enum value (5 v2 values).
- **Notes:** no v1 equivalent — v1 had only a single session-persona and no persistent
  user→role table. Recorded as a v2 addition in the capability inventory below.

### 4. Auth event `auth_event`  *(append-only, Tier-2, v2-new)*
- **Records:** each authentication outcome (login success, login failure with
  categorized reason, logout, session expiry/termination) and each authorization denial.
- **Notes:** observability/audit substrate for compliance reconstruction (FR-024). Writes
  MUST NOT block or fail-open the request path.

### 5. Authorization decision (the action gate)
- **Input:** the principal's currently-cached platform roles + the requested action
  code; for app-scoped actions, the server-derived target `application_id`.
- **Policy:** `is_action_allowed(role, action)` over the ~20-action matrix carried
  verbatim from v1 (`web/middleware/persona.py` `_ACTION_ROLES` as behavioral
  reference). **Fail-closed:** unknown role/action, or a route with no declared action,
  → deny.
- **Notes:** role *source* changes from cookie (v1) to DB lookup (v2); the matrix and
  fail-closed behavior are unchanged.

## Architecture topology

Browser-driven OIDC Authorization Code + PKCE against a tenant-specific Entra authority;
all authorization decisions made locally in `verity-governance` against Postgres, never
derived from token claims.

```
                              verity-governance (FastAPI, localhost:8000)
                          ┌──────────────────────────────────────────────┐
 ┌─────────┐   1 GET /    │  ┌────────────────┐    ┌───────────────────┐  │
 │ Browser │─────────────▶│  │ AuthN          │    │ AuthZ middleware  │  │
 │         │              │  │ middleware     │    │ is_action_allowed │  │
 │         │  2 302 to    │  │ (session +     │    │ (~20-action matrix│  │
 │         │◀─────────────│  │  PKCE/state/   │    │  fail-closed)     │  │
 │         │   Entra      │  │  nonce mint)   │    └─────────┬─────────┘  │
 └────┬────┘              │  └───────┬────────┘              │            │
      │ 3 /authorize      │          │ 6 validate JWT        │ 7 query    │
      ▼  (code_challenge, │          │   sig RS256 / iss /   │   roles by │
 ┌──────────────┐  state, │          │   aud / exp / nonce   │   oid      │
 │  Entra ID    │  nonce  │          ▼  trusted claim = oid  ▼            │
 │  (IdP / OIDC)│         │   ┌─────────────────────────────────────┐    │
 │  JWKS, /token│◀────────┼── │  PostgreSQL (Tier-1 system-of-record)│   │
 └──────┬───────┘ 5 /token│   │  user (tenant_id, microsoft_oid)     │   │
        │ 4 302 callback  │   │  platform_role_grant (append-only)   │   │
        └────────────────▶│   │  app_team_role_grant (append-only)   │   │
          code + state    │   │  auth_event (append-only, Tier-2)    │   │
                          │   └─────────────────────────────────────┘    │
                          └──────────────────────────────────────────────┘
```

Flow: (1) browser hits a protected route; (2) governance mints `state` + `nonce` + PKCE
`code_verifier`/`code_challenge` (S256) into the **server-side session** and 302s to
Entra; (3) Entra `/authorize`; (4) callback to `http://localhost:8000/auth/callback`
with `code` + `state` (state verified against session, single-use); (5) code exchanged at
`/token` (TLS-verified) — public-client PKCE locally, confidential client in prod; (6)
**explicit** ID-token validation; (7) roles resolved by `oid` from Postgres and cached
server-side with a short TTL. The harness (`verity-runtime`) never participates in this
flow — it carries an app-scoped API credential per ADR-0003.

## Component responsibilities

| Component | Responsibility | Must NOT |
|---|---|---|
| **IdP (Entra ID)** | Authenticate the human; issue ID token with `oid`, `tid`, `exp`, `nonce`; publish JWKS. | Be a source of authorization — Entra groups/app-roles are **not** consulted. |
| **AuthN middleware** | Mint/verify single-use `state`+`nonce`+PKCE; exchange code; validate ID token (sig/iss/aud/exp/nbf/iat/nonce/`tid`/token-type); resolve trusted `oid`; JIT-provision; issue opaque server-side session; emit `auth_event`. | Trust MSAL parsing alone for authz; key on email; put roles in the cookie; reflect IdP strings or follow client-supplied redirect targets. |
| **AuthZ middleware** | Resolve the principal's cached roles; evaluate `is_action_allowed(role, action)` per the v1 matrix; derive the target `application_id` server-side; gate **every** API route and UI-serving route; deny unmapped routes; fail closed; emit denial `auth_event`. | Allow on unknown role/action or unmapped route; read roles from token claims; accept a client-supplied `application_id`. |
| **PostgreSQL (Tier-1)** | System-of-record for `user` identity and append-only role grants; current roles = view over latest grant event. Tier-2 `auth_event` log. | Mutate grants in place; hold a second identity key besides `(tenant_id, microsoft_oid)`. |

## Data model (hardened schema)

All identifiers are snake_case under the one uniform convention (Principle II); these
tables are **illustrative** here and will live in the canonical
`specs/schema/verity_schema.sql` (not yet created — schema gate, Principle II) as
**Tier-1 system-of-record**, with the `auth_event` log as **Tier-2**. Role grants are
**append-only**: a revoke is a new event, current state is a view over the latest event
per subject (and per `application_id` for app-team roles). No in-place mutation of
authorization. Stack per the constitution: psycopg v3 async + **raw SQL (no ORM)**,
Pydantic v2 models mirroring these names exactly (naming gate). The schema is **designed
for distributed scale** (HA primary/replica, horizontal `verity-governance` replicas per
[[verity_v2_pcr]] §3.1/§3.5); see *Distributed-scale design notes* below — these
constraints are normative inputs to the canonical schema, not afterthoughts.

**Enums** (one consistent enum-naming convention; lowercase snake_case members):

- `platform_role` — 10 values, carried verbatim from v1 `studio_role`:
  `business_owner`, `compliance`, `legal`, `model_risk`, `ai_governance`, `security`,
  `privacy`, `engineer`, `auditor`, `viewer`.
- **`approval_role` subset** — the 7 of the above that may sign off on governance
  approvals: `business_owner`, `compliance`, `legal`, `model_risk`, `ai_governance`,
  `security`, `privacy`. (`engineer`, `auditor`, `viewer` **cannot** sign off.) Modeled
  as the constrained subset, not a parallel free-standing enum, to keep one source of
  truth.
- `app_team_role` — 5 values, **v2-new** per-application dimension:
  `app_demo_owner`, `app_demo_sre`, `app_demo_dev`, `app_demo_lead`, `app_demo_ops`.

**Tables:**

```sql
-- identity principal; keyed on the IMMUTABLE composite, never on email.
-- Surrogate key is UUIDv7 (time-ordered, globally unique, index-friendly) so identity
-- can be minted by any governance replica without a central sequence round-trip and
-- without becoming an insert hotspot; bigint identity is rejected for that reason.
CREATE TABLE user (
    user_id        uuid        PRIMARY KEY DEFAULT uuidv7(),
    tenant_id      uuid        NOT NULL,           -- Entra tid
    microsoft_oid  uuid        NOT NULL,           -- Entra oid (immutable per tenant)
    display_name   text        NOT NULL,           -- display only (mutable)
    email          text,                            -- display only (mutable, non-key)
    upn            text,                            -- display only (mutable, non-key)
    session_epoch  integer     NOT NULL DEFAULT 0, -- bumped on any role change
    disabled_at    timestamptz,                     -- non-null => fail closed (FR-021)
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_user_tenant_oid UNIQUE (tenant_id, microsoft_oid)
);

-- platform/governance role grants — APPEND-ONLY (revoke = new event)
CREATE TABLE platform_role_grant (
    platform_role_grant_id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id        uuid          NOT NULL,
    role           platform_role NOT NULL,
    is_revocation  boolean       NOT NULL DEFAULT false,
    granted_by     uuid          NOT NULL,         -- server-resolved actor user_id
    reason         text,
    granted_at     timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT fk_platform_role_grant_user
        FOREIGN KEY (user_id)    REFERENCES user (user_id),
    CONSTRAINT fk_platform_role_grant_actor
        FOREIGN KEY (granted_by) REFERENCES user (user_id)
);
-- latest-event-per-subject lookup (drives effective-roles resolution)
CREATE INDEX ix_platform_role_grant_latest
    ON platform_role_grant (user_id, role, granted_at DESC);

-- app-team role grants — APPEND-ONLY, scoped to an application (v2-new dimension)
CREATE TABLE app_team_role_grant (
    app_team_role_grant_id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id        uuid          NOT NULL,
    application_id uuid          NOT NULL,         -- the app this grant is scoped to
    role           app_team_role NOT NULL,
    is_revocation  boolean       NOT NULL DEFAULT false,
    granted_by     uuid          NOT NULL,
    reason         text,
    granted_at     timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT fk_app_team_role_grant_user
        FOREIGN KEY (user_id)        REFERENCES user (user_id),
    CONSTRAINT fk_app_team_role_grant_actor
        FOREIGN KEY (granted_by)     REFERENCES user (user_id)
    -- fk to the application table per the hardened schema
);
CREATE INDEX ix_app_team_role_grant_latest
    ON app_team_role_grant (application_id, user_id, role, granted_at DESC);

-- auth-event audit log — APPEND-ONLY, Tier-2, high-volume.
-- RANGE-PARTITIONED by month on created_at: bounded indexes, cheap retention by
-- DETACH/DROP of old partitions, and partition pruning on time-bounded audit reads.
-- Written via the API's async/bulk ingest path (ADR-0003/0004), never inline on the
-- request hot path.
CREATE TABLE auth_event (
    auth_event_id  uuid        DEFAULT uuidv7(),
    event_type     text        NOT NULL,           -- login | logout | session_expiry | authz_denial
    outcome        text        NOT NULL,           -- success | failure | denied
    reason_code    text,                            -- bad_signature | expired | nonce_mismatch | unknown_tenant | mock_auth | ...
    user_id        uuid,                            -- nullable for pre-identity failures
    action_code    text,                            -- requested action on authz_denial
    resource       text,
    request_id     text        NOT NULL,           -- correlation id
    ip             inet,
    created_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (auth_event_id, created_at)
) PARTITION BY RANGE (created_at);
CREATE INDEX ix_auth_event_user_time ON auth_event (user_id, created_at DESC);
CREATE INDEX brin_auth_event_time    ON auth_event USING brin (created_at);
-- FK to user is intentionally omitted on the Tier-2 log to avoid a cross-tier write
-- dependency on the hot ingest path; integrity is enforced at the API layer.

-- current state is a VIEW over the latest event per subject (no in-place mutation).
-- At scale this resolves against ix_platform_role_grant_latest; if the grant history
-- grows large, it is replaced by an incrementally-maintained current_role projection
-- table updated within the same transaction as the grant insert (still append-only
-- source of truth). Either form MUST be read from the PRIMARY for authorization (see
-- design notes) — replica lag must not silently grant a revoked role.
CREATE VIEW current_platform_role AS
SELECT DISTINCT ON (user_id, role) user_id, role, is_revocation
FROM   platform_role_grant
ORDER  BY user_id, role, granted_at DESC;
-- effective roles = rows where is_revocation = false; app-team analog adds application_id
```

**Distributed-scale design notes** (normative for the canonical schema):

- **Keys.** UUIDv7 surrogate PKs (time-ordered) let any `verity-governance` replica mint
  rows without a central-sequence round-trip and without a monotonic-insert hotspot,
  while staying index-friendly. Natural identity is still the `(tenant_id,
  microsoft_oid)` unique constraint.
- **Read/write split & replica lag.** Per [[verity_v2_pcr]] §3.5 writes go to the
  primary and read-heavy UI queries to replicas. **Authorization role resolution MUST
  read from the primary** (or an equivalently fresh shared cache), because a lagging
  replica could return a role that was just revoked — violating FR-015 immediate
  revocation. Only non-authorization reads may use replicas.
- **Append-only at volume.** Grant tables stay small (one row per grant/revoke) and are
  served by the `*_latest` covering indexes. `auth_event` is the high-volume Tier-2 log:
  month-range-partitioned, BRIN on time, retention by partition DETACH/DROP, ingested via
  the API's async/bulk path so audit writes never block or fail-open the request
  (FR-024).
- **Shared session/role cache.** Multi-replica operation REQUIRES a shared session and
  role-cache store (e.g. Redis); `session_epoch` is the cross-replica invalidation signal
  and MUST live in (or be re-validated against) that shared store, never per-process
  memory. Per-process storage is local-dev-only and is a fail-closed blocker for
  multi-replica deploys (see *What changes for production*).
- **Portability.** `uuidv7()` assumes PostgreSQL 18+; on earlier majors substitute a
  UUIDv7 generation function. No logic depends on key monotonicity beyond index locality.

**Action-permission matrix.** The ~20 governance action codes (`create_intake`,
`edit_intake`, `triage_intake`, `reclassify_risk`, `edit_requirement`,
`edit_impact_assessment`, `signoff`, `withdraw_approval`, `generate_plan`, `edit_plan`,
`realize_plan`, `promote_registry`, `author_registry`, `view`, `export_yaml`,
`import_yaml`, `view_reports`, `lock_envelope`, `edit_plan_estimate`,
`edit_roi_assessment`), plus the **role-mutation actions** added by this spec
(`grant_platform_role`, `revoke_platform_role`, `grant_app_team_role`,
`revoke_app_team_role` — see FR-023), and their role mapping are the **v2 authorization
model**, hardened and DB-backed. The spec references this matrix rather than re-deriving
each cell; the behavioral source of truth is v1 `web/middleware/persona.py`
`_ACTION_ROLES`. **Every action code MUST appear in the matrix with an explicit
allowed-role set; an action absent from the matrix MUST deny (no implicit allow), and
the matrix MUST be unit-tested for total coverage of the action enum** — so "reference
v1" cannot silently import an ungated cell. The approval-by-risk-tier requirements
(`UNACCEPTABLE` → none/auto-reject; `HIGH` → 5 roles; `LIMITED` → 3 roles; `MINIMAL` →
`business_owner`) are likewise carried verbatim from v1 `intake.py`
`REQUIRED_ROLES_BY_RISK_TIER`.

The `app_team_role` action set is a **v2 addition and is NOT yet specified** — only the 5
enum values exist. A least-privilege default mapping is proposed and sequenced for
product-owner confirmation (see Open items). Until then **FR-010 is partially
specified / blocked on that open item**: the second dimension is not enforceable as
written.

## Functional requirements

1. **FR-001 — SSO login.** The system MUST authenticate users via Entra ID using the
   OIDC Authorization Code flow with **PKCE (S256)** against a tenant-specific authority
   `https://login.microsoftonline.com/{tenant_id}/v2.0`. For **local dev** the client
   SHOULD be a **public client** (PKCE-only, no client secret) so no confidential secret
   resides on a developer machine; a **confidential-client secret is used only in prod**,
   sourced from the vault/managed identity (see NFR-002a). Where a dev confidential
   secret is unavoidable it MUST be a short-lived, dev-tenant-only secret, never reused
   across developers or environments. A single local **mock-authentication** mode bypasses
   this flow for dev/test only, under the hard guardrails of FR-030.
2. **FR-002 — CSRF/replay protection.** The system MUST generate `state`, `nonce`, and
   the PKCE `code_verifier`/`code_challenge` server-side, store them in the
   browser-keyed session, verify `state` on callback, and verify `nonce` matches the
   session value. The session-bound `state`, `nonce`, and `code_verifier` MUST be
   **single-use**: consumed (deleted) atomically on the first callback and bound to a
   short expiry (≤10 min); a callback whose `state` is absent/expired/already-consumed
   MUST be rejected with no token exchange.
3. **FR-002a — Hostile callback handling.** A callback with an `error` parameter, or with
   a `code` but no matching unconsumed session `state`, MUST be rejected and MUST NOT
   initiate a token exchange, reflect IdP-supplied strings (`error_description`) into the
   response body, or redirect to any URL derived from request input — post-login redirect
   targets MUST come from a server-side allow-list.
4. **FR-003 — Localhost redirect.** The system MUST register and use redirect URI
   `http://localhost:8000/auth/callback` (plain `http` permitted by Entra only for
   `localhost`); it MUST use `localhost`, never `127.0.0.1`.
5. **FR-003a — Redirect-URI and issuer-response binding.** The `redirect_uri` presented
   at the token endpoint MUST byte-for-byte equal the registered value; the system MUST
   validate the `iss` authorization-response parameter (RFC 9207) against the configured
   authority before exchanging the code.
6. **FR-004 — Explicit token validation.** Before any local authorization decision, the
   system MUST validate the ID token explicitly:
   - **Algorithm allow-list:** validate with an explicit signing-algorithm allow-list of
     exactly `{RS256}`; the verification algorithm MUST be fixed by server configuration
     and MUST NOT be taken from the token `alg` header; any token whose `alg` is not
     exactly `RS256` (including `none`, `HS*`, `ES*`, `PS*`) MUST be rejected.
   - **Token type and audience:** the token MUST be confirmed to be the **ID token from
     the code exchange** (the `id_token` field of the `/token` response), not an access
     token; `aud` MUST equal the configured `client_id` exactly (Entra v2.0, no `api://`
     prefix); `tid` MUST equal the configured home tenant.
   - **Claims:** `iss` exact-match to the tenant issuer; `exp`/`nbf`/`iat` within ≤120s
     skew; `nonce` match.
   - **Transport:** it MUST NOT rely on MSAL parsing alone for authz.
7. **FR-004a — JWKS fetch hardening (fail-closed).** On an unknown `kid` the system MUST
   perform **at most one rate-limited JWKS refresh** from the statically-configured
   tenant JWKS URI, MUST ignore any `jku`/`x5u`/`kid`-derived URL in the token header,
   MUST cap key-cache age, and MUST **reject the token (fail closed)** if no matching key
   is found or the JWKS endpoint is unreachable (no stale-forever, no fail-open). All
   outbound calls to Entra (`/authorize` discovery, `/token`, JWKS) MUST use TLS with
   certificate verification **enabled in every environment, including local dev**, and
   the discovery/JWKS endpoints MUST be fetched only over
   `https://login.microsoftonline.com`.
8. **FR-005 — Trusted identity claim.** The system MUST treat `(tid, oid)` as the only
   authoritative identity. It MUST NOT use `email`, `preferred_username`, or `upn` as a
   key or as an authorization input.
9. **FR-006 — JIT provisioning.** On first valid login the system MUST upsert the `user`
   row, refreshing display fields. It MUST NOT provision or match on email.
10. **FR-006a — Race-safe provisioning.** JIT provisioning MUST occur via a single atomic
    `INSERT ... ON CONFLICT (tenant_id, microsoft_oid) DO UPDATE ... RETURNING user_id`
    statement (no read-then-insert). Concurrent first-logins for the same identity MUST
    resolve to exactly one `user` row; the conflict path MUST return the existing row,
    not error. This statement is the **only** code path that creates a `user` row.
11. **FR-007 — Decoupled authorization.** Roles MUST be resolved exclusively from
    `verity-governance` Postgres (`platform_role_grant` / `app_team_role_grant` views).
    The system MUST NOT derive roles from Entra groups, app-roles, or any token claim.
12. **FR-008 — Action gate, fail-closed.** Authorization MUST be action-based via
    `is_action_allowed(role, action)` over the ported ~20-action matrix; an unknown role
    or action MUST deny. The matrix and fail-closed behavior are carried verbatim from v1.
13. **FR-009 — Approval subset.** Only the 7 `approval_role` members MAY perform
    `signoff` / `withdraw_approval`; the system MUST enforce the v1
    approval-by-risk-tier required-role sets verbatim.
14. **FR-010 — App-team scope** *(partially specified — blocked on the app-team action
    set, see Open items)*. `app_team_role` grants MUST be evaluated only against actions
    on the matching `application_id`; an app-team grant MUST NOT confer platform authority
    and vice versa. The `application_id` used in an app-team authorization decision MUST
    be **derived from the target resource (server-side)**, never accepted from a
    client-supplied field, and MUST be re-verified against the resource's owning
    application on every request — a grant for application X MUST NOT authorize any action
    whose target resolves to application Y.
15. **FR-011 — Multi-role principals.** A principal MAY hold multiple platform roles and
    multiple app-team roles concurrently (v2-new; v1 allowed a single session persona).
    The effective decision is the union of allowed actions, subject to the hard
    invariant in FR-022.
16. **FR-012 — Enforce all surfaces.** Authorization MUST gate **every** governance API
    route and every UI-serving route — closing the v1 gap where personas were enforced
    only on the Studio sub-app (API + Admin were ungated). This is a tightening, not a
    capability loss.
17. **FR-013 — Server-side session.** On successful login the system MUST issue an opaque
    random session ID referenced by a signed/encrypted cookie that is `HttpOnly`,
    `SameSite=Lax`, and `Secure` (a documented dev flag MAY relax `Secure` on localhost
    only).
18. **FR-013a — Session key provenance.** The session cookie signing/encryption key MUST
    be loaded from environment/vault config (never a hardcoded or default constant), MUST
    be distinct per environment, and MUST be ≥256 bits of CSPRNG entropy. Startup MUST
    fail closed if the key is unset or a known placeholder.
19. **FR-014 — Role caching with bounded staleness.** The system MUST cache resolved
    roles server-side with a short TTL (60–300s) and re-read from DB on expiry. Roles
    MUST NOT be stored in a long-lived client cookie.
20. **FR-015 — Immediate revocation.** On any role grant/revoke — **platform OR
    app-team** — the system MUST bump the affected user's `session_epoch` (checked per
    request); the epoch bump is **required for both dimensions** and neither dimension may
    rely on TTL expiry alone for revocation. On full account deactivation (FR-021) all of
    the principal's active server-side sessions MUST be terminated, not merely
    cache-evicted.
21. **FR-016 — Session lifetime.** Sessions MUST expire at the ID-token `exp` or sooner
    and MUST NOT outlive it; token refresh MUST re-run full validation (FR-004).
22. **FR-017 — Append-only grants.** Every grant and revoke MUST be recorded as an
    immutable event with `granted_by` and `granted_at`; current roles MUST be a view over
    the latest event. No in-place mutation (Principle II). The `granted_by` value MUST be
    the **server-resolved `user_id`** of the authenticated principal and MUST NOT be
    accepted from the request body.
23. **FR-018 — Real-identity attribution.** Audit attribution previously self-asserted
    via cookie persona (`acting_as_role`, `opened_by_role`, `signoff role`,
    `locked_role`) MUST now be derived from the authenticated principal, not a
    self-selected value. HITL `created_by` and approval attribution bind to the resolved
    immutable `user_id`. Any rendering of historical `email`/`upn`/`display_name` MUST
    reflect the value **at the time of the event** (display fields are point-in-time
    unstable; audit reads bind to `user_id` only).
24. **FR-019 — Least-privilege default.** A provisioned user with no grants defaults to
    the `viewer` capability set (read-only `view`); tampered/unknown identity fails closed
    to least privilege.
25. **FR-020 — Harness boundary.** The harness (`verity-runtime`) MUST authenticate to
    governance with an application-scoped API credential and MUST NOT participate in the
    interactive OIDC flow or hold a governance DB credential (ADR-0003,
    [[0003-harness-governance-api]]).
26. **FR-021 — Account-state revalidation.** The `user` table MUST carry
    `disabled_at timestamptz NULL`. On every role refresh (cache miss / `session_epoch`
    check) a non-null `disabled_at` MUST be treated as **fail-closed** (deny all,
    terminate session). Because sessions cannot outlive ID-token `exp` (FR-016) and
    refresh re-runs full validation (FR-004), an account disabled in Entra fails the next
    refresh; a local admin-initiated `disabled_at` MUST immediately invalidate active
    sessions, analogous to the `session_epoch` mechanism.
27. **FR-022 — Tenant & guest admission.** The system MUST authenticate against a single
    tenant-specific authority and MUST reject any token whose `tid` is not the configured
    home tenant (**no `common`/`organizations` authority**). Guest/B2B principals (e.g.
    `#EXT#` UPN or external `tid`) MUST NOT be auto-provisioned above `viewer` and SHOULD
    be denied provisioning unless explicitly allow-listed; JIT provisioning of an
    unrecognized tenant MUST fail closed.
28. **FR-023 — Role-mutation authorization, anti-self-escalation, and bootstrap.** Writing
    to `platform_role_grant` / `app_team_role_grant` MUST be gated by dedicated action
    codes (`grant_platform_role`, `revoke_platform_role`, `grant_app_team_role`,
    `revoke_app_team_role`), each present as explicit matrix cells with **no default-allow
    fallback**. Platform-role mutation MUST be authorized exclusively to the `security`
    role; app-team-role mutation MUST be authorized to the matching `application_id`'s
    `app_demo_owner`/`app_demo_lead` or `security`. A principal MUST NOT grant, revoke, or
    elevate **its own** roles (`granted_by != user_id` for elevations), and the system
    MUST prevent removal of the last holder of each role-administration capability
    (anti-lockout). Initial admin bootstrap MUST be an explicit, audited, **out-of-band
    seed event** recorded as an append-only grant with a documented system actor — never
    an in-place DB edit. (This FR depends on the `admin`/`security-admin` open item below;
    that decision MUST be resolved before implementation.)
29. **FR-024 — Auth-event audit.** The system MUST record an append-only `auth_event` for
    each authentication outcome (login success; login failure with categorized reason —
    bad signature / expired / nonce-mismatch / unknown-tenant; logout; session
    expiry/termination) and for each authorization denial — **including denied
    role-mutation attempts** with actor, target, attempted role, and decision. Each record
    carries `user_id` (nullable pre-identity), action code, resource, `request_id`, source
    IP, and timestamp. Audit writes MUST NOT block or fail-open the request path, and
    failure reasons MUST NOT leak token internals to the client.
30. **FR-025 — Logout.** The system MUST expose a logout that invalidates the server-side
    session immediately and SHOULD redirect through Entra's `end_session_endpoint`.
31. **FR-026 — Idle and absolute timeout.** Sessions MUST enforce **both** an idle
    (inactivity) timeout and an absolute lifetime (≤ token `exp`), whichever is sooner.
32. **FR-027 — Auth-failure UX.** Unauthenticated requests to UI routes MUST redirect to
    login (preserving an allow-listed return URL); authenticated-but-denied requests MUST
    return **403** with a non-leaking message and the requested action, distinct from
    **401**. API routes return 401/403 JSON with a stable error code and `request_id`.
33. **FR-028 — Mid-session expiry.** On ID-token/session expiry during an active session
    the system MUST **fail closed** and re-initiate the OIDC flow (UI) or return 401
    (API); it MUST NOT silently extend authorization. **Whether a silent token refresh is
    attempted is an Open item** (see below) — until resolved, the conservative behavior
    (re-auth, no silent refresh) holds.
34. **FR-029 — Route default-deny.** The AuthZ middleware MUST deny any request to a route
    that has no declared required action (unmapped routes fail closed); route-to-action
    mapping MUST be enforced centrally so that adding a route without an action
    declaration results in denial, not bypass. A startup check SHOULD assert every
    registered route has an action mapping.
35. **FR-030 — Local mock authentication (dev/test only, env-var gated).** To support
    development and testing without a live Entra round-trip, the system MUST support a
    mock-authentication mode selected by an environment variable
    (`VERITY_AUTH_MODE=entra|mock`, default `entra`). In `mock` mode the OIDC flow
    (FR-001–FR-004a) is bypassed and a **synthetic principal** is injected from
    server-side configuration — `(tenant_id, microsoft_oid)`, display fields, and an
    explicit set of platform and app-team roles. The synthetic principal MUST then flow
    through the **same** JIT provisioning (FR-006a), role-resolution, session, and
    fail-closed action-gate paths as a real principal, so authorization is still
    exercised end-to-end. The following guardrails are MUST, non-negotiable:
    - **Never in production.** Startup MUST **fail closed (fatal)** if `VERITY_AUTH_MODE=mock`
      while `verity_env != local` (tied to NFR-001a). Mock mode is impossible to enable in
      any non-local environment; there is no runtime/request-level toggle.
    - **Config-sourced, never client-asserted.** The mock principal and its roles come
      only from server configuration; no request header, cookie, or body may set, add, or
      escalate identity or roles. A client MUST NOT be able to choose who it is.
    - **Default off & visible.** Mock mode is off by default; when active, startup MUST
      log a prominent warning and every request authenticated via mock MUST emit an
      `auth_event` with `reason_code = mock_auth` so mock sessions are unambiguous in the
      audit trail.
    - **No prod artifacts.** The mock code path MUST NOT be reachable when `verity_env=prod`
      and MUST NOT depend on test-only packages being present in the production image.

## Non-functional requirements

1. **NFR-001 — Environment isolation.** Local dev and prod MUST use **separate Entra app
   registrations** (distinct client_id/secret/redirect URIs). No prod Azure configuration
   ever resides on a dev machine.
2. **NFR-001a — Enforced environment separation.** The app MUST load an explicit
   `verity_env` (`local`|`prod`) setting and MUST **fail to start (fatal, fail-closed)**
   if the configured Entra `tenant_id`/`client_id` does not match the allow-list
   registered for that environment, or if `verity_env=local` while the redirect-URI
   scheme is `https`/non-localhost. Environment mismatch MUST be a startup error, never a
   warning.
3. **NFR-002 — Secret hygiene.** Config loads from `.env` via Pydantic `BaseSettings`;
   `.env` is git-ignored and only `.env.example` is committed. `.gitignore` MUST cover
   `.env`, `.env.*` (except `.env.example`), and any local secret/keyfile paths. Secrets
   MUST NOT be committed. Prod secrets live in a vault/managed identity, never `.env`.
   `.env.example` MUST contain only documented **placeholder** values (e.g.
   `AZURE_CLIENT_SECRET=<set-in-local-env>`) and MUST NOT contain any real `tenant_id`,
   `client_id`, secret, or redirect URI for any non-fictional tenant.
4. **NFR-002a — Public-client local dev.** Per FR-001, no confidential client secret is
   stored on a developer machine; the confidential secret exists only in prod, sourced
   from vault/managed identity, with rotation/expiry handled there.
5. **NFR-002b — Secret scanning.** The repo MUST run an automated secret scanner (e.g.
   gitleaks/trufflehog) as a **pre-commit hook and a CI gate that fails the build** on any
   detected credential, JWT, or Entra secret pattern; CI MUST also reject an
   `.env.example` whose values match the scanner patterns.
6. **NFR-002c — Log/error redaction.** Authorization codes, tokens, `code_verifier` /
   `nonce` / `state`, the client secret, and session keys MUST NOT be written to logs,
   error responses, or telemetry in any environment. Redaction is on by default; debug
   logging of token contents MUST be impossible to enable in prod config.
7. **NFR-003 — Local environment.** All work uses the project-local `.venv` (Python
   3.12), excluded from VCS; dependencies are NEVER installed globally (constitution
   Technical Standards).
8. **NFR-004 — Stack conformance.** Backend is FastAPI + psycopg v3 (async) + **raw SQL
   (no ORM)** + Pydantic v2; identity/role UI is React+TS to the design system. MSAL
   Python (`msal.ConfidentialClientApplication` in prod; public-client app for local
   dev) is the OIDC client of record, but the explicit validation controls of FR-004 /
   FR-004a are spec-level guarantees, not delegated to MSAL.
9. **NFR-005 — Performance.** A cache-hit authorization decision MUST add negligible
   latency (in-process matrix lookup, no DB round-trip); a cache-miss role refresh is a
   single bounded indexed query on `(tenant_id, microsoft_oid)` / `user_id`.
10. **NFR-006 — Deployment substrate.** Kubernetes via Helm is the source of truth and the
    production substrate. Docker Compose MAY be used as a local-dev convenience, but every
    auth component (the governance service, the shared session/role-cache store, secret
    sourcing) MUST have a clear, documented K8s/Helm equivalent and MUST NOT carry
    Compose-only assumptions into its design (constitution Technical Standards, v1.1.0).
11. **NFR-007 — Naming gate.** Every identifier (enum, table, column, FK, view, Pydantic
    field, API field, UI label, doc reference) follows the one hardened snake_case
    convention; v1 inconsistencies are not carried forward ([[0005-schema-hardening]],
    [[binding-grammar]]).
12. **NFR-008 — Auth observability baseline.** Every request MUST carry a
    correlation/request ID propagated into `auth_event` records (FR-024) and structured
    logs; auth outcomes (login result, authz allow/deny) MUST be logged at a structured
    level suitable for later metric extraction (login-failure and authz-denial rates).
    Full OTEL/Prometheus export is deferred (see Out of scope).

## Security considerations / threat model

| Threat | Mitigation (this spec) |
|---|---|
| **Account takeover via email recycling** | Identity keyed on immutable `(tenant_id, microsoft_oid)`; email is display-only (FR-005, FR-006). |
| **Authorization-code interception / injection** | PKCE S256; single-use `state`/`nonce`/`code_verifier`; exact `redirect_uri` and RFC 9207 `iss` checks (FR-002, FR-003a). |
| **CSRF / login-CSRF / hostile callback** | Single-use server-side `state`; `error`/unsolicited-`code` callbacks rejected with no token exchange, no reflected strings, allow-listed redirects only (FR-002, FR-002a). |
| **Token replay** | `nonce` bound and single-use; sessions bounded by token `exp` (FR-002, FR-016). |
| **Algorithm confusion / forged tokens** | Verifier-pinned `{RS256}` allow-list (never read from header); reject `none`/`HS*`/`ES*`/`PS*` (FR-004). |
| **Access-token substitution** | Token confirmed to be the ID token from the code exchange; exact `aud`/`tid` match (FR-004). |
| **JWKS-fetch DoS / SSRF / fail-open** | At-most-one rate-limited refresh from static JWKS URI; ignore `jku`/`x5u`; fail closed on miss/unreachable; TLS verification always on (FR-004a). |
| **Unauthorized tenant / guest provisioning** | Single home-tenant authority; `tid` allow-list; guests not auto-provisioned above `viewer` (FR-022). |
| **JIT race / duplicate users** | Single atomic upsert as sole provisioning path (FR-006a). |
| **Disabled/offboarded account retains access** | `disabled_at` fail-closed on refresh; local deactivation terminates sessions (FR-021, FR-015). |
| **Privilege escalation via stale roles** | Server-side roles, short TTL, `session_epoch` bump (both dimensions) for immediate revocation (FR-014, FR-015). |
| **Privilege freeze via client-held roles** | Roles never in cookies; opaque server-side session only (FR-013, FR-014). |
| **Ungated role-mutation / self-escalation / lockout** | Gated mutation actions, `security`-only, no self-grant, anti-lockout, audited out-of-band bootstrap (FR-023). |
| **Cross-app authority leakage** | `application_id` derived server-side from the target resource, never client-supplied (FR-010). |
| **Segregation-of-duties bypass via role union** | Approval-subset hard invariant enforced independent of the matrix (FR-022). |
| **IdP-claim trust for authz** | Authorization decoupled — DB-managed grants only, never Entra groups/claims (FR-007). |
| **Self-asserted identity in audit** | Attribution bound to authenticated principal; `granted_by` server-resolved; historical display fields are point-in-time (FR-017, FR-018). |
| **Ungated surface (v1 gap) / unmapped new route** | All API + UI routes gated; unmapped route fails closed; startup coverage check (FR-012, FR-029). |
| **Fail-open on unknown input** | Fail-closed default; least-privilege `viewer` fallback (FR-008, FR-019). |
| **Prod credential leak on dev box** | Separate app registrations; enforced env separation; public-client local dev; secret scanner; vault for prod (NFR-001/001a/002/002a/002b). |
| **Auth material in logs** | Codes/tokens/verifiers/keys redacted by default; debug token logging impossible in prod (NFR-002c). |
| **Forged session cookies** | Per-env ≥256-bit CSPRNG signing key from vault/env; fail closed if unset/placeholder (FR-013a). |
| **Multi-replica revocation bypass** | Per-process session/cache is local-dev-only; multi-replica requires a shared store, enforced as a fail-closed config gate (see "What changes for production"). |
| **Tamper of grant history** | Append-only grants; no in-place mutation; current state is a view (FR-017). |
| **Mock-auth backdoor reaching prod** | `VERITY_AUTH_MODE=mock` allowed only when `verity_env=local`; startup fails closed otherwise; config-sourced principal (never client-asserted); every mock session audited `mock_auth` (FR-030, NFR-001a). |
| **Stale role granted via replica lag** | Authorization role resolution reads the primary (or equivalently-fresh shared cache), never a lagging replica (Distributed-scale design notes, FR-015). |

## What changes for production

This spec is local-dev-first. For production: use HTTPS redirect URIs (no plain `http`)
under the **prod** Entra app registration; always set `Secure` on the session cookie
(drop the localhost dev flag); switch from the local public client to the **confidential
client**, sourcing the secret from a vault/managed identity, never `.env`; deploy
`verity-governance` on Kubernetes via Helm (no Compose). The authorization model, schema,
and validation rules are identical across environments — only configuration, transport,
and secret sourcing differ.

Per-process session and role-cache storage is a **local-dev-only** affordance.
**Production MUST use a shared session/cache store; running multi-replica on per-process
storage is a fail-closed blocker** — revocation (FR-015) and session validation would not
propagate across replicas, silently breaking enforcement. This constraint MUST be
enforced by a config gate before any non-single-process deployment.

## Capability coverage (v1 → v2 disposition)

No silent capability loss (Principle III, [[0005-schema-hardening]]): every v1 auth
capability is carried, changed, or recorded as v2-new.

| Capability | V1 mechanism | V2 disposition |
|---|---|---|
| 10-role platform taxonomy | enum `studio_role` | **KEEP** → `platform_role` (verbatim values) |
| 7-role approval subset | enum `approval_role` | **KEEP** → constrained subset |
| ~20 action codes + role map | `_ACTION_ROLES` (persona.py) | **KEEP** (port verbatim; DB-backed source of truth) |
| `is_action_allowed`, fail-closed | persona.py | **KEEP** behavior; **CHANGE** role source (DB not cookie) |
| Approval-by-risk-tier matrix | intake.py | **KEEP** verbatim |
| Persona resolution | cookie read | **CHANGE** → Entra SSO + DB role lookup |
| Identity source | none (anonymous + cookie) | **CHANGE** → Entra OIDC authenticated principal |
| User→role persistence | none | **NEW** → append-only grant tables |
| Multi-role per principal | no (single cookie value) | **NEW** (union of grants) |
| App-team role dimension | none | **NEW** → `app_team_role` scoped to `application_id` |
| Least-privilege default = viewer | persona.py | **KEEP** |
| Tamper/unknown → fail closed | persona.py | **KEEP** |
| `acting_as_role` audit capture | self-asserted persona | **KEEP** (now real identity, not self-asserted) |
| `opened_by_role` audit capture | self-asserted persona | **KEEP** (now derived from authenticated principal, FR-018) |
| `locked_role` audit capture | self-asserted persona | **KEEP** (now derived from authenticated principal, FR-018) |
| `signoff role` audit capture | self-asserted persona | **KEEP** (now derived from authenticated principal, FR-018) |
| Persona-switcher UI | `persona_switcher.html` | **DROP (with reason)** — replaced by SSO identity; no self-selection of persona |
| Studio-only enforcement (API/Admin ungated) | persona.py | **CHANGE** → gate all surfaces (security tightening, not loss) |
| `view` for all; auditor/viewer read-only | persona.py | **KEEP** |

## Acceptance scenarios

1. **Given** an unprovisioned user with a valid Entra account in the home tenant,
   **when** they complete the OIDC+PKCE login, **then** a `user` row is upserted on
   `(tenant_id, microsoft_oid)` via the single atomic provisioning path, they hold no
   grants, and they are limited to the `viewer` (`view`-only) capability set.
2. **Given** a tampered or invalid ID token (bad signature, `alg=none`/`HS*`/`ES*`, wrong
   `iss`/`aud`/`tid`, an access token rather than the ID token, expired, or mismatched
   `nonce`), **when** validation runs, **then** the request is rejected before any
   authorization decision, no session is issued, and a categorized failure `auth_event`
   is recorded.
3. **Given** an email that was reassigned to a different person in the tenant, **when**
   that person logs in, **then** they receive a distinct identity (new `oid`) and none of
   the prior holder's roles — no account takeover.
4. **Given** a user with the `engineer` platform role, **when** they attempt `signoff`,
   **then** the action is denied (engineer is not in the `approval_role` subset and the
   FR-022 hard invariant also rejects it), and a `view` action by the same user succeeds.
5. **Given** an admin revokes a user's `compliance` role, **when** the user issues their
   next request, **then** the `session_epoch` bump forces a role re-read and the revoked
   action is denied within seconds (not after TTL expiry).
6. **Given** a user holds `app_demo_dev` on application A only, **when** they attempt an
   app-team action whose target resource resolves to application B (even if they assert
   `application_id=A`), **then** it is denied — scope is derived from the resource.
7. **Given** a user holds both `model_risk` (platform) and `app_demo_lead` (app A),
   **when** they act, **then** their effective permissions are the union across both
   dimensions, scoped correctly.
8. **Given** the harness (`verity-runtime`), **when** it calls the governance API,
   **then** it authenticates with an application-scoped API credential and never enters
   the OIDC flow nor touches the governance DB.
9. **Given** a role grant, **when** it is recorded, **then** it is an immutable
   append-only event carrying the granting principal's **server-resolved** `user_id`, and
   the effective-roles view reflects only the latest event per subject.
10. **Given** an unauthenticated request to any governance API or UI route (including
    former Admin/JSON surfaces) **or** a newly added route with no declared action,
    **when** it arrives, **then** it is rejected at the boundary — no surface is ungated,
    unmapped routes fail closed.
11. **Given** a denied `signoff` (or a denied role-mutation attempt), **when** the
    decision is made, **then** an authz-denial `auth_event` is written with the principal,
    requested action, target, and decision.
12. **Given** an authenticated session, **when** the user logs out, **then** the
    server-side session is invalidated immediately and a subsequent request is
    unauthenticated.
13. **Given** a session idle past the idle timeout (or past its absolute lifetime),
    **when** the next request arrives, **then** it fails closed and re-auth is required.
14. **Given** Entra rotates signing keys (new `kid`), **when** a token signed with the new
    key arrives, **then** JWKS is refreshed once from the static URI and validation
    succeeds; **and** given an account disabled in Entra, the next refresh fails closed.
15. **Given** `VERITY_AUTH_MODE=mock` with `verity_env=local`, **when** the app starts and
    a request arrives, **then** the configured synthetic principal is JIT-provisioned and
    authorized through the normal action gate, and an `auth_event` with
    `reason_code=mock_auth` is recorded; **and given** the same `VERITY_AUTH_MODE=mock`
    with `verity_env=prod`, **when** the app starts, **then** startup aborts (fail-closed)
    and the service does not serve traffic.

## Out of scope / assumptions

- **OPEN ITEM — no superuser `admin` / `security-admin` role.** The user's original
  sketch had separate `admin` and `security-admin` roles. This authoritative role model
  has **no** superuser `admin`; the v1 `security` persona plus the role-management actions
  (FR-023) are assumed to cover security administration. This is recorded as an explicit
  **open decision for the product owner to confirm**, not silently resolved — no `admin`
  role is invented here. **FR-023's role-mutation authority depends on this decision and
  must be resolved before implementation.**
- **OPEN ITEM — app-team action set.** The five `app_team_role` values are enum-only; no
  action-permission cells exist yet. A least-privilege default mapping is proposed and
  sequenced for product-owner confirmation. Until then, **FR-010 is partially specified /
  blocked**: the app-team dimension is not enforceable as written, and this is not a
  silent deferral.
- **OPEN ITEM — silent token refresh on mid-session expiry.** FR-028 fails closed and
  re-initiates auth by default; whether a silent refresh is attempted is an explicit open
  decision, not resolved here.
- **Assumption — single IdP, single tenant.** Entra ID is the only identity provider and
  provisioning is restricted to one configured home tenant (FR-022); multi-IdP /
  federation / multi-tenant operation is out of scope. The composite key is forward-
  compatible with multi-tenant but does not enable it.
- **Assumption — admin UI for grants.** The React+TS administration surface for issuing
  and revoking grants conforms to the design system; its detailed screens are specified
  separately.
- **Deferred per constitution.** Auth/RBAC is sequenced as a committed later phase
  ([[constitution]] Principle VI; [[equity-research-slice]] lists it as
  deferred-not-dropped). Multi-replica shared session storage, full production K8s/Helm
  packaging, and Prometheus/OTEL audit-stream integration (beyond the NFR-008 baseline)
  are out of scope for this local-dev-first spec and follow as their own committed phases.
