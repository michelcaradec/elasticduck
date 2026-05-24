SET VARIABLE rows_count = 1_000_000;

CREATE OR REPLACE TABLE data AS
SELECT
  chr(65 + cast((random() * 100) % 25 AS INTEGER)) AS item,
  cast(random() * 1_000 AS INTEGER) AS x,
  cast(random() * 1_000 AS INTEGER) AS y,
  cast(random() * 1_000 AS INTEGER) AS z,
  random() AS metric_1,
  random() AS metric_2,
  random() AS metric_3,
FROM
  range(getvariable ('rows_count')::INTEGER);
