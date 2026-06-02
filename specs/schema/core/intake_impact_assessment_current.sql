-- core.intake_impact_assessment_current  ·  subject: intake  ·  (view)

CREATE VIEW core.intake_impact_assessment_current AS
SELECT * FROM core.intake_impact_assessment WHERE valid_to IS NULL;
