Implemented the TDK BAS table fix.

Changed:
- Optional blank Details-like columns are filtered from the browser table by default in [workflow_helper.rb](C:/Users/edward/projects/tdkgroup/app/helpers/admin/bas/workflow_helper.rb:242).
- `Details/Narration/Reference/Memo/Notes` stay visible when populated, explicitly requested, or currently sorted.
- Added Show/Hide blank optional columns toggle preserving `page`, `per_page`, `sort`, and `direction`.
- Hidden optional columns no longer render inputs, so saves only submit visible fields.
- Added compact Balance table classes/layout in [application.css](C:/Users/edward/projects/tdkgroup/app/assets/tailwind/application.css:2389).
- Added regression coverage in [admin_bas_tdk_workbooks_controller_test.rb](C:/Users/edward/projects/tdkgroup/test/controllers/admin_bas_tdk_workbooks_controller_test.rb:312).

Verification:
- `ruby -c app/helpers/admin/bas/workflow_helper.rb` passed.
- `ruby -c test/controllers/admin_bas_tdk_workbooks_controller_test.rb` passed.
- `bundle exec rails test` passed: 444 runs, 4884 assertions.
- `bundle exec rails zeitwerk:check` passed: “All is good!”
- `bundle exec rails tailwindcss:build` passed.
- `git diff --check` passed, with only existing CRLF normalization warnings.

The Rails commands emitted Windows VIPS/tempfile warnings, but all requested commands exited successfully. `codex_summary.md` was already modified in the worktree and I left it alone.