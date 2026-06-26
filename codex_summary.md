Implemented the TDK BAS Step 1 fixes.

Changed:
- `app/services/bas_tdk/pdf_statement_parser.rb`
  - Generic URL/footer truncation for OCR descriptions.
  - Trailing OCR noise cleanup for `_`, punctuation, stray lower/diacritic single letters, and attached final digits like `VIC1`.
  - Narrow split uppercase ending repair for OCR fragments like `VI [ c`.
  - Date-starting continuation lines without amounts now stay with the active transaction, including split day repair like `1` + `5 FEB 2026`.
- `app/helpers/admin/bas/workflow_helper.rb`
  - `Balance` now maps to `tdk-workbook-col--balance` before generic amount matching.
- `app/assets/tailwind/application.css`
  - Added Balance width/min-width, table min-width, and preserved horizontal scrolling/right-aligned amount fields.
- Added synthetic parser/controller/CSS coverage in:
  - `test/services/bas_tdk_pdf_statement_parser_test.rb`
  - `test/controllers/admin_bas_tdk_workbooks_controller_test.rb`

Verification:
- `bundle exec rails test` passed: 438 runs, 4753 assertions
- `bundle exec rails zeitwerk:check` passed
- `bundle exec rails tailwindcss:build` passed
- `ruby -c app/services/bas_tdk/pdf_statement_parser.rb` passed
- `ruby -c app/helpers/admin/bas/workflow_helper.rb` passed
- `ruby -c test/services/bas_tdk_pdf_statement_parser_test.rb` passed
- `git diff --check` clean except the repo’s CRLF conversion warnings

The test runs also emitted local environment warnings about missing optional VIPS modules, Ruby `csv` future bundling, and Windows Tempfile cleanup permissions, but they did not fail the suite.