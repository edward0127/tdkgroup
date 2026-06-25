# TDK Local OCR Fallback

TDK BAS Step 1 can process readable bank statement PDFs directly. When a PDF has no selectable transaction text, the TDK-only workflow can optionally run local OCR and feed the generated sidecar text back through the same deterministic PDF parser.

## Privacy Rule

Customer bank statements, invoices, OCR text, and extracted transaction data must stay on the server/container. Do not use external OCR, cloud document extraction, HTTP OCR services, OpenAI, or any LLM for this workflow.

Do not commit real customer bank statements, invoices, OCR output, review ZIPs, storage blobs, or generated customer data.

## Docker Runtime Requirement

Production runs inside Docker. Installing OCR tools on the host server is not enough. The OCR binaries must exist inside the Rails runtime image/container.

The Docker image should include:

- ocrmypdf
- tesseract-ocr
- tesseract-ocr-eng
- tesseract-ocr-osd
- ghostscript
- qpdf
- poppler-utils

## Environment

Recommended production values:

```text
TDK_LOCAL_OCR_ENABLED=true
TDK_LOCAL_OCR_COMMAND=/usr/bin/ocrmypdf
TDK_LOCAL_OCR_TIMEOUT_SECONDS=300
TDK_LOCAL_OCR_JOBS=1
TDK_LOCAL_OCR_PSM=6
```

Readable PDFs do not require OCR to be enabled. Scanned/image-only PDFs fail safely when OCR is disabled or unavailable.

`TDK_LOCAL_OCR_JOBS=1` is recommended on small servers so OCR does not use all CPU cores for one uploaded PDF.

`TDK_LOCAL_OCR_PSM=6` uses Tesseract's single uniform block page segmentation mode, which is a better default for scanned bank statement tables.

## Verify Installation Inside Container

After deploying the rebuilt image:

```bash
docker compose exec web which ocrmypdf
docker compose exec web ocrmypdf --version
docker compose exec web tesseract --version
docker compose exec web tesseract --list-langs
docker compose exec web printenv TDK_LOCAL_OCR_ENABLED
docker compose exec web printenv TDK_LOCAL_OCR_COMMAND
docker compose exec web printenv TDK_LOCAL_OCR_TIMEOUT_SECONDS
docker compose exec web printenv TDK_LOCAL_OCR_JOBS
docker compose exec web printenv TDK_LOCAL_OCR_PSM
```

Expected:

* `which ocrmypdf` should usually return `/usr/bin/ocrmypdf`
* `tesseract --list-langs` should include `eng` and `osd`

## Failure Modes

Expected safe failures include:

* OCR disabled: upload the original selectable-text bank PDF or XLSX.
* OCR command missing: rebuild the Docker image with local OCR tooling or upload selectable-text PDF/XLSX.
* OCR timeout: retry with a smaller/original statement or use selectable-text PDF/XLSX.
* OCR text parsed unreliably: use the original bank PDF with selectable text or XLSX.

Failed uploads do not replace the previous active processed TDK workbook.

## Local Testing

Rails tests stub OCR execution and must not require `ocrmypdf` or Tesseract. Use synthetic fixtures only. For manual verification, use local real files only and do not commit them.

OCR logs and metadata may include only operational status such as attempted/disabled/missing command/timeout/failed/succeeded and parsed row counts. Do not log OCR text, descriptions, balances, bank details, account numbers, or raw PDF text.
