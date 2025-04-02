-- Databricks notebook source
-- CREATE WIDGET DROPDOWN scale_factor DEFAULT "10" CHOICES SELECT * FROM (VALUES ("10"), ("100"), ("1000"), ("5000"), ("10000"));
-- CREATE WIDGET TEXT tpcdi_directory DEFAULT "/Volumes/tpcdi/tpcdi_raw_data/tpcdi_volume/";
-- CREATE WIDGET TEXT wh_db DEFAULT '';
-- CREATE WIDGET TEXT catalog DEFAULT 'tpcdi';

-- COMMAND ----------

USE ${catalog}.${wh_db};
CREATE OR REPLACE TABLE DimCompany (
  ${tgt_schema}
  ${constraints}
)
TBLPROPERTIES (${tbl_props});

-- COMMAND ----------

INSERT OVERWRITE ${catalog}.${wh_db}.DimCompany
WITH cmp as (
  SELECT
    recdate,
    trim(substring(value, 1, 60)) AS CompanyName,
    trim(substring(value, 61, 10)) AS CIK,
    trim(substring(value, 71, 4)) AS Status,
    trim(substring(value, 75, 2)) AS IndustryID,
    trim(substring(value, 77, 4)) AS SPrating,
    to_date(try_to_timestamp(substring(value, 81, 8), 'yyyyMMdd')) AS FoundingDate,
    trim(substring(value, 89, 80)) AS AddrLine1,
    trim(substring(value, 169, 80)) AS AddrLine2,
    trim(substring(value, 249, 12)) AS PostalCode,
    trim(substring(value, 261, 25)) AS City,
    trim(substring(value, 286, 20)) AS StateProvince,
    trim(substring(value, 306, 24)) AS Country,
    trim(substring(value, 330, 46)) AS CEOname,
    trim(substring(value, 376, 150)) AS Description
  FROM ${catalog}.${wh_db}.stage_FinWire
  WHERE rectype = 'CMP'
)
SELECT 
  bigint(concat(date_format(effectivedate, 'yyyyMMdd'), companyid)) sk_companyid,
  companyid, 
  status, 
  name, 
  industry, 
  sprating, 
  islowgrade, 
  ceo, 
  addressline1, 
  addressline2, 
  postalcode, 
  city, 
  stateprov, 
  country, 
  description, 
  foundingdate, 
  if(enddate = date('9999-12-31'), true, false) iscurrent,
  batchid, 
  effectivedate, 
  enddate 
FROM (
  SELECT
    cast(cik as BIGINT) companyid,
    decode(cmp.status, 
      'ACTV',	'Active',
      'CMPT','Completed',
      'CNCL','Canceled',
      'PNDG','Pending',
      'SBMT','Submitted',
      'INAC','Inactive') status,
    companyname name,
    ind.in_name industry,
    if(
      SPrating IN ('AAA','AA','AA+','AA-','A','A+','A-','BBB','BBB+','BBB-','BB','BB+','BB-','B','B+','B-','CCC','CCC+','CCC-','CC','C','D'), 
      SPrating, 
      cast(null as string)) sprating, 
    CASE
      WHEN SPrating IN ('AAA','AA','A','AA+','A+','AA-','A-','BBB','BBB+','BBB-') THEN false
      WHEN SPrating IN ('BB','B','CCC','CC','C','D','BB+','B+','CCC+','BB-','B-','CCC-') THEN true
      ELSE cast(null as boolean)
      END as islowgrade, 
    ceoname ceo,
    addrline1 addressline1,
    addrline2 addressline2,
    postalcode,
    city,
    stateprovince stateprov,
    country,
    description,
    foundingdate,
    1 batchid,
    recdate effectivedate,
    coalesce(
      lead(date(recdate)) OVER (PARTITION BY cik ORDER BY recdate),
      cast('9999-12-31' as date)) enddate
  FROM cmp
  JOIN ${catalog}.${wh_db}.Industry ind ON cmp.industryid = ind.in_id
)
where effectivedate < enddate;
