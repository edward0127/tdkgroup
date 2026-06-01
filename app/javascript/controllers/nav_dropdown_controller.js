import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger"]

  connect() {
    this.setExpanded(false)
  }

  open() {
    this.setExpanded(true)
  }

  close() {
    requestAnimationFrame(() => {
      if (this.element.matches(":hover") || this.element.contains(document.activeElement)) {
        return
      }

      this.setExpanded(false)
    })
  }

  setExpanded(expanded) {
    if (!this.hasTriggerTarget) return

    this.triggerTarget.setAttribute("aria-expanded", expanded ? "true" : "false")
  }
}
