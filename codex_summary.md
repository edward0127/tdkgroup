Implemented the scanned OCR parser fixes.

Changed [pdf_statement_parser.rb](C:/Users/edward/projects/tdkgroup/app/services/bas_tdk/pdf_statement_parser.rb:62) to:
- Use a scanned-OCR amount pattern that accepts 2-4 decimal places only on the scanned debit/credit/balance path.
- Truncate over-precise OCR currency amounts to cents in `parse_amount`, e.g. `86.307` -> `86.30`.
- Treat `osko payment` as a generic debit signal only when no explicit credit/deposit signal is present, so `DEPOSIT-OSKO PAYMENT`, `DEPOSIT OSKO PAYMENT`, and `OSKO DEPOSIT` import as credits while `WITHDRAWAL-OSKO PAYMENT` remains debit.

Added synthetic coverage in [bas_tdk_pdf_statement_parser_test.rb](C:/Users/edward/projects/tdkgroup/test/services/bas_tdk_pdf_statement_parser_test.rb:99) for Osko direction, decimal-noise truncation, and the combined footer fixture.

Verification passed:
- `ruby -c app/services/bas_tdk/pdf_statement_parser.rb`
- `ruby -c test/services/bas_tdk_pdf_statement_parser_test.rb`
- `bundle exec rails test test/services/bas_tdk_pdf_statement_parser_test.rb` — 18 runs, 255 assertions
- `bundle exec rails test` — 434 runs, 4716 assertions
- `bundle exec rails zeitwerk:check`
- `bundle exec rails tailwindcss:build`
- `git diff --check`

The Rails commands still emit existing local vips/csv/Windows Tempfile warnings, but all exited successfully.