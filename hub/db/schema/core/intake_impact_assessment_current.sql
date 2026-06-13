-- core.intake_impact_assessment_current  ·  subject: intake  ·  (view)

CREATE VIEW core.intake_impact_assessment_current AS
SELECT * FROM core.intake_impact_assessment WHERE valid_to = '2099-12-31 00:00:00+00';
COMMENT ON VIEW core.intake_impact_assessment_current IS
'The current impact assessment per intake (the open SCD-2 revision) — read this instead of filtering revisions by hand (D4).

@tier 1
@lifecycle view
@subject intake
@decision D4';
