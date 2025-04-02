-- Databricks notebook source
CREATE OR REPLACE TABLE ${catalog}.${wh_db}.Prospect (
  ${tgt_schema}
  ${constraints}
)
TBLPROPERTIES (${tbl_props});

-- COMMAND ----------

INSERT OVERWRITE ${catalog}.${wh_db}.Prospect
with cust as (
  SELECT 
    lastname,
    firstname,
    addressline1,
    addressline2,
    postalcode
  FROM ${catalog}.${wh_db}.DimCustomer
  WHERE iscurrent
)
SELECT 
  agencyid,
  bigint(date_format(recdate.batchdate, 'yyyyMMdd')) sk_recorddateid,
  bigint(date_format(origdate.batchdate, 'yyyyMMdd')) sk_updatedateid,
  p.batchid,
  nvl2(c.LastName, True, False) iscustomer, 
  p.lastname,
  p.firstname,
  p.middleinitial,
  p.gender,
  p.addressline1,
  p.addressline2,
  p.postalcode,
  city,
  state,
  country,
  phone,
  income,
  numbercars,
  numberchildren,
  maritalstatus,
  age,
  creditrating,
  ownorrentflag,
  employer,
  numbercreditcards,
  networth,
  marketingnameplate
FROM ${catalog}.${wh_db}.stage_ProspectIncremental p
JOIN ${catalog}.${wh_db}.BatchDate recdate
  ON p.recordbatchid = recdate.batchid
JOIN ${catalog}.${wh_db}.BatchDate origdate
  ON p.batchid = origdate.batchid
LEFT JOIN cust c
  ON 
    upper(p.LastName) = upper(c.lastname)
    and upper(p.FirstName) = upper(c.firstname)
    and upper(p.AddressLine1) = upper(c.addressline1)
    and upper(nvl(p.addressline2, '')) = upper(nvl(c.addressline2, ''))
    and upper(p.PostalCode) = upper(c.postalcode)
