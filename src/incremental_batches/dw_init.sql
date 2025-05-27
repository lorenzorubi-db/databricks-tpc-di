-- Databricks notebook source
-- CREATE WIDGET DROPDOWN scale_factor DEFAULT "10" CHOICES SELECT * FROM (VALUES ("10"), ("100"), ("1000"), ("5000"), ("10000"));
-- CREATE WIDGET TEXT tpcdi_directory DEFAULT "/Volumes/tpcdi/tpcdi_raw_data/tpcdi_volume/";
-- CREATE WIDGET TEXT wh_db DEFAULT '';
-- CREATE WIDGET TEXT catalog DEFAULT 'tpcdi';
-- CREATE WIDGET DROPDOWN pred_opt DEFAULT "DISABLE" CHOICES SELECT * FROM (VALUES ("ENABLE"), ("DISABLE")); -- Predictive Optimization

-- COMMAND ----------

-- MAGIC %md
-- MAGIC # Reset/Create Catalog and Database

-- COMMAND ----------

SET timezone = Etc/UTC;
DROP DATABASE IF EXISTS ${catalog}.${wh_db}_${scale_factor} cascade;
CREATE DATABASE ${catalog}.${wh_db}_${scale_factor};
CREATE DATABASE IF NOT EXISTS ${catalog}.${wh_db}_${scale_factor}_stage;
DROP TABLE IF EXISTS ${catalog}.${wh_db}_${scale_factor}_stage.finwire;
DROP TABLE IF EXISTS ${catalog}.${wh_db}_${scale_factor}_stage.CustomerIncremental;
DROP TABLE IF EXISTS ${catalog}.${wh_db}_${scale_factor}_stage.ProspectIncremental;
DROP TABLE IF EXISTS ${catalog}.${wh_db}_${scale_factor}_stage.AccountIncremental;
DROP TABLE IF EXISTS ${catalog}.${wh_db}_${scale_factor}_stage.WatchIncremental;
DROP TABLE IF EXISTS ${catalog}.${wh_db}_${scale_factor}_stage.DailyMarketIncremental;
DROP TABLE IF EXISTS ${catalog}.${wh_db}_${scale_factor}_stage.CashTransactionIncremental;
DROP TABLE IF EXISTS ${catalog}.${wh_db}_${scale_factor}_stage.HoldingIncremental;
DROP TABLE IF EXISTS ${catalog}.${wh_db}_${scale_factor}_stage.TradeIncremental;
DROP TABLE IF EXISTS ${catalog}.${wh_db}_${scale_factor}_stage.CompanyFinancialsStg;
-- Enable Predictive Optimization for those workspaces that it is available
ALTER DATABASE ${catalog}.${wh_db}_${scale_factor} ${pred_opt} PREDICTIVE OPTIMIZATION;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Just create a view over the top of the audit files - no reason to ingest

-- COMMAND ----------

