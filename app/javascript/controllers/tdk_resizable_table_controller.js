import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["column", "handle", "tableWrap", "topScroll", "topScrollInner", "table"]
  static values = { storageKey: String }

  connect() {
    this.resizeState = null
    this.scrollSyncSource = null
    this.scrollSyncFrame = null
    this.topScrollbarFrame = null
    this.boundPointerMove = this.pointerMove.bind(this)
    this.boundPointerUp = this.pointerUp.bind(this)
    this.boundRefreshTopScrollbar = this.queueTopScrollbarRefresh.bind(this)
    const savedWidthsApplied = this.applySavedWidths()
    if (!savedWidthsApplied) {
      this.applyDefaultWidths()
      this.syncTableWidth()
    }
    this.setupResizeObserver()
    window.addEventListener("resize", this.boundRefreshTopScrollbar)
    this.queueTopScrollbarRefresh()
  }

  disconnect() {
    this.finishResize({ persist: false })
    this.resizeObserver?.disconnect()
    window.removeEventListener("resize", this.boundRefreshTopScrollbar)
    this.cancelFrame(this.scrollSyncFrame)
    this.cancelFrame(this.topScrollbarFrame)
    this.scrollSyncFrame = null
    this.topScrollbarFrame = null
  }

  startResize(event) {
    if (event.button !== undefined && event.button !== 0) return

    const column = this.columnForKey(event.currentTarget.dataset.columnKey)
    if (!column) return

    event.preventDefault()
    event.stopPropagation()

    this.freezeCurrentColumnWidths()
    this.resizeState = {
      column,
      startX: event.clientX,
      startWidth: this.currentColumnWidth(column)
    }
    this.tableElement?.classList.add("is-resizing")

    document.addEventListener("pointermove", this.boundPointerMove)
    document.addEventListener("pointerup", this.boundPointerUp)
    document.addEventListener("pointercancel", this.boundPointerUp)
  }

  pointerMove(event) {
    if (!this.resizeState) return

    event.preventDefault()
    const nextWidth = this.constrainedWidth(
      this.resizeState.column,
      this.resizeState.startWidth + event.clientX - this.resizeState.startX
    )
    this.resizeState.column.style.width = `${nextWidth}px`
    this.syncTableWidth()
  }

  pointerUp(event) {
    event.preventDefault()
    this.finishResize({ persist: true })
  }

  handleClick(event) {
    event.preventDefault()
    event.stopPropagation()
  }

  resetWidths(event) {
    event.preventDefault()
    this.removeStoredWidths()
    this.columnTargets.forEach((column) => column.style.removeProperty("width"))
    this.tableElement?.style.removeProperty("width")
    this.tableElement?.style.removeProperty("min-width")
    this.applyDefaultWidths()
    this.syncTableWidth()
  }

  applySavedWidths() {
    const widths = this.storedWidths()
    if (!widths) return false

    let applied = false
    this.columnTargets.forEach((column) => {
      const width = this.constrainedWidth(column, Number(widths[column.dataset.columnKey]))
      if (!Number.isFinite(width)) return

      column.style.width = `${width}px`
      applied = true
    })

    if (applied) {
      this.requestFrame(() => this.syncTableWidth())
    }

    return applied
  }

  applyDefaultWidths() {
    this.columnTargets.forEach((column) => {
      const width = this.defaultWidth(column)
      if (!Number.isFinite(width) || width <= 0) return

      column.style.width = `${width}px`
    })
  }

  finishResize({ persist }) {
    if (persist) this.storeWidths()

    document.removeEventListener("pointermove", this.boundPointerMove)
    document.removeEventListener("pointerup", this.boundPointerUp)
    document.removeEventListener("pointercancel", this.boundPointerUp)
    this.tableElement?.classList.remove("is-resizing")
    this.resizeState = null
    this.queueTopScrollbarRefresh()
  }

  freezeCurrentColumnWidths() {
    this.columnTargets.forEach((column) => {
      column.style.width = `${this.currentColumnWidth(column)}px`
    })
    this.syncTableWidth()
  }

  syncTableWidth() {
    this.applyTableWidthFromColumns()
    this.queueTopScrollbarRefresh()
  }

  scrollTableFromTop(event) {
    const tableWrap = this.tableWrapElement
    if (!tableWrap || this.scrollSyncSource === "table") return

    this.syncScrollLeft("top", event.currentTarget, tableWrap)
  }

  scrollTopFromTable(event) {
    const topScroll = this.topScrollElement
    if (!topScroll || this.scrollSyncSource === "top") return

    this.syncScrollLeft("table", event.currentTarget, topScroll)
  }

  syncScrollLeft(sourceName, source, target) {
    this.scrollSyncSource = sourceName
    target.scrollLeft = source.scrollLeft
    this.cancelFrame(this.scrollSyncFrame)
    this.scrollSyncFrame = this.requestFrame(() => {
      this.scrollSyncSource = null
      this.scrollSyncFrame = null
    })
  }

  setupResizeObserver() {
    if (typeof ResizeObserver === "undefined") return

    this.resizeObserver = new ResizeObserver(() => this.queueTopScrollbarRefresh())
    const observedElements = [this.tableWrapElement, this.tableElement]
    observedElements.forEach((element) => {
      if (element) this.resizeObserver.observe(element)
    })
  }

  queueTopScrollbarRefresh() {
    if (this.topScrollbarFrame !== null) return

    this.topScrollbarFrame = this.requestFrame(() => {
      this.topScrollbarFrame = null
      this.refreshTopScrollbar()
    })
  }

  refreshTopScrollbar() {
    const tableWrap = this.tableWrapElement
    const topScroll = this.topScrollElement
    const topScrollInner = this.topScrollInnerElement
    if (!tableWrap || !topScroll || !topScrollInner) return

    const totalColumnWidth = this.applyTableWidthFromColumns()
    const clientWidth = Math.ceil(tableWrap.clientWidth)
    const hasOverflow = totalColumnWidth > clientWidth
    const topScrollWidth = hasOverflow ? totalColumnWidth : clientWidth

    topScrollInner.style.width = `${topScrollWidth}px`
    topScroll.hidden = !hasOverflow

    if (hasOverflow) {
      topScroll.scrollLeft = tableWrap.scrollLeft
    } else {
      this.resetScrollPositions()
    }
  }

  applyTableWidthFromColumns() {
    const table = this.tableElement
    if (!table) return 0

    const totalColumnWidth = Math.ceil(this.totalColumnWidth())
    if (!Number.isFinite(totalColumnWidth) || totalColumnWidth <= 0) return 0

    const wrapperWidth = Math.ceil(this.wrapperElement?.clientWidth || 0)
    if (wrapperWidth > 0 && totalColumnWidth <= wrapperWidth) {
      table.style.width = "100%"
      table.style.removeProperty("min-width")
      this.resetScrollPositions()
    } else {
      table.style.width = `${totalColumnWidth}px`
      table.style.minWidth = `${totalColumnWidth}px`
    }

    return totalColumnWidth
  }

  totalColumnWidth() {
    return this.columnTargets.reduce((sum, column) => {
      const width = this.currentColumnWidth(column)
      return Number.isFinite(width) && width > 0 ? sum + width : sum
    }, 0)
  }

  resetScrollPositions() {
    const tableWrap = this.tableWrapElement
    const topScroll = this.topScrollElement

    if (tableWrap) tableWrap.scrollLeft = 0
    if (topScroll) topScroll.scrollLeft = 0
  }

  requestFrame(callback) {
    if (typeof window.requestAnimationFrame === "function") return window.requestAnimationFrame(callback)

    callback()
    return null
  }

  cancelFrame(frame) {
    if (frame !== null && typeof window.cancelAnimationFrame === "function") window.cancelAnimationFrame(frame)
  }

  storeWidths() {
    if (!this.hasStorageKeyValue) return

    const widths = {}
    this.columnTargets.forEach((column) => {
      const key = column.dataset.columnKey
      if (!key) return

      widths[key] = this.currentColumnWidth(column)
    })

    try {
      window.localStorage.setItem(this.storageKeyValue, JSON.stringify(widths))
    } catch (_error) {
      return
    }
  }

  storedWidths() {
    if (!this.hasStorageKeyValue) return null

    try {
      const parsed = JSON.parse(window.localStorage.getItem(this.storageKeyValue))
      return parsed && typeof parsed === "object" ? parsed : null
    } catch (_error) {
      return null
    }
  }

  removeStoredWidths() {
    if (!this.hasStorageKeyValue) return

    try {
      window.localStorage.removeItem(this.storageKeyValue)
    } catch (_error) {
      return
    }
  }

  columnForKey(key) {
    return this.columnTargets.find((column) => column.dataset.columnKey === key)
  }

  currentColumnWidth(column) {
    const inlineWidth = Number.parseFloat(column.style.width)
    if (Number.isFinite(inlineWidth) && inlineWidth > 0) return Math.round(inlineWidth)

    const renderedWidth = column.getBoundingClientRect().width
    if (Number.isFinite(renderedWidth) && renderedWidth > 0) return Math.round(renderedWidth)

    return this.defaultWidth(column)
  }

  constrainedWidth(column, width) {
    if (!Number.isFinite(width) || width <= 0) return Number.NaN

    const minWidth = this.minWidth(column)
    const maxWidth = Number.parseFloat(column.dataset.maxWidth)
    const nextWidth = Math.max(Math.round(width), minWidth)

    return Number.isFinite(maxWidth) && maxWidth > 0 ? Math.min(nextWidth, maxWidth) : nextWidth
  }

  defaultWidth(column) {
    const width = Number.parseFloat(column.dataset.defaultWidth)
    return Number.isFinite(width) && width > 0 ? Math.round(width) : this.minWidth(column)
  }

  minWidth(column) {
    const width = Number.parseFloat(column.dataset.minWidth)
    return Number.isFinite(width) && width > 0 ? Math.round(width) : 80
  }

  get tableElement() {
    return this.hasTableTarget ? this.tableTarget : this.element.querySelector("table.tdk-workbook-table")
  }

  get wrapperElement() {
    return this.tableWrapElement
  }

  get tableWrapElement() {
    return this.hasTableWrapTarget ? this.tableWrapTarget : this.element.querySelector(".tdk-workbook-table-wrap")
  }

  get topScrollElement() {
    return this.hasTopScrollTarget ? this.topScrollTarget : this.element.querySelector(".tdk-workbook-table-scrollbar-top")
  }

  get topScrollInnerElement() {
    return this.hasTopScrollInnerTarget ? this.topScrollInnerTarget : this.element.querySelector(".tdk-workbook-table-scrollbar-top__inner")
  }
}
