"""Create each job/material indent once, within the caller's transaction."""
import json
import math

from psycopg2.extras import Json


class IndentSubmissionError(ValueError):
    def __init__(self, message, status_code=400):
        super().__init__(message)
        self.status_code = status_code


def submit_indents(conn, data):
    if not isinstance(data, list) or not data:
        raise IndentSubmissionError('List of indents expected')
    entries = []
    seen = set()
    for item in data:
        if not isinstance(item, dict):
            raise IndentSubmissionError('Each indent must be an object')
        identity = tuple(item.get(key) for key in ('serialNo', 'type', 'subtype'))
        if any(not isinstance(value, str) or not value.strip() for value in identity):
            raise IndentSubmissionError('serialNo, type and subtype are required')
        if identity in seen:
            raise IndentSubmissionError('The same job/material appears twice in this submission')
        seen.add(identity)
        try:
            quantity = float(item.get('quantity'))
        except (TypeError, ValueError):
            raise IndentSubmissionError('Indent quantity must be finite and positive')
        if isinstance(item.get('quantity'), bool) or not math.isfinite(quantity) or quantity <= 0:
            raise IndentSubmissionError('Indent quantity must be finite and positive')
        jobid, material_type, subtype = identity
        stock_key = f'{material_type} - {subtype}'
        if item.get('jobSpecific') is True:
            stock_key += f' - {jobid}'
        entries.append((identity, stock_key, {**item, 'quantity': quantity}))

    with conn.cursor() as cur:
        # Serialize even when no matching row exists yet. Always lock in order.
        for identity in sorted(seen):
            cur.execute(
                'SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))',
                (json.dumps(['job_indent', *identity]),),
            )
        for identity, _, _ in entries:
            cur.execute(
                """SELECT id FROM job_indents WHERE jobid = %s
                   AND data->>'type' = %s AND data->>'subtype' = %s LIMIT 1""",
                identity,
            )
            if cur.fetchone():
                jobid, material_type, subtype = identity
                raise IndentSubmissionError(
                    f'Indent already exists for {jobid}: {material_type} - {subtype}. '
                    'Refresh the job; existing indents must be updated, not added again.',
                    409,
                )

        # Atomic increments prevent lost totals across different jobs as well.
        for identity, stock_key, item in sorted(entries, key=lambda entry: (entry[1], entry[0])):
            cur.execute(
                """INSERT INTO indent_stock (key, data) VALUES (%s, %s)
                   ON CONFLICT (key) DO UPDATE SET data = jsonb_set(
                       COALESCE(indent_stock.data, '{}'::jsonb),
                       '{indentQuantity}',
                       to_jsonb(COALESCE((indent_stock.data->>'indentQuantity')::numeric, 0)
                           + (EXCLUDED.data->>'indentQuantity')::numeric))""",
                (stock_key, Json({'indentQuantity': item['quantity']})),
            )
            cur.execute(
                'INSERT INTO job_indents (jobid, data) VALUES (%s, %s)',
                (identity[0], Json(item)),
            )
