import { Controller } from "@hotwired/stimulus"

const AUTO_REFRESH_SCROLL_KEY = "tdk-workbook-status:auto-refresh-scroll-y"

export default class extends Controller {
  static targets = [
    "statusBadge",
    "statusText",
    "version",
    "rowCount",
    "errors",
    "activeNotice",
    "downloadAction",
    "statusSpinner",
    "statusWorkingText",
    "exportSpinner",
    "exportStatus",
    "activeSourceFilename"
  ]

  static values = {
    url: String,
    initialStatus: String,
    renderedActiveWorkbookId: String,
    renderedActiveWorkbookVersion: String,
    pollInterval: { type: Number, default: 3000 }
  }

  connect() {
    this.timeout = null
    this.reloadTriggered = false
    this.restoreAutoRefreshScroll()
    this.poll()
  }

  disconnect() {
    this.stop()
  }

  poll() {
    if (!this.hasUrlValue) return

    window.fetch(this.urlValue, {
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    })
      .then((response) => {
        if (!response.ok) throw new Error("Status request failed")
        return response.json()
      })
      .then((payload) => {
        const shouldReload = this.shouldReloadAfterActiveWorkbookChange(payload) ||
          this.shouldReloadAfterMappingRequired(payload)
        this.render(payload)

        if (shouldReload) {
          this.reloadTriggered = true
          this.stop()
          this.reloadAfterActiveWorkbookChange(payload)
          return
        }

        if (this.shouldContinuePolling(payload)) this.schedule()
      })
      .catch(() => this.schedule())
  }

  render(payload) {
    this.updateStatus(payload)
    this.updateExport(payload)
    this.updateErrors(payload.processing_errors || [], payload.mapping_required)
    this.updateActiveNotice(payload)
  }

  updateStatus(payload) {
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.textContent = this.humanize(payload.status)
      this.statusBadgeTarget.className = `tdk-status-pill ${this.statusClass(payload.status)}`
    }

    if (this.hasStatusTextTarget) {
      this.statusTextTarget.textContent = payload.source_filename || "Uploaded bank statement"
    }

    if (this.hasVersionTarget) {
      this.versionTarget.textContent = payload.version_number ? `v${payload.version_number}` : "Not recorded"
    }

    if (this.hasRowCountTarget) {
      this.rowCountTarget.textContent = payload.row_count || 0
    }

    if (this.hasActiveSourceFilenameTarget) {
      this.activeSourceFilenameTarget.textContent = payload.active_source_filename || "No active statement yet"
    }

