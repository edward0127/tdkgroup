import { Controller } from "@hotwired/stimulus"

const CODING_REFRESH_SCROLL_KEY = "tdk-coding-status:auto-refresh-scroll-y"

export default class extends Controller {
  static targets = [
    "statusBadge",
    "spinner",
    "sourceFilename",
    "version",
    "referenceRows",
    "suggestions",
    "warnings",
    "reviewed",
    "errors"
  ]

  static values = {
    url: String,
    initialStatus: String,
    renderedActiveRunId: String,
    renderedActiveRunVersion: String,
    pollInterval: { type: Number, default: 3000 }
  }

  connect() {
    this.timeout = null
    this.reloadTriggered = false
    this.restoreScroll()
    if (this.runningStatus(this.initialStatusValue)) this.poll()
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
        if (!response.ok) throw new Error("Coding status request failed")
        return response.json()
      })
      .then((payload) => {
        this.render(payload)
        if (this.shouldReload(payload)) {
          this.reloadTriggered = true
          this.storeScroll()
          window.location.assign(this.cacheBustedUrl(payload.workflow_url || window.location.href))
          return
        }

        if (this.runningStatus(payload.status)) this.schedule()
      })
      .catch(() => this.schedule())
  }

  render(payload) {
    if (this.hasStatusBadgeTarget) {
      this.statusBadgeTarget.textContent = this.humanize(payload.status)
      this.statusBadgeTarget.className = `tdk-status-pill ${this.statusClass(payload.status)}`
    }
    this.setText("sourceFilename", payload.source_filename || "Previous-quarter reference")
    this.setText("version", payload.version_number ? `v${payload.version_number}` : "Not recorded")
    this.setText("referenceRows", payload.reference_row_count || 0)
    this.setText("suggestions", payload.suggestion_count || 0)
    this.setText("warnings", payload.warning_count || 0)
    this.setText("reviewed", payload.reviewed_count || 0)

    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.toggle("is-empty", !this.runningStatus(payload.status))
    }
    this.renderErrors(payload.processing_errors || [], payload.mapping_required)
  }

  renderErrors(errors, mappingRequired) {
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

  shouldReload(payload) {
    if (this.reloadTriggered) return false
    if (!this.runningStatus(payload.status) && payload.status !== this.initialStatusValue) return true

    const activeId = payload.active_run_id ? String(payload.active_run_id) : ""
    const renderedId = this.hasRenderedActiveRunIdValue ? this.renderedActiveRunIdValue : ""
    if (activeId && activeId !== renderedId) return true

    const activeVersion = payload.active_run_version ? String(payload.active_run_version) : ""
    const renderedVersion = this.hasRenderedActiveRunVersionValue ? this.renderedActiveRunVersionValue : ""
    return Boolean(activeVersion && renderedVersion && activeVersion !== renderedVersion)
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

  runningStatus(status) {
    return ["queued", "processing"].includes(status)
  }

  statusClass(status) {
    switch (status) {
      case "processed": return "is-success"
      case "failed": return "is-danger"
      case "needs_mapping": return "is-warning"
      case "queued":
      case "processing": return "is-working"
      case "superseded": return "is-muted"
      default: return "is-neutral"
    }
  }

  setText(targetName, value) {
    const target = this[`${targetName}Target`]
    if (target) target.textContent = String(value)
  }

  humanize(value) {
    if (!value) return "Unknown"
    return value.replace(/_/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase())
  }

  cacheBustedUrl(url) {
    const refreshUrl = new URL(url, window.location.href)
    refreshUrl.hash = ""
    refreshUrl.searchParams.set("_tdk_coding_refresh", Date.now().toString())
    return refreshUrl.toString()
  }

  storeScroll() {
    window.sessionStorage.setItem(CODING_REFRESH_SCROLL_KEY, String(window.scrollY))
  }

  restoreScroll() {
    const value = window.sessionStorage.getItem(CODING_REFRESH_SCROLL_KEY)
    if (value === null) return
    window.sessionStorage.removeItem(CODING_REFRESH_SCROLL_KEY)
    const top = Number(value)
    if (!Number.isFinite(top)) return
    window.requestAnimationFrame(() => window.scrollTo({ top, left: 0, behavior: "auto" }))
  }
}
