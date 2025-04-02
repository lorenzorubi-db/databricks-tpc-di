-- Databricks notebook source
-- CREATE WIDGET DROPDOWN scale_factor DEFAULT "10" CHOICES SELECT * FROM (VALUES ("10"), ("100"), ("1000"), ("5000"), ("10000"));
-- CREATE WIDGET TEXT tpcdi_directory DEFAULT "/Volumes/tpcdi/tpcdi_raw_data/tpcdi_volume/";
-- CREATE WIDGET TEXT wh_db DEFAULT '';
-- CREATE WIDGET TEXT catalog DEFAULT 'tpcdi';

-- COMMAND ----------

USE ${catalog}.${wh_db};
CREATE OR REPLACE TABLE FactWatches (
  ${tgt_schema}
  ${constraints}
)
TBLPROPERTIES (${tbl_props});

-- COMMAND ----------

INSERT OVERWRITE ${catalog}.${wh_db}.FactWatches
with watchhistory AS (
  SELECT
    *,
    1 batchid
  FROM read_files(
    "${tpcdi_directory}sf=${scale_factor}/Batch1",
    format => "csv",
    inferSchema => False,
    header => False,
    sep => "|",
    fileNamePattern => "WatchHistory.txt",
    schema => "w_c_id BIGINT, w_s_symb STRING, w_dts TIMESTAMP, w_action STRING"
  )
  UNION ALL
  SELECT
    * except(cdc_flag, cdc_dsn),
    int(substring(_metadata.file_path FROM (position('/Batch', _metadata.file_path) + 6) FOR 1)) batchid
  FROM
    read_files(
      "${tpcdi_directory}sf=${scale_factor}/Batch{2,3}",
      format => "csv",
      inferSchema => False,
      header => False,
      sep => "|",
      fileNamePattern => "WatchHistory.txt",
      schema => "cdc_flag STRING, cdc_dsn BIGINT, w_c_id BIGINT, w_s_symb STRING, w_dts TIMESTAMP, w_action STRING"
    )
),
watches as (
  SELECT 
    wh.w_c_id customerid,
    wh.w_s_symb symbol,        
    date(min(w_dts)) dateplaced,
    date(max(if(w_action = 'CNCL', w_dts, null))) dateremoved,
    min(batchid) batchid
  FROM watchhistory wh
  GROUP BY 
    w_c_id,
    w_s_symb
)
select
  c.sk_customerid sk_customerid,
  s.sk_securityid sk_securityid,
  bigint(date_format(dateplaced, 'yyyyMMdd')) sk_dateid_dateplaced,
  bigint(date_format(dateremoved, 'yyyyMMdd')) sk_dateid_dateremoved,
  wh.batchid 
from watches wh
JOIN ${catalog}.${wh_db}.DimSecurity s
  ON 
    s.symbol = wh.symbol
    AND wh.dateplaced >= s.effectivedate 
    AND wh.dateplaced < s.enddate
JOIN ${catalog}.${wh_db}.DimCustomer c
  ON
    wh.customerid = c.customerid
    AND wh.dateplaced >= c.effectivedate 
    AND wh.dateplaced < c.enddate