    const workbookRunning = ["queued", "processing"].includes(payload.status)
    this.toggleHidden(this.statusSpinnerTargetOrNull(), !workbookRunning)
    if (this.hasStatusWorkingTextTarget) {
      this.statusWorkingTextTarget.textContent = workbookRunning ? "Processing bank statement..." : ""
      this.toggleHidden(this.statusWorkingTextTarget, !workbookRunning)
    }
  }

  updateExport(payload) {
    if (this.hasExportStatusTarget) {
      this.exportStatusTarget.textContent = this.exportLabel(payload)
    }

    const exportRunning = ["queued", "processing"].includes(payload.export_status)
    this.toggleHidden(this.exportSpinnerTargetOrNull(), !exportRunning)

    if (this.hasDownloadActionTarget) {
      this.renderDownloadAction(payload)
    }
  }

  updateErrors(errors, mappingRequired = false) {
    if (!this.hasErrorsTarget) return

    if (errors.length === 0) {
      this.errorsTarget.classList.add("is-empty")
      this.errorsTarget.replaceChildren()
      return
    }

    const title = document.createElement("strong")
    title.textContent = mappingRequired ? "Column mapping required" : "Processing errors"
    const list = document.createElement("ul")
    errors.forEach((error) => {
      const item = document.createElement("li")
      item.textContent = error
      list.appendChild(item)
    })

    this.errorsTarget.classList.remove("is-empty")
    this.errorsTarget.replaceChildren(title, list)
  }

  updateActiveNotice(payload) {
    if (!this.hasActiveNoticeTarget) return

    if (payload.status === "failed" && payload.active_workbook_id && payload.active_workbook_id !== payload.id) {
      this.activeNoticeTarget.textContent = "This upload failed. The previous processed bank statement is still active."
      this.activeNoticeTarget.classList.remove("is-empty")
    } else if (payload.mapping_required && payload.active_workbook_id) {
      this.activeNoticeTarget.textContent = "This upload needs column mapping confirmation. The previous processed bank statement is still active."
      this.activeNoticeTarget.classList.remove("is-empty")
    } else if (payload.mapping_required) {
      this.activeNoticeTarget.textContent = "Confirm the column mapping below to continue processing this upload."
      this.activeNoticeTarget.classList.remove("is-empty")
    } else {
      this.activeNoticeTarget.textContent = ""
      this.activeNoticeTarget.classList.add("is-empty")
    }
  }

  schedule() {
    this.stop()
    this.timeout = window.setTimeout(() => this.poll(), this.pollIntervalValue)
  }

  stop() {
    if (!this.timeout) return

    window.clearTimeout(this.timeout)
    this.timeout = null
  }

  shouldContinuePolling(payload) {
    return ["queued", "processing"].includes(payload.status) ||
      ["queued", "processing"].includes(payload.export_status)
  }

  shouldReloadAfterActiveWorkbookChange(payload) {
    return !this.reloadTriggered && this.activeWorkbookChanged(payload)
  }

  shouldReloadAfterMappingRequired(payload) {
    if (this.reloadTriggered || !payload.mapping_required) return false

    const initialStatus = this.hasInitialStatusValue ? this.initialStatusValue : ""
    return initialStatus !== "needs_mapping"
  }

  activeWorkbookChanged(payload) {
    const payloadActiveId = payload.active_workbook_id ? String(payload.active_workbook_id) : ""
    if (!payloadActiveId) return false

    const renderedActiveId = this.hasRenderedActiveWorkbookIdValue ? this.renderedActiveWorkbookIdValue : ""
    const renderedActiveVersion = this.hasRenderedActiveWorkbookVersionValue ? this.renderedActiveWorkbookVersionValue : ""
    const payloadActiveVersion = payload.active_workbook_version ? String(payload.active_workbook_version) : ""

    if (!renderedActiveId) return true
    if (payloadActiveId !== renderedActiveId) return true

    return Boolean(payloadActiveVersion && renderedActiveVersion && payloadActiveVersion !== renderedActiveVersion)
  }

  reloadAfterActiveWorkbookChange(payload) {
    this.storeAutoRefreshScroll()
    if (payload.workflow_url) {
      window.location.assign(this.urlWithCacheBust(payload.workflow_url))
      return
    }

    window.location.assign(this.urlWithCacheBust(payload.active_table_url || window.location.href))
  }

  urlWithCacheBust(url) {
    const refreshUrl = new URL(url, window.location.href)
    refreshUrl.hash = ""
    refreshUrl.searchParams.set("_tdk_refresh", Date.now().toString())
    return refreshUrl.toString()
  }

  storeAutoRefreshScroll() {
    window.sessionStorage.setItem(AUTO_REFRESH_SCROLL_KEY, String(window.scrollY))
  }

  restoreAutoRefreshScroll() {
    const scrollY = window.sessionStorage.getItem(AUTO_REFRESH_SCROLL_KEY)
    if (scrollY === null) return

    window.sessionStorage.removeItem(AUTO_REFRESH_SCROLL_KEY)
    const top = Number(scrollY)
    if (!Number.isFinite(top)) return

    window.requestAnimationFrame(() => window.scrollTo({ top, left: 0, behavior: "auto" }))
  }

  statusClass(status) {
    switch (status) {
      case "processed":
        return "is-success"
      case "failed":
        return "is-danger"
      case "needs_mapping":
        return "is-warning"
      case "queued":
      case "processing":
        return "is-working"
      case "superseded":
        return "is-muted"
      default:
        return "is-neutral"
    }
  }

  exportLabel(payload) {
    if (payload.download_url) return "Ready to download"

    switch (payload.export_status) {
      case "queued":
      case "processing":
        return "Preparing Excel download..."
      case "failed":
        return "Export failed"
      case "stale":
        return "Export needs refresh"
      default:
        return "Not prepared"
    }
  }

  humanize(value) {
    if (!value) return "Unknown"

    return value.replace(/_/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase())
  }

  renderDownloadAction(payload) {
    this.downloadActionTarget.replaceChildren()

    if (payload.download_url) {
      this.downloadActionTarget.appendChild(this.downloadLink(payload.download_url))
      return
    }

    if (["queued", "processing"].includes(payload.export_status)) {
      this.downloadActionTarget.appendChild(this.disabledPreparingStatus())
      return
    }

    if (payload.prepare_download_url) {
      if (payload.export_status === "stale") {
        const note = document.createElement("p")
        note.className = "tdk-export-stale-note"
        note.textContent = "Bank statement changed. Prepare a new Excel download to include the latest edits."
        this.downloadActionTarget.appendChild(note)
      }
      this.downloadActionTarget.appendChild(this.prepareDownloadForm(payload.prepare_download_url))
      return
    }

    const muted = document.createElement("span")
    muted.className = "admin-muted"
    muted.textContent = "Prepare/download available after processing succeeds."
    this.downloadActionTarget.appendChild(muted)
  }

  downloadLink(url) {
    const link = document.createElement("a")
    link.textContent = "Download Excel"
    link.className = "btn-primary"
    link.setAttribute("href", url)
    link.setAttribute("data-turbo", "false")
    return link
  }

  disabledPreparingStatus() {
    const status = document.createElement("span")
    status.className = "btn-secondary is-disabled tdk-export-disabled"
    status.setAttribute("aria-disabled", "true")
    status.appendChild(this.spinnerElement())
    status.appendChild(document.createTextNode("Preparing Excel download..."))
    return status
  }

  prepareDownloadForm(url) {
    const form = document.createElement("form")
    form.method = "post"
    form.action = url
    form.className = "button_to"

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
    if (csrfToken) {
      const token = document.createElement("input")
      token.type = "hidden"
      token.name = "authenticity_token"
      token.value = csrfToken
      form.appendChild(token)
    }

    const button = document.createElement("button")
    button.type = "submit"
    button.className = "btn-secondary"
    button.textContent = "Prepare Excel download"
    form.appendChild(button)

    return form
  }

  spinnerElement() {
    const spinner = document.createElement("span")
    spinner.className = "tdk-status-spinner"
    spinner.setAttribute("aria-hidden", "true")
    return spinner
  }

  statusSpinnerTargetOrNull() {
    return this.hasStatusSpinnerTarget ? this.statusSpinnerTarget : null
  }

  exportSpinnerTargetOrNull() {
    return this.hasExportSpinnerTarget ? this.exportSpinnerTarget : null
  }

  toggleHidden(element, hidden) {
    if (!element) return

    element.classList.toggle("is-empty", hidden)
  }
}
