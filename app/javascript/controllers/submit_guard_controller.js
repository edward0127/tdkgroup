import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    loadingText: String
  }

  connect() {
    this.submitted = false
    this.lastSubmitter = null
    this.fallbackTimer = null
  }

  rememberSubmitter(event) {
    const submitter = event.target.closest("button[type='submit'], button:not([type]), input[type='submit']")

    if (!submitter || !this.element.contains(submitter)) return

    this.lastSubmitter = submitter
  }

  submit(event) {
    if (this.submitted) {
      event.preventDefault()
      return
    }

    if (this.element.checkValidity && !this.element.checkValidity()) {
      return
    }

    if (event.defaultPrevented) return

    this.clearFallbackTimer()
    this.fallbackTimer = window.setTimeout(() => {
      this.fallbackTimer = null
      if (this.submitted || event.defaultPrevented || this.usesTurbo) return

      this.startLoading(event.submitter || this.lastSubmitter || this.firstEnabledSubmitButton)
    }, 0)
  }

  submitStart(event) {
    if (this.submitted) return

    this.clearFallbackTimer()
    const formSubmission = event.detail && event.detail.formSubmission
    this.startLoading((formSubmission && formSubmission.submitter) || this.lastSubmitter || this.firstEnabledSubmitButton)
  }

  startLoading(submitter) {
    this.submitted = true
    this.element.classList.add("is-submitting")
    this.element.dataset.submitGuardSubmitting = "true"
    this.disableSubmitButtons(submitter)
  }

  submitEnd(event) {
    this.clearFallbackTimer()

    if (event.detail && event.detail.success) return

    this.reset()
  }

  reset() {
    this.clearFallbackTimer()
    this.submitted = false
    this.lastSubmitter = null
    this.element.classList.remove("is-submitting")
    delete this.element.dataset.submitGuardSubmitting
    this.submitButtons.forEach((button) => this.restoreButton(button))
  }

  clearFallbackTimer() {
    if (!this.fallbackTimer) return

    window.clearTimeout(this.fallbackTimer)
    this.fallbackTimer = null
  }

  disableSubmitButtons(submitter) {
    this.submitButtons.forEach((button) => {
      button.dataset.submitGuardWasDisabled = button.disabled ? "true" : "false"

      if (button === submitter) {
        this.applyLoadingState(button)
      }

      button.disabled = true
      button.setAttribute("aria-disabled", "true")
    })
  }

  applyLoadingState(button) {
    const loadingText = button.dataset.submitGuardLoadingText || this.loadingTextValue || "Working"

    if (button.tagName === "INPUT") {
      if (button.dataset.submitGuardOriginalValue === undefined) {
        button.dataset.submitGuardOriginalValue = button.value
      }
      button.value = loadingText
      return
    }

    if (button.dataset.submitGuardOriginalHtml === undefined) {
      button.dataset.submitGuardOriginalHtml = button.innerHTML
    }
    button.classList.add("is-loading")
    button.replaceChildren(this.spinnerElement(), document.createTextNode(loadingText))
  }

  restoreButton(button) {
    if (button.dataset.submitGuardOriginalValue !== undefined) {
      button.value = button.dataset.submitGuardOriginalValue
      delete button.dataset.submitGuardOriginalValue
    }

    if (button.dataset.submitGuardOriginalHtml !== undefined) {
      button.innerHTML = button.dataset.submitGuardOriginalHtml
      delete button.dataset.submitGuardOriginalHtml
    }

    button.classList.remove("is-loading")
    button.removeAttribute("aria-disabled")

    if (button.dataset.submitGuardWasDisabled === "false") {
      button.disabled = false
    }

    delete button.dataset.submitGuardWasDisabled
  }

  spinnerElement() {
    const spinner = document.createElement("span")
    spinner.className = "submit-guard-spinner"
    spinner.setAttribute("aria-hidden", "true")
    return spinner
  }

  get submitButtons() {
    const nestedButtons = Array.from(
      this.element.querySelectorAll("button[type='submit'], button:not([type]), input[type='submit']")
    )
    const associatedButtons = Array.from(
      document.querySelectorAll("button[form], input[type='submit'][form]")
    ).filter((button) => button.form === this.element)

    return Array.from(new Set([...nestedButtons, ...associatedButtons]))
  }

  get firstEnabledSubmitButton() {
    return this.submitButtons.find((button) => !button.disabled)
  }

  get usesTurbo() {
    return window.Turbo !== undefined && !this.element.closest("[data-turbo='false']")
  }
}
