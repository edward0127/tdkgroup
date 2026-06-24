Implemented the TDK BAS follow-up fixes.

Key changes:
- Added narrow Excel decimal-noise cleanup in [workbook_values.rb](C:/Users/edward/projects/tdkgroup/app/services/bas_tdk/workbook_values.rb:98), wired through import, table display, text sorting, save normalization, and Excel text export.
- Removed row-save `#tdk-active-table` redirects and added one-shot save scroll restoration via [tdk_save_scroll_controller.js](C:/Users/edward/projects/tdkgroup/app/javascript/controllers/tdk_save_scroll_controller.js:1).
- Fixed the table layout: Date is wider, old generic `first-child` width no longer applies, horizontal overflow is allowed.
- Made the Source file status detail span the full status grid row.
- Added/updated focused regressions for decimal cleanup, export cleanup, hidden Source row/date layout, status card width, save-scroll wiring, and hash-free save redirects.

Verification:
- `bundle exec rails test` passed: 397 runs, 4241 assertions.
- `bundle exec rails zeitwerk:check` passed.
- `bundle exec rails tailwindcss:build` passed.
- Focused TDK tests also passed: 30 runs, 670 assertions.

Warnings seen during verification were non-failing existing environment warnings: missing optional VIPS modules, Ruby 3.4 `csv` default-gem warnings from roo/app code, and one Tempfile finalizer warning after the full test run.

I did not open or upload the named real customer workbook files, to stay within the “do not touch real customer XLSX/PDF/CSV files” constraint.