Implemented the OCR productionisation.

Changed:
- [Dockerfile](C:/Users/edward/projects/tdkgroup/Dockerfile:67): installs `ocrmypdf`, Tesseract `eng/osd`, Ghostscript, qpdf, and Poppler in the final runtime image before `USER 1000:1000`.
- [local_ocr.rb](C:/Users/edward/projects/tdkgroup/app/services/bas_tdk/local_ocr.rb:9): added `TDK_LOCAL_OCR_JOBS`, defaulting invalid/missing values to `1`, and passes `--jobs <n>` safely via argv.
- [tdk_local_ocr.md](C:/Users/edward/projects/tdkgroup/docs/tdk_local_ocr.md:11): replaced host-install guidance with Docker/runtime OCR docs and job-limit notes.
- [.env.prod.example](C:/Users/edward/projects/tdkgroup/.env.prod.example:32) and [.env.example](C:/Users/edward/projects/tdkgroup/.env.example:34): added disabled-by-default OCR config blocks.
- [bas_tdk_local_ocr_test.rb](C:/Users/edward/projects/tdkgroup/test/services/bas_tdk_local_ocr_test.rb:86): added default/configured/invalid job tests and log content-safety coverage. Tests still stub OCR execution.

Verification passed:
- `bundle exec rails test`: 422 runs, 4515 assertions, 0 failures.
- `bundle exec rails zeitwerk:check`: All is good.
- `bundle exec rails tailwindcss:build`: completed.
- `docker build -t tdkgroup-ocr-check .`: completed.
- `docker run --rm tdkgroup-ocr-check which ocrmypdf`: `/usr/bin/ocrmypdf`
- `ocrmypdf --version`: `16.7.0+dfsg1`
- `tesseract --version`: `5.5.0`
- Extra check: `tesseract --list-langs` includes `eng` and `osd`.

Notes: local Windows VIPS optional-module warnings, Ruby CSV deprecation warnings, and Tempfile cleanup warnings appeared during Rails commands, but all command exit codes were clean. I did not modify real `.env`, `.env.prod`, secrets, storage, or customer data; `.dockerignore` also excludes those from the Docker build context. The OCR service/docs/test files remain untracked because they were already untracked when I started.