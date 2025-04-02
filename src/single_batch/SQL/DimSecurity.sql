-- Databricks notebook source
-- CREATE WIDGET DROPDOWN scale_factor DEFAULT "10" CHOICES SELECT * FROM (VALUES ("10"), ("100"), ("1000"), ("5000"), ("10000"));
-- CREATE WIDGET TEXT tpcdi_directory DEFAULT "/Volumes/tpcdi/tpcdi_raw_data/tpcdi_volume/";
-- CREATE WIDGET TEXT wh_db DEFAULT '';
-- CREATE WIDGET TEXT catalog DEFAULT 'tpcdi';

-- COMMAND ----------

USE ${catalog}.${wh_db};
CREATE OR REPLACE TABLE DimSecurity (
  ${tgt_schema}
  ${constraints}
)
TBLPROPERTIES (${tbl_props});

-- COMMAND ----------

INSERT OVERWRITE ${catalog}.${wh_db}.DimSecurity
WITH SEC as (
  SELECT
    recdate AS effectivedate,
    trim(substring(value, 1, 15)) AS Symbol,
    trim(substring(value, 16, 6)) AS issue,
    trim(substring(value, 22, 4)) AS Status,
    trim(substring(value, 26, 70)) AS Name,
    trim(substring(value, 96, 6)) AS exchangeid,
    cast(substring(value, 102, 13) as BIGINT) AS sharesoutstanding,
    to_date(substring(value, 115, 8), 'yyyyMMdd') AS firsttrade,
    to_date(substring(value, 123, 8), 'yyyyMMdd') AS firsttradeonexchange,
    cast(substring(value, 131, 12) AS DOUBLE) AS Dividend,
    trim(substring(value, 143, 60)) AS conameorcik
  FROM ${catalog}.${wh_db}.stage_FinWire
  WHERE rectype = 'SEC'
),
dc as (
  SELECT 
    sk_companyid,
    name conameorcik,
    EffectiveDate,
    EndDate
  FROM ${catalog}.${wh_db}.DimCompany
  UNION ALL
  SELECT 
    sk_companyid,
    cast(companyid as string) conameorcik,
    EffectiveDate,
    EndDate
  FROM ${catalog}.${wh_db}.DimCompany
),
SEC_prep AS (
  SELECT 
    SEC.* except(Status, conameorcik),
    nvl(string(try_cast(conameorcik as bigint)), conameorcik) conameorcik,
    decode(status, 
      'ACTV',	'Active',
      'CMPT','Completed',
      'CNCL','Canceled',
      'PNDG','Pending',
      'SBMT','Submitted',
      'INAC','Inactive') status,
    coalesce(
      lead(effectivedate) OVER (
        PARTITION BY symbol
        ORDER BY effectivedate),
      date('9999-12-31')
    ) enddate
  FROM SEC
),
SEC_final AS (
  SELECT
    SEC.Symbol,
    SEC.issue,
    SEC.status,
    SEC.Name,
    SEC.exchangeid,
    dc.sk_companyid,
    SEC.sharesoutstanding,
    SEC.firsttrade,
    SEC.firsttradeonexchange,
    SEC.Dividend,
    if(SEC.effectivedate < dc.effectivedate, dc.effectivedate, SEC.effectivedate) effectivedate,
    if(SEC.enddate > dc.enddate, dc.enddate, SEC.enddate) enddate
  FROM SEC_prep SEC
  JOIN dc 
  ON
    SEC.conameorcik = dc.conameorcik 
    AND SEC.EffectiveDate < dc.EndDate
    AND SEC.EndDate > dc.EffectiveDate
)
SELECT 
  monotonically_increasing_id() sk_securityid,
  Symbol,
  issue,
  status,
  Name,
  exchangeid,
  sk_companyid,
  sharesoutstanding,
  firsttrade,
  firsttradeonexchange,
  Dividend,
  if(enddate = date('9999-12-31'), true, false) iscurrent,
  1 batchid,
  effectivedate,
  enddate
FROM SEC_final
WHERE effectivedate < enddate;
