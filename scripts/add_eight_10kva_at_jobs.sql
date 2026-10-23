-- PostgreSQL / database: gew_erp
-- Latest New job checked on 2026-10-22: TRFD0743.
-- Expected next eight numbers: TRFD0744 through TRFD0751.
-- This script has NOT been executed against the database.
-- Customer names and quantities supplied by mayank; total: 45 units.
-- PO/reference fields are blank because no PO numbers were supplied.
-- Common electrical defaults match existing 10 kVA AT job TRFD0741.
-- Running this script again creates ANOTHER eight jobs; it is not idempotent.

BEGIN;

CREATE TEMP TABLE at_job_input (
    position integer PRIMARY KEY,
    purchaser text NOT NULL CHECK (btrim(purchaser) <> ''),
    po_reference text NOT NULL,
    quantity integer NOT NULL CHECK (quantity > 0)
) ON COMMIT DROP;

-- Fill PO/reference values if available before running.
-- Quantity is transformer units per job, NOT the number of job records.
INSERT INTO at_job_input (position, purchaser, po_reference, quantity)
VALUES
    (1, 'IC Electricals Manohar', '', 2),
    (2, 'DRM Guntur', '', 3),
    (3, 'GSD Begusarai Hajipur', '', 19),
    (4, 'Mahakal', '', 1),
    (5, 'Krishangini', '', 6),
    (6, 'IC Electricals Unnao', '', 2),
    (7, 'Krishangini TTRPL JV', '', 4),
    (8, 'SNS', '', 8);

-- Protect number allocation from concurrent inserts; never overwrite a job.
LOCK TABLE public.jobs IN SHARE ROW EXCLUSIVE MODE;

WITH last_job AS (
    SELECT COALESCE(MAX(substring(serial_no FROM 5)::integer), 0) AS last_number
    FROM public.jobs
    WHERE serial_no ~ '^TRFD[0-9]+$'
), numbered AS (
    SELECT i.*,
           'TRFD' || CASE
               WHEN last_number + position < 10000
                   THEN lpad((last_number + position)::text, 4, '0')
               ELSE (last_number + position)::text
           END AS job_number
    FROM at_job_input i CROSS JOIN last_job
), common_details AS (
    -- Edit these defaults if the new orders have different specifications.
    SELECT jsonb_build_object(
        'jobType', 'New',
        'kva', '10',
        'hvVoltage', '25000',
        'lvVoltage', '240',
        'phases', '1',
        'material', 'Copper',
        'vectorGroup', 'Not Applicable',
        'relevantIS', 'IS:2026',
        'tappingType', 'OCTC',
        'tappingRangeMax', '5',
        'tappingRangeMin', '-10',
        'stepVoltage', '5',
        'remark', 'AT',
        'isFinal', false,
        'createdBy', 'mayank',
        'entryDateTime', to_char(
            CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata',
            'YYYY-MM-DD"T"HH24:MI:SS.US'
        )
    ) AS data
)
INSERT INTO public.jobs (serial_no, data)
SELECT n.job_number,
       c.data || jsonb_build_object(
           'serialNo', n.job_number,
           'purchaserName', n.purchaser,
           'purchaserReference', n.po_reference,
           'quantity', n.quantity::text
       )
FROM numbered n CROSS JOIN common_details c
ORDER BY n.position
RETURNING serial_no, data;

COMMIT;
