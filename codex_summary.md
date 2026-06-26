Implemented and verified.

Changes made:
- Added adaptive Balance column/input sizing in [workflow_helper.rb](C:/Users/edward/projects/tdkgroup/app/helpers/admin/bas/workflow_helper.rb), [_tdk_workbook_table.html.erb](C:/Users/edward/projects/tdkgroup/app/views/admin/bas/jobs/_tdk_workbook_table.html.erb), and [application.css](C:/Users/edward/projects/tdkgroup/app/assets/tailwind/application.css).
- Added `tdk-workbook-cell-input--balance`, CSS min-width rules, and increased workbook table min-width to allow horizontal scrolling instead of clipping.
- Improved scanned OCR description cleanup in [pdf_statement_parser.rb](C:/Users/edward/projects/tdkgroup/app/services/bas_tdk/pdf_statement_parser.rb): final footer truncation, trailing punctuation/noise scrub, safer VIC/NSW/QLD/ACT/TAS/SA/WA/NT split-ending repair, and stronger trailing lowercase/diacritic removal.
- Added synthetic parser/controller tests confirming cleanup in parsed row data and persisted workbook `row_data`.

Verification passed:
- `bundle exec rails test`  
  `439 runs, 4771 assertions, 0 failures, 0 errors`
- `bundle exec rails zeitwerk:check`  
  `All is good!`
- `bundle exec rails tailwindcss:build`  
  passed
- Optional syntax checks passed for parser, helper, parser test, and controller test.

Notes: the test commands still emit existing Windows VIPS module warnings, Ruby `csv` default-gem warnings, and a tempfile finalizer warning, but all requested commands exited successfully.