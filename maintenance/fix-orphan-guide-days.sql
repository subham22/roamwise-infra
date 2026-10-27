-- One-off: remove guide days left behind by deleted guides whose ids were later reused.
-- A guide's own days are its newest N rows (N = days in the slug). Aborts unless the
-- kept rows are exactly day 1..N for every guide.
\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE ranked AS
SELECT gd.id, gd.guide_id, gd.day_no, g.slug,
       row_number() OVER (PARTITION BY gd.guide_id ORDER BY gd.id DESC) AS rn,
       (regexp_match(g.slug, '-(\d+)-days$'))[1]::int AS want
FROM guide_day gd
JOIN guide g ON g.id = gd.guide_id;

DO $$
DECLARE bad text;
BEGIN
  -- every guide must keep exactly day_no 1..want, each once
  SELECT string_agg(slug, ', ') INTO bad FROM (
    SELECT slug, want
    FROM ranked WHERE rn <= want
    GROUP BY slug, want
    HAVING count(*) <> want
        OR count(DISTINCT day_no) <> want
        OR min(day_no) <> 1 OR max(day_no) <> want
  ) x;
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'Kept days are not a clean 1..N set for: %', bad;
  END IF;
END $$;

CREATE TEMP TABLE stale AS SELECT id FROM ranked WHERE rn > want;

SELECT (SELECT count(*) FROM stale) AS stale_days,
       (SELECT count(*) FROM guide_activity WHERE guide_day_id IN (SELECT id FROM stale)) AS stale_activities;

DELETE FROM guide_activity WHERE guide_day_id IN (SELECT id FROM stale);
DELETE FROM guide_day WHERE id IN (SELECT id FROM stale);

-- after: every guide has exactly the days its slug promises
SELECT count(*) FILTER (WHERE n = want) AS guides_ok, count(*) FILTER (WHERE n <> want) AS guides_wrong
FROM (SELECT g.slug, count(gd.id) AS n, (regexp_match(g.slug, '-(\d+)-days$'))[1]::int AS want
      FROM guide g LEFT JOIN guide_day gd ON gd.guide_id = g.id GROUP BY g.slug) t;

COMMIT;
