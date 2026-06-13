-- core.domain_maturity_current  ·  subject: compliance  ·  (view)

CREATE VIEW core.domain_maturity_current AS
SELECT DISTINCT ON (governance_domain_code, application_id)
       governance_domain_code, application_id, score, max_tier_achieved, coverage_level_code, computed_at
FROM   core.domain_maturity
ORDER  BY governance_domain_code, application_id, computed_at DESC;
COMMENT ON VIEW core.domain_maturity_current IS
'Latest maturity snapshot per (governance domain, application scope) — the current-state projection over domain_maturity (D7).

@tier 1
@lifecycle view
@subject compliance
@decision D7';
