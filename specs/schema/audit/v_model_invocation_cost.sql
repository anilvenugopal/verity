-- audit.v_model_invocation_cost  ·  subject: decisions  ·  (view)

-- cost = tokens × the price in effect at invocation time (joins model_price by window)
CREATE VIEW audit.v_model_invocation_cost AS
SELECT m.model_invocation_log_id, m.created_at, m.model_id,
       m.input_tokens, m.output_tokens,
       round((m.input_tokens  / 1000.0) * p.input_price_per_1k
           + (m.output_tokens / 1000.0) * p.output_price_per_1k, 6) AS cost,
       p.currency_code
FROM   audit.model_invocation_log m
LEFT   JOIN core.model_price p
       ON p.model_id = m.model_id
      AND m.created_at >= p.valid_from
      AND (m.created_at < p.valid_to);
COMMENT ON VIEW audit.v_model_invocation_cost IS
'Point-in-time cost per invocation: tokens × the price in effect at the invocation timestamp (an SCD-2 join on the model_price window). Because it joins by time, the figure stays stable even after prices are later edited — cost is computed here, never stored.

@tier 2
@lifecycle view
@subject decisions';
