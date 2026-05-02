
The date that is downloaded in:
- Catalog: energy_endava_193
- Schema: default
- Table name: nsw_dispatch_5min

The data was downloaded from Sep 2021 to Feb 2026, which include the data that use 5-min intervals.

The attributes in the downloaded table is explained as:


| Name | Data Type | Comment |
| -------- | -------- | -------- |
| SETTLEMENTDATE | DATE | Market date and time starting at 04:05 |
| REGIONID | VARCHAR2(10) | Region Identifier |
| INTERVENTION | NUMBER(2,0) | Manual Intervention flag |
| RRP | NUMBER(15,5) | Regional Reference Price for this dispatch period. RRP is the price used to settle the market |
| PRICE_STATUS | VARCHAR2(20) | Status of regional prices for this dispatch interval "NOT FIRM" or "FIRM" |
| RAISE6SECRRP | NUMBER(15,5) | How much the grid pays the generators within 6 seconds to fix frequency issue|
| RAISEREGRRP | NUMBER(15,5) | How much the grid pays the regulation services to keep the grid at exactly 50 Hz|

More information on the data can be found: https://visualisations.aemo.com.au/aemo/nemweb/MMSDataModelReport/Electricity/MMS%20Data%20Model%20Report_files/MMS_130.htm

- Table name: nsw_demand

The data was downloaded from Oct 2021 to Feb 2026.

More information on the data can be found: https://visualisations.aemo.com.au/aemo/nemweb/MMSDataModelReport/Electricity/MMS%20Data%20Model%20Report_files/MMS_131.htm


