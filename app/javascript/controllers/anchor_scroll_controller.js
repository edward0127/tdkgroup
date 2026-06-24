import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.scrollAfterTurboLoad = () => this.scrollToHashOnce()
    document.addEventListener("turbo:load", this.scrollAfterTurboLoad)
    this.scrollToHashOnce()
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.scrollAfterTurboLoad)
  }

  scrollToHashOnce() {
    const hash = window.location.hash
    if (!hash) return

    const target = this.targetForHash(hash)
    if (target !== this.element) return

    this.scrollOnNextFrame(hash)
    window.setTimeout(() => this.scrollOnNextFrame(hash), 75)
    window.setTimeout(() => this.removeCurrentHash(hash), 100)
  }

  removeCurrentHash(hash) {
    if (window.location.hash !== hash) return

    const url = new URL(window.location.href)
    url.hash = ""
    window.history.replaceState(window.history.state, "", url.toString())
  }

  scrollOnNextFrame(hash) {
    window.requestAnimationFrame(() => {
      const target = this.targetForHash(hash)
      if (target) target.scrollIntoView({ block: "start", behavior: "auto" })
    })
  }

  targetForHash(hash) {
    const id = window.decodeURIComponent(hash.slice(1))
    if (!id) return null

    return document.getElementById(id)
  }
}