CREATE OR REPLACE VIEW ${catalog}.${wh_db}_${scale_factor}.Audit (
  dataset COMMENT 'Component the data is associated with', 
  batchid COMMENT 'BatchID the data is associated with', 
  date COMMENT 'Date value corresponding to the Attribute', 
  attribute COMMENT 'Attribute this row of data corresponds to', 
  value COMMENT 'Integer value corresponding to the Attribute', 
  dvalue COMMENT 'Decimal value corresponding to the Attribute'
) AS SELECT *
FROM 
  read_files(
  "${tpcdi_directory}sf=${scale_factor}/*",
  format => "csv",
  inferSchema => False, 
  header => True,
  sep => ",",
  fileNamePattern => "*_audit.csv", 
  schema => "dataset STRING, batchid INT, date DATE, attribute STRING, value BIGINT, dvalue DECIMAL(15,5)"
)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC # Create Empty Tables

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.DIMessages (
  MessageDateAndTime TIMESTAMP COMMENT 'Date and time of the message', 
  BatchId INT COMMENT 'DI run number; see the section Overview of BatchID usage', 
  MessageSource STRING COMMENT 'Typically the name of the transform that logs the message', 
  MessageText STRING COMMENT 'Description of why the message was logged', 
  MessageType STRING COMMENT 'Status or Alert or Reject', 
  MessageData STRING COMMENT 'Varies with the reason for logging the message'
);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}_stage.FinWire (
  rectype STRING COMMENT 'Indicates the type of table into which this record will eventually be parsed: CMP FIN or SEC',
  recdate date COMMENT 'Date of the record',
  value STRING COMMENT 'Pre-parsed String Values of all FinWire files'
) 
PARTITIONED BY (rectype)
TBLPROPERTIES ('delta.dataSkippingNumIndexedCols' = 0, 'delta.autoOptimize.autoCompact'=False, 'delta.autoOptimize.optimizeWrite'=True);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}_stage.WatchIncremental (
  w_c_id BIGINT COMMENT 'Customer identifier',
  w_s_symb STRING COMMENT 'Symbol of the security to watch',
  w_dts TIMESTAMP COMMENT 'Date and Time Stamp for the action',
  w_action STRING COMMENT 'Whether activating or canceling the watch',
  batchid INT COMMENT 'Batch ID when this record was inserted'
) PARTITIONED BY (batchid);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}_stage.DailyMarketIncremental (
  dm_date DATE COMMENT 'Date of last completed trading day',
  dm_s_symb STRING COMMENT 'Security symbol of the security',
  dm_close DOUBLE COMMENT 'Closing price of the security on this day',
  dm_high DOUBLE COMMENT 'Highest price for the security on this day',
  dm_low DOUBLE COMMENT 'Lowest price for the security on this day',
  dm_vol INT COMMENT 'Volume of the security on this day',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  fiftytwoweekhigh DOUBLE COMMENT 'Security highest price in last 52 weeks from this day',
  sk_fiftytwoweekhighdate BIGINT COMMENT 'Earliest date on which the 52 week high price was set',
  fiftytwoweeklow DOUBLE COMMENT 'Security lowest price in last 52 weeks from this day',
  sk_fiftytwoweeklowdate BIGINT COMMENT 'Earliest date on which the 52 week low price was set'
) PARTITIONED BY (batchid);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}_stage.CashTransactionIncremental (
  accountid BIGINT COMMENT 'Customer account identifier',
  datevalue DATE COMMENT 'Date of the Customer Account Balance',
  cash DOUBLE COMMENT 'Cash balance for the account at end of day',
  batchid INT COMMENT 'Batch ID when this record was inserted'
) PARTITIONED BY (batchid);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}_stage.HoldingIncremental (
  hh_h_t_id INT COMMENT 'Trade Identifier of the trade that originally created the holding row.',
  hh_t_id INT COMMENT 'Trade Identifier of the current trade',
  hh_before_qty INT COMMENT 'Quantity of this security held before the modifying trade.',
  hh_after_qty INT COMMENT 'Quantity of this security held after the modifying trade.',
  batchid INT COMMENT 'Batch ID when this record was inserted'
) PARTITIONED BY (batchid);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}_stage.TradeIncremental (
  tradeid BIGINT COMMENT 'Trade identifier.',
  t_dts TIMESTAMP COMMENT 'Date and time of trade.',
  create_ts TIMESTAMP,
  close_ts TIMESTAMP,
  status STRING COMMENT 'Status type identifier',
  type STRING COMMENT 'Trade type identifier',
  cashflag BOOLEAN COMMENT 'Is this trade a cash or margin trade?',
  t_s_symb STRING COMMENT 'Security symbol of the security',
  quantity INT COMMENT 'Quantity of securities traded.',
  bidprice DOUBLE COMMENT 'The requested unit price.',
  t_ca_id BIGINT COMMENT 'Customer account identifier.',
  executedby STRING COMMENT 'Name of the person executing the trade.',
  tradeprice DOUBLE COMMENT 'Unit price at which the security was traded.',
  fee DOUBLE COMMENT 'Fee charged for placing this trade request.',
  commission DOUBLE COMMENT 'Commission earned on this trade',
  tax DOUBLE COMMENT 'Amount of tax due on this trade',
  batchid INT COMMENT 'Batch ID when this record was inserted'
) PARTITIONED BY (batchid);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}_stage.AccountIncremental (
  accountid BIGINT COMMENT 'Customer account identifier', 
  brokerid BIGINT COMMENT 'Identifier of the managing broker', 
  customerid BIGINT COMMENT 'Owning customer identifier', 
  accountDesc STRING COMMENT 'Name of customer account', 
  taxstatus TINYINT COMMENT 'Tax status of this account', 
  status STRING COMMENT 'Customer status type identifier',
  batchid INT COMMENT 'Batch ID when this record was inserted'
) PARTITIONED BY (batchid);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}_stage.CustomerIncremental (
  customerid BIGINT COMMENT 'Customer identifier',
  taxid STRING COMMENT 'Customer’s tax identifier',
  status STRING COMMENT 'Customer status type identifier',
  lastname STRING COMMENT 'Primary Customers last name.',
  firstname STRING COMMENT 'Primary Customers first name.',
  middleinitial STRING COMMENT 'Primary Customers middle initial',
  gender STRING COMMENT 'Gender of the primary customer',
  tier TINYINT COMMENT 'Customer tier',
  dob DATE COMMENT 'Customer’s date of birth as YYYY-MM-DD.',
  addressline1 STRING COMMENT 'Address Line 1',
  addressline2 STRING COMMENT 'Address Line 2',
  postalcode STRING COMMENT 'Zip or postal code',
  city STRING COMMENT 'City',
  stateprov STRING COMMENT 'State or province',
  country STRING COMMENT 'Country',
  phone1 STRING COMMENT 'Phone number 1',
  phone2 STRING COMMENT 'Phone number 2',
  phone3 STRING COMMENT 'Phone number 3',
  email1 STRING COMMENT 'Email address 1',
  email2 STRING COMMENT 'Email address 2',
  lcl_tx_id STRING COMMENT 'Customers local tax rate',
  nat_tx_id STRING COMMENT 'Customers national tax rate',
  batchid INT COMMENT 'Batch ID when this record was inserted'
) PARTITIONED BY (batchid);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}_stage.ProspectIncremental (
  agencyid STRING COMMENT 'Unique identifier from agency',
  lastname STRING COMMENT 'Last name',
  firstname STRING COMMENT 'First name',
  middleinitial STRING COMMENT 'Middle initial',
  gender STRING COMMENT '‘M’ or ‘F’ or ‘U’',
  addressline1 STRING COMMENT 'Postal address',
  addressline2 STRING COMMENT 'Postal address',
  postalcode STRING COMMENT 'Postal code',
  city STRING COMMENT 'City',
  state STRING COMMENT 'State or province',
  country STRING COMMENT 'Postal country',
  phone STRING COMMENT 'Telephone number',
  income STRING COMMENT 'Annual income',
  numbercars INT COMMENT 'Cars owned',
  numberchildren INT COMMENT 'Dependent children',
  maritalstatus STRING COMMENT '‘S’ or ‘M’ or ‘D’ or ‘W’ or ‘U’',
  age INT COMMENT 'Current age',
  creditrating INT COMMENT 'Numeric rating',
  ownorrentflag STRING COMMENT '‘O’ or ‘R’ or ‘U’',
  employer STRING COMMENT 'Name of employer',
  numbercreditcards INT COMMENT 'Credit cards',
  networth INT COMMENT 'Estimated total net worth',
  marketingnameplate STRING COMMENT 'Marketing nameplate',
  recordbatchid INT NOT NULL COMMENT 'Batch ID when this record last inserted',
  batchid INT COMMENT 'Batch ID when this record was initially inserted'
) PARTITIONED BY (batchid);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.TaxRate (
  tx_id STRING NOT NULL COMMENT 'Tax rate code',
  tx_name STRING COMMENT 'Tax rate description',
  tx_rate FLOAT COMMENT 'Tax rate',
  CONSTRAINT taxrate_pk PRIMARY KEY(tx_id)
);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.BatchDate (
  batchdate DATE NOT NULL COMMENT 'Batch date',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  CONSTRAINT batchdate_pk PRIMARY KEY(batchdate)
);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.DimDate (
  sk_dateid BIGINT NOT NULL COMMENT 'Surrogate key for the date',
  datevalue DATE COMMENT 'The date stored appropriately for doing comparisons in the Data Warehouse',
  datedesc STRING COMMENT 'The date in full written form e.g. July 7 2004',
  calendaryearid INT COMMENT 'Year number as a number',
  calendaryeardesc STRING COMMENT 'Year number as text',
  calendarqtrid INT COMMENT 'Quarter as a number e.g. 20042',
  calendarqtrdesc STRING COMMENT 'Quarter as text e.g. 2004 Q2',
  calendarmonthid INT COMMENT 'Month as a number e.g. 20047',
  calendarmonthdesc STRING COMMENT 'Month as text e.g. 2004 July',
  calendarweekid INT COMMENT 'Week as a number e.g. 200428',
  calendarweekdesc STRING COMMENT 'Week as text e.g. 2004-W28',
  dayofweeknum INT COMMENT 'Day of week as a number e.g. 3',
  dayofweekdesc STRING COMMENT 'Day of week as text e.g. Wednesday',
  fiscalyearid INT COMMENT 'Fiscal year as a number e.g. 2005',
  fiscalyeardesc STRING COMMENT 'Fiscal year as text e.g. 2005',
  fiscalqtrid INT COMMENT 'Fiscal quarter as a number e.g. 20051',
  fiscalqtrdesc STRING COMMENT 'Fiscal quarter as text e.g. 2005 Q1',
  holidayflag BOOLEAN COMMENT 'Indicates holidays',
  CONSTRAINT dimdate_pk PRIMARY KEY(sk_dateid)
);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.DimTime (
  sk_timeid BIGINT NOT NULL COMMENT 'Surrogate key for the time',
  timevalue STRING COMMENT 'The time stored appropriately for doing',
  hourid INT COMMENT 'Hour number as a number e.g. 01',
  hourdesc STRING COMMENT 'Hour number as text e.g. 01',
  minuteid INT COMMENT 'Minute as a number e.g. 23',
  minutedesc STRING COMMENT 'Minute as text e.g. 01:23',
  secondid INT COMMENT 'Second as a number e.g. 45',
  seconddesc STRING COMMENT 'Second as text e.g. 01:23:45',
  markethoursflag BOOLEAN COMMENT 'Indicates a time during market hours',
  officehoursflag BOOLEAN COMMENT 'Indicates a time during office hours',
  CONSTRAINT dimtime_pk PRIMARY KEY(sk_timeid)
);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.StatusType (
  st_id STRING COMMENT 'Status code',
  st_name STRING NOT NULL COMMENT 'Status description',
  CONSTRAINT statustype_pk PRIMARY KEY(st_name)
);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.industry (
  in_id STRING COMMENT 'Industry code',
  in_name STRING NOT NULL COMMENT 'Industry description',
  in_sc_id STRING COMMENT 'Sector identifier',
  CONSTRAINT industry_pk PRIMARY KEY(in_name)
);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.TradeType (
  tt_id STRING NOT NULL COMMENT 'Trade type code',
  tt_name STRING COMMENT 'Trade type description',
  tt_is_sell INT COMMENT 'Flag indicating a sale',
  tt_is_mrkt INT COMMENT 'Flag indicating a market order',
  CONSTRAINT tradetype_pk PRIMARY KEY(tt_id)
);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.DimBroker (
  sk_brokerid BIGINT NOT NULL COMMENT 'Surrogate key for broker',
  brokerid BIGINT COMMENT 'Natural key for broker',
  managerid BIGINT COMMENT 'Natural key for manager’s HR record',
  firstname STRING COMMENT 'First name',
  lastname STRING COMMENT 'Last Name',
  middleinitial STRING COMMENT 'Middle initial',
  branch STRING COMMENT 'Facility in which employee has office',
  office STRING COMMENT 'Office number or description',
  phone STRING COMMENT 'Employee phone number',
  iscurrent BOOLEAN COMMENT 'True if this is the current record',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  effectivedate DATE COMMENT 'Beginning of date range when this record was the current record',
  enddate DATE COMMENT 'Ending of date range when this record was the current record. A record that is not expired will use the date 9999-12-31.',
  CONSTRAINT dimbroker_pk PRIMARY KEY(sk_brokerid)
);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.DimCustomer (
  sk_customerid BIGINT NOT NULL COMMENT 'Surrogate key for CustomerID',
  customerid BIGINT COMMENT 'Customer identifier',
  taxid STRING COMMENT 'Customer’s tax identifier',
  status STRING COMMENT 'Customer status type',
  lastname STRING COMMENT 'Customers last name.',
  firstname STRING COMMENT 'Customers first name.',
  middleinitial STRING COMMENT 'Customers middle name initial',
  gender STRING COMMENT 'Gender of the customer',
  tier TINYINT COMMENT 'Customer tier',
  dob DATE COMMENT 'Customer’s date of birth.',
  addressline1 STRING COMMENT 'Address Line 1',
  addressline2 STRING COMMENT 'Address Line 2',
  postalcode STRING COMMENT 'Zip or Postal Code',
  city STRING COMMENT 'City',
  stateprov STRING COMMENT 'State or Province',
  country STRING COMMENT 'Country',
  phone1 STRING COMMENT 'Phone number 1',
  phone2 STRING COMMENT 'Phone number 2',
  phone3 STRING COMMENT 'Phone number 3',
  email1 STRING COMMENT 'Email address 1',
  email2 STRING COMMENT 'Email address 2',
  nationaltaxratedesc STRING COMMENT 'National Tax rate description',
  nationaltaxrate FLOAT COMMENT 'National Tax rate',
  localtaxratedesc STRING COMMENT 'Local Tax rate description',
  localtaxrate FLOAT COMMENT 'Local Tax rate',
  agencyid STRING COMMENT 'Agency identifier',
  creditrating INT COMMENT 'Credit rating',
  networth INT COMMENT 'Net worth',
  marketingnameplate STRING COMMENT 'Marketing nameplate',
  iscurrent BOOLEAN COMMENT 'True if this is the current record',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  effectivedate DATE COMMENT 'Beginning of date range when this record was the current record',
  enddate DATE COMMENT 'Ending of date range when this record was the current record. A record that is not expired will use the date 9999-12-31.',
  CONSTRAINT dimcustomer_pk PRIMARY KEY(sk_customerid)
) PARTITIONED BY (iscurrent)
TBLPROPERTIES ('delta.dataSkippingNumIndexedCols' = 33);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.DimCompany (
  sk_companyid BIGINT NOT NULL COMMENT 'Surrogate key for CompanyID',
  companyid BIGINT COMMENT 'Company identifier (CIK number)',
  status STRING COMMENT 'Company status',
  name STRING COMMENT 'Company name',
  industry STRING COMMENT 'Company’s industry',
  sprating STRING COMMENT 'Standard & Poor company’s rating',
  islowgrade BOOLEAN COMMENT 'True if this company is low grade',
  ceo STRING COMMENT 'CEO name',
  addressline1 STRING COMMENT 'Address Line 1',
  addressline2 STRING COMMENT 'Address Line 2',
  postalcode STRING COMMENT 'Zip or postal code',
  city STRING COMMENT 'City',
  stateprov STRING COMMENT 'State or Province',
  country STRING COMMENT 'Country',
  description STRING COMMENT 'Company description',
  foundingdate DATE COMMENT 'Date the company was founded',
  iscurrent BOOLEAN COMMENT 'True if this is the current record',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  effectivedate DATE COMMENT 'Beginning of date range when this record was the current record',
  enddate DATE COMMENT 'Ending of date range when this record was the current record. A record that is not expired will use the date 9999-12-31.',
  CONSTRAINT dimcompany_pk PRIMARY KEY(sk_companyid),
  CONSTRAINT dimcompany_status_fk FOREIGN KEY (status) REFERENCES ${catalog}.${wh_db}_${scale_factor}.StatusType(st_name),
  CONSTRAINT dimcompany_industry_fk FOREIGN KEY (industry) REFERENCES ${catalog}.${wh_db}_${scale_factor}.Industry(in_name)
);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.DimAccount (
  sk_accountid BIGINT NOT NULL COMMENT 'Surrogate key for AccountID',
  accountid BIGINT COMMENT 'Customer account identifier',
  sk_brokerid BIGINT COMMENT 'Surrogate key of managing broker',
  sk_customerid BIGINT COMMENT 'Surrogate key of customer',
  accountdesc STRING COMMENT 'Name of customer account',
  taxstatus TINYINT COMMENT 'Tax status of this account',
  status STRING COMMENT 'Account status, active or closed',
  iscurrent BOOLEAN COMMENT 'True if this is the current record',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  effectivedate DATE COMMENT 'Beginning of date range when this record was the current record',
  enddate DATE COMMENT 'Ending of date range when this record was the current record. A record that is not expired will use the date 9999-12-31.',
  CONSTRAINT dimaccount_pk PRIMARY KEY(sk_accountid),
  CONSTRAINT dimaccount_customer_fk FOREIGN KEY (sk_customerid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimCustomer(sk_customerid),
  CONSTRAINT dimaccount_broker_fk FOREIGN KEY (sk_brokerid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimBroker(sk_brokerid)
) PARTITIONED BY (iscurrent)
--CLUSTER BY (enddate);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.DimSecurity (
  sk_securityid BIGINT NOT NULL COMMENT 'Surrogate key for Symbol',
  symbol STRING COMMENT 'Identifies security on ticker',
  issue STRING COMMENT 'Issue type',
  status STRING COMMENT 'Status type',
  name STRING COMMENT 'Security name',
  exchangeid STRING COMMENT 'Exchange the security is traded on',
  sk_companyid BIGINT COMMENT 'Company issuing security',
  sharesoutstanding BIGINT COMMENT 'Shares outstanding',
  firsttrade DATE COMMENT 'Date of first trade',
  firsttradeonexchange DATE COMMENT 'Date of first trade on this exchange',
  dividend DOUBLE COMMENT 'Annual dividend per share',
  iscurrent BOOLEAN COMMENT 'True if this is the current record',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  effectivedate DATE COMMENT 'Beginning of date range when this record was the current record',
  enddate DATE COMMENT 'Ending of date range when this record was the current record. A record that is not expired will use the date 9999-12-31.',
  CONSTRAINT dimsecurity_pk PRIMARY KEY(sk_securityid),
  CONSTRAINT dimsecurity_status_fk FOREIGN KEY (status) REFERENCES ${catalog}.${wh_db}_${scale_factor}.StatusType(st_name),
  CONSTRAINT dimsecurity_company_fk FOREIGN KEY (sk_companyid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimCompany(sk_companyid)
) PARTITIONED BY (iscurrent);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.Prospect (
  agencyid STRING NOT NULL COMMENT 'Unique identifier from agency',
  sk_recorddateid BIGINT COMMENT 'Last date this prospect appeared in input',
  sk_updatedateid BIGINT COMMENT 'Latest change date for this prospect',
  batchid INT COMMENT 'Batch ID when this record was last modified',
  iscustomer BOOLEAN COMMENT 'True if this person is also in DimCustomer,else False',
  lastname STRING COMMENT 'Last name',
  firstname STRING COMMENT 'First name',
  middleinitial STRING COMMENT 'Middle initial',
  gender STRING COMMENT 'M / F / U',
  addressline1 STRING COMMENT 'Postal address',
  addressline2 STRING COMMENT 'Postal address',
  postalcode STRING COMMENT 'Postal code',
  city STRING COMMENT 'City',
  state STRING COMMENT 'State or province',
  country STRING COMMENT 'Postal country',
  phone STRING COMMENT 'Telephone number',
  income STRING COMMENT 'Annual income',
  numbercars INT COMMENT 'Cars owned',
  numberchildren INT COMMENT 'Dependent children',
  maritalstatus STRING COMMENT 'S / M / D / W / U',
  age INT COMMENT 'Current age',
  creditrating INT COMMENT 'Numeric rating',
  ownorrentflag STRING COMMENT 'O / R / U',
  employer STRING COMMENT 'Name of employer',
  numbercreditcards INT COMMENT 'Credit cards',
  networth INT COMMENT 'Estimated total net worth',
  marketingnameplate STRING COMMENT 'For marketing purposes',
  CONSTRAINT prospect_pk PRIMARY KEY(agencyid)
) PARTITIONED BY (batchid);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.Financial (
  sk_companyid BIGINT NOT NULL COMMENT 'Company SK.',
  fi_year INT NOT NULL COMMENT 'Year of the quarter end.',
  fi_qtr INT NOT NULL COMMENT 'Quarter number that the financial information is for: valid values 1, 2, 3, 4.',
  fi_qtr_start_date DATE COMMENT 'Start date of quarter.',
  fi_revenue DOUBLE COMMENT 'Reported revenue for the quarter.',
  fi_net_earn DOUBLE COMMENT 'Net earnings reported for the quarter.',
  fi_basic_eps DOUBLE COMMENT 'Basic earnings per share for the quarter.',
  fi_dilut_eps DOUBLE COMMENT 'Diluted earnings per share for the quarter.',
  fi_margin DOUBLE COMMENT 'Profit divided by revenues for the quarter.',
  fi_inventory DOUBLE COMMENT 'Value of inventory on hand at the end of quarter.',
  fi_assets DOUBLE COMMENT 'Value of total assets at the end of the quarter.',
  fi_liability DOUBLE COMMENT 'Value of total liabilities at the end of the quarter.',
  fi_out_basic BIGINT COMMENT 'Average number of shares outstanding (basic).',
  fi_out_dilut BIGINT COMMENT 'Average number of shares outstanding (diluted).',
  CONSTRAINT financial_pk PRIMARY KEY(sk_companyid, fi_year, fi_qtr),
  CONSTRAINT financial_company_fk FOREIGN KEY (sk_companyid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimCompany(sk_companyid)
);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.DimTrade (
  tradeid INT NOT NULL COMMENT 'Trade identifier',
  sk_brokerid BIGINT COMMENT 'Surrogate key for BrokerID',
  sk_createdateid BIGINT COMMENT 'Surrogate key for date created',
  sk_createtimeid BIGINT COMMENT 'Surrogate key for time created',
  sk_closedateid BIGINT COMMENT 'Surrogate key for date closed',
  sk_closetimeid BIGINT COMMENT 'Surrogate key for time closed',
  status STRING COMMENT 'Trade status',
  type STRING COMMENT 'Trade type',
  cashflag BOOLEAN COMMENT 'Is this trade a cash or margin trade?',
  sk_securityid BIGINT COMMENT 'Surrogate key for SecurityID',
  sk_companyid BIGINT COMMENT 'Surrogate key for CompanyID',
  quantity INT COMMENT 'Quantity of securities traded.',
  bidprice DOUBLE COMMENT 'The requested unit price.',
  sk_customerid BIGINT COMMENT 'Surrogate key for CustomerID',
  sk_accountid BIGINT COMMENT 'Surrogate key for AccountID',
  executedby STRING COMMENT 'Name of person executing the trade.',
  tradeprice DOUBLE COMMENT 'Unit price at which the security was traded.',
  fee DOUBLE COMMENT 'Fee charged for placing this trade request',
  commission DOUBLE COMMENT 'Commission earned on this trade',
  tax DOUBLE COMMENT 'Amount of tax due on this trade',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  closed BOOLEAN GENERATED ALWAYS AS (nvl2(sk_closedateid, true, false)) COMMENT 'True if this trade has been closed',
  CONSTRAINT dimtrade_pk PRIMARY KEY(tradeid),
  CONSTRAINT dimtrade_security_fk FOREIGN KEY (sk_securityid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimSecurity(sk_securityid),
  CONSTRAINT dimtrade_company_fk FOREIGN KEY (sk_companyid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimCompany(sk_companyid),
  CONSTRAINT dimtrade_broker_fk FOREIGN KEY (sk_brokerid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimBroker(sk_brokerid),
  CONSTRAINT dimtrade_account_fk FOREIGN KEY (sk_accountid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimAccount(sk_accountid),
  CONSTRAINT dimtrade_customer_fk FOREIGN KEY (sk_customerid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimCustomer(sk_customerid),
  CONSTRAINT dimtrade_createdate_fk FOREIGN KEY (sk_createdateid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimDate(sk_dateid),
  CONSTRAINT dimtrade_closedate_fk FOREIGN KEY (sk_closedateid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimDate(sk_dateid),
  CONSTRAINT dimtrade_createtime_fk FOREIGN KEY (sk_createtimeid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimTime(sk_timeid),
  CONSTRAINT dimtrade_closetime_fk FOREIGN KEY (sk_closetimeid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimTime(sk_timeid)
) 
PARTITIONED BY (closed);

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.FactHoldings (
  tradeid INT COMMENT 'Key for Orignial Trade Indentifier',
  currenttradeid INT NOT NULL COMMENT 'Key for the current trade',
  sk_customerid BIGINT COMMENT 'Surrogate key for Customer Identifier',
  sk_accountid BIGINT COMMENT 'Surrogate key for Account Identifier',
  sk_securityid BIGINT COMMENT 'Surrogate key for Security Identifier',
  sk_companyid BIGINT COMMENT 'Surrogate key for Company Identifier',
  sk_dateid BIGINT COMMENT 'Surrogate key for the date associated with the',
  sk_timeid BIGINT COMMENT 'Surrogate key for the time associated with the',
  currentprice DOUBLE COMMENT 'Unit price of this security for the current trade',
  currentholding INT COMMENT 'Quantity of a security held after the current trade.',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  CONSTRAINT factholdings_pk PRIMARY KEY(currenttradeid),
  CONSTRAINT factholdings_security_fk FOREIGN KEY (sk_securityid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimSecurity(sk_securityid),
  CONSTRAINT factholdings_company_fk FOREIGN KEY (sk_companyid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimCompany(sk_companyid),
  CONSTRAINT factholdings_trade_fk FOREIGN KEY (tradeid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimTrade(tradeid),
  CONSTRAINT factholdings_currenttrade_fk FOREIGN KEY (currenttradeid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimTrade(tradeid),
  CONSTRAINT factholdings_account_fk FOREIGN KEY (sk_accountid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimAccount(sk_accountid),
  CONSTRAINT factholdings_customer_fk FOREIGN KEY (sk_customerid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimCustomer(sk_customerid),
  CONSTRAINT factholdings_date_fk FOREIGN KEY (sk_dateid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimDate(sk_dateid),
  CONSTRAINT factholdings_time_fk FOREIGN KEY (sk_timeid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimTime(sk_timeid)
)

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.FactCashBalances (
  sk_customerid BIGINT NOT NULL COMMENT 'Surrogate key for CustomerID',
  sk_accountid BIGINT NOT NULL COMMENT 'Surrogate key for AccountID',
  sk_dateid BIGINT NOT NULL COMMENT 'Surrogate key for the date',
  cash DOUBLE COMMENT 'Cash balance for the account after applying',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  CONSTRAINT cashbalances_pk PRIMARY KEY(sk_customerid, sk_accountid, sk_dateid),
  CONSTRAINT cashbalances_customer_fk FOREIGN KEY (sk_customerid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimCustomer(sk_customerid),
  CONSTRAINT cashbalances_account_fk FOREIGN KEY (sk_accountid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimAccount(sk_accountid),
  CONSTRAINT cashbalances_date_fk FOREIGN KEY (sk_dateid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimDate(sk_dateid)
)

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.FactMarketHistory (
  sk_securityid BIGINT NOT NULL COMMENT 'Surrogate key for SecurityID',
  sk_companyid BIGINT COMMENT 'Surrogate key for CompanyID',
  sk_dateid BIGINT NOT NULL COMMENT 'Surrogate key for the date',
  peratio DOUBLE COMMENT 'Price to earnings per share ratio',
  yield DOUBLE COMMENT 'Dividend to price ratio, as a percentage',
  fiftytwoweekhigh DOUBLE COMMENT 'Security highest price in last 52 weeks from this day',
  sk_fiftytwoweekhighdate BIGINT COMMENT 'Earliest date on which the 52 week high price was set',
  fiftytwoweeklow DOUBLE COMMENT 'Security lowest price in last 52 weeks from this day',
  sk_fiftytwoweeklowdate BIGINT COMMENT 'Earliest date on which the 52 week low price was set',
  closeprice DOUBLE COMMENT 'Security closing price on this day',
  dayhigh DOUBLE COMMENT 'Highest price for the security on this day',
  daylow DOUBLE COMMENT 'Lowest price for the security on this day',
  volume INT COMMENT 'Trading volume of the security on this day',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  CONSTRAINT fmh_pk PRIMARY KEY(sk_securityid, sk_dateid),
  CONSTRAINT fmh_security_fk FOREIGN KEY (sk_securityid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimSecurity(sk_securityid),
  CONSTRAINT fmh_company_fk FOREIGN KEY (sk_companyid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimCompany(sk_companyid),
  CONSTRAINT fmh_date_fk FOREIGN KEY (sk_dateid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimDate(sk_dateid)
)

-- COMMAND ----------

CREATE OR REPLACE TABLE ${catalog}.${wh_db}_${scale_factor}.FactWatches (
  sk_customerid BIGINT NOT NULL COMMENT 'Customer associated with watch list',
  sk_securityid BIGINT NOT NULL COMMENT 'Security listed on watch list',
  sk_dateid_dateplaced BIGINT COMMENT 'Date the watch list item was added',
  sk_dateid_dateremoved BIGINT COMMENT 'Date the watch list item was removed',
  batchid INT COMMENT 'Batch ID when this record was inserted',
  removed BOOLEAN GENERATED ALWAYS AS (nvl2(sk_dateid_dateremoved, true, false)) COMMENT 'True if this watch has been removed',
  CONSTRAINT factwatches_pk PRIMARY KEY(sk_customerid, sk_securityid),
  CONSTRAINT factwatches_customer_fk FOREIGN KEY (sk_customerid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimCustomer(sk_customerid),
  CONSTRAINT factwatches_security_fk FOREIGN KEY (sk_securityid) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimSecurity(sk_securityid),
  CONSTRAINT factwatches_dateplaced_fk FOREIGN KEY (sk_dateid_dateplaced) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimDate(sk_dateid),
  CONSTRAINT factwatches_dateremoved_fk FOREIGN KEY (sk_dateid_dateremoved) REFERENCES ${catalog}.${wh_db}_${scale_factor}.DimDate(sk_dateid)
) 
PARTITIONED BY (removed);
