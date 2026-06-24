import { Controller } from "@hotwired/stimulus"

const SAVE_SCROLL_KEY = "tdk-workbook-rows-save-scroll-y"

export default class extends Controller {
  connect() {
    this.restore()
  }

  store() {
    window.sessionStorage.setItem(SAVE_SCROLL_KEY, String(window.scrollY))
  }

  restore() {
    const scrollY = window.sessionStorage.getItem(SAVE_SCROLL_KEY)
    if (scrollY === null) return

    window.sessionStorage.removeItem(SAVE_SCROLL_KEY)
    const top = Number(scrollY)
    if (!Number.isFinite(top)) return

    this.scrollTo(top)
    window.setTimeout(() => this.scrollTo(top), 75)
  }

  scrollTo(top) {
    window.requestAnimationFrame(() => {
      window.scrollTo({ top, left: 0, behavior: "auto" })
    })
  }
}
