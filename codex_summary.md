Implemented the workbook width fix.

Changed:
- [tdk_resizable_table_controller.js](C:/Users/edward/projects/tdkgroup/app/javascript/controllers/tdk_resizable_table_controller.js:205): table width now comes from summed visible column widths, clears stale `min-width` when the table fits, hides top scrollbar, and resets scroll positions.
- [workflow_helper.rb](C:/Users/edward/projects/tdkgroup/app/helpers/admin/bas/workflow_helper.rb:328): lowered min widths while keeping readable defaults, including Details `224px -> 128px min` and Description `320px -> 160px min`.
- [application.css](C:/Users/edward/projects/tdkgroup/app/assets/tailwind/application.css:2484): removed the forced visible-Details wide min width and reduced CSS fallback mins so they do not fight `<colgroup>` widths.
- [admin_bas_tdk_workbooks_controller_test.rb](C:/Users/edward/projects/tdkgroup/test/controllers/admin_bas_tdk_workbooks_controller_test.rb:868): added/updated coverage for helper widths, Details col metadata, no hardcoded `88rem`, dynamic scrollbar controller behavior, top scrollbar markup, pagination, save buttons, and no nested forms.

Validation passed:
- `ruby -c app/helpers/admin/bas/workflow_helper.rb`
- `node --check app/javascript/controllers/tdk_resizable_table_controller.js`
- `bundle exec rails test test/controllers/admin_bas_workflow_ui_test.rb`
- `bundle exec rails test test/controllers/admin_bas_tdk_workbooks_controller_test.rb`
- `bundle exec rails test` - 500 runs, 5585 assertions
- `bundle exec rails zeitwerk:check`
- `bundle exec rails tailwindcss:build`

There is no JS test runner in this repo, so the resize behavior is covered with static Rails assertions rather than browser-level drag tests. The test output still has existing VIPS/csv warnings, but no failures.