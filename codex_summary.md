Implemented the TDK BAS Step 1 hardening.

Changed:
- Hardened `BasTdk::PdfStatementParser` for Westpac stop boundaries, ANZ `blank` tokens, ANZ withdrawal/deposit/balance parsing, and totals/footer continuation rejection.
- Added focused parser regressions in `test/services/bas_tdk_pdf_statement_parser_test.rb`.
- Added Date-cell spacing/class coverage and widened Date/Category table spacing while keeping horizontal scrolling.

Verification passed:
- `bundle exec rails test` — 405 runs, 4378 assertions, 0 failures
- `bundle exec rails zeitwerk:check` — passed
- `bundle exec rails tailwindcss:build` — passed

Notes: the commands still emit existing Windows libvips optional-module warnings and a Ruby `csv` stdlib warning, but they did not fail. I did not open or modify the named real PDF files.