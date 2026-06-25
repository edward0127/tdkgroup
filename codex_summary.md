Implemented configurable local OCR PSM.

Changes:
- Added `DEFAULT_PSM = 6`, `.configured_psm`, valid range `1..13`, and argv support for `--tesseract-pagesegmode <psm>` in [local_ocr.rb](C:/Users/edward/projects/tdkgroup/app/services/bas_tdk/local_ocr.rb:10).
- Kept `--jobs`, `--sidecar`, `--skip-text`, `--rotate-pages`, `--deskew`, and `--output-type pdf`.
- Added focused PSM tests for default, configured `4`/`6`, and invalid fallback cases in [bas_tdk_local_ocr_test.rb](C:/Users/edward/projects/tdkgroup/test/services/bas_tdk_local_ocr_test.rb:95).
- Added `TDK_LOCAL_OCR_PSM=6` to `.env.example`, `.env.prod.example`, and the local OCR ops doc.
- Did not modify real `.env`, `.env.prod`, storage, DB, secrets, or customer files.

Verification passed:
- `ruby -c app/services/bas_tdk/local_ocr.rb`
- `ruby -c test/services/bas_tdk_local_ocr_test.rb`
- `bundle exec rails test test/services/bas_tdk_local_ocr_test.rb`: 12 runs, 101 assertions, 0 failures
- `bundle exec rails test`: 431 runs, 4679 assertions, 0 failures
- `bundle exec rails zeitwerk:check`: All is good
- `bundle exec rails tailwindcss:build`: Done

The full test/zeitwerk/tailwind commands emitted existing local Windows warnings from VIPS modules, Ruby CSV default-gem deprecation, and Tempfile cleanup, but all commands exited successfully. Existing unrelated uncommitted changes in parser/controller/workbook test files and `codex_summary.md` were left untouched.