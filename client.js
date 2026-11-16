/**
 * DSH screenshot plugin — Web client half.
 *
 * Adds a screenshot button to the composer's left tool row. The click opens a
 * small chooser (area / window / full screen plus a delay); the Host runs the
 * native Windows capture overlay and returns PNG bytes, which are attached to
 * the current Session draft as a normal image attachment.
 */
window.__ModuleLoader__.load({
  id: '@local/dsh-screenshot',
  factory(require) {
    const React = require('react')
    const { createPortal } = require('react-dom')
    const h = React.createElement

    const NS = 'dsh.screenshot'
    const API = '/api/dsh-screenshot'
    const STORAGE_KEY = 'dsh-screenshot:preferences'
    const MODES = ['region', 'window', 'fullscreen']
    const DELAYS = [0, 1, 3, 5, 10]

    const en = {
      title: 'Screenshot',
      hint: 'Pick a mode and delay, then start',
      'hint.instant': '0s captures what is on screen now, including the DSH window. Pick a delay to capture another window.',
      'hint.delayed': 'Switch to the target window while the countdown runs.',
      tooltip: 'Screenshot (area / window / full screen)',
      modeGroup: 'Mode',
      'mode.region': 'Area',
      'mode.window': 'Window',
      'mode.fullscreen': 'Full screen',
      delay: 'Delay',
      'delay.off': 'Off',
      'delay.seconds': '{count} seconds',
      start: 'Start capture',
      busy: 'Capturing…',
      added: 'Screenshot added to the composer',
      'error.token': 'The screenshot service is unavailable.',
      'error.busy': 'A screenshot is already in progress.',
      'error.failed': 'The screenshot failed.',
      'error.timeout': 'The screenshot took too long and was cancelled.',
      'error.attach': 'Could not add the screenshot to the composer.',
      'error.session': 'The session changed, so the screenshot was not added.',
      'error.unavailable': 'Screenshots are only available on Windows.',
    }

    const zh = {
      title: '截图',
      hint: '选择方式和延迟后开始',
      'hint.instant': '0 秒会立即截取当前画面（DSH 窗口也会入镜）。要截其它窗口，请选择延迟。',
      'hint.delayed': '倒计时期间切换到目标窗口。',
      tooltip: '截图（区域 / 窗口 / 全屏）',
      modeGroup: '方式',
      'mode.region': '区域',
      'mode.window': '窗口',
      'mode.fullscreen': '全屏',
      delay: '延迟',
      'delay.off': '无',
      'delay.seconds': '{count} 秒',
      start: '开始截图',
      busy: '截图中…',
      added: '截图已添加到输入框',
      'error.token': '截图服务不可用。',
      'error.busy': '已有一个截图正在进行。',
      'error.failed': '截图失败。',
      'error.timeout': '截图等待超时，已取消。',
      'error.attach': '无法把截图添加到输入框。',
      'error.session': '会话已切换，截图未添加。',
      'error.unavailable': '截图仅支持 Windows。',
    }

    const CSS = `
.dsh-shot-trigger {
  display: grid;
  place-items: center;
  flex: none;
  width: 28px;
  height: 28px;
  padding: 0;
  border: none;
  border-radius: 999px;
  corner-shape: round;
  background: var(--dsw-specific-selector);
  color: var(--dsw-alias-label-primary);
  cursor: pointer;
}
@media (hover: hover) {
  .dsh-shot-trigger:hover:not(:disabled) {
    background: var(--dsw-alias-interactive-bg-hover-solid);
  }
}
.dsh-shot-trigger[aria-expanded="true"] {
  background: var(--dsw-alias-interactive-bg-hover-solid);
}
.dsh-shot-trigger:disabled {
  opacity: 0.5;
  cursor: default;
}
.dsh-shot-trigger:focus-visible,
.dsh-shot-mode:focus-visible,
.dsh-shot-delay:focus-visible,
.dsh-shot-start:focus-visible {
  outline: var(--dsw-focus-ring-width, 2px) solid var(--dsw-focus-ring-color, var(--dsw-alias-state-business-primary));
  outline-offset: 2px;
}
.dsh-shot-spin {
  animation: dsh-shot-spin 900ms linear infinite;
}
@keyframes dsh-shot-spin {
  to { transform: rotate(360deg); }
}
@media (prefers-reduced-motion: reduce) {
  .dsh-shot-spin { animation-duration: 2400ms; }
}
.dsh-shot-panel {
  position: fixed;
  z-index: 1100;
  box-sizing: border-box;
  width: min(322px, calc(100vw - 24px));
  padding: 14px;
  border: 0;
  border-radius: var(--dsw-radius-lg);
  background: var(--dsw-specific-menu);
  -webkit-backdrop-filter: var(--dsw-menu-backdrop-filter);
  backdrop-filter: var(--dsw-menu-backdrop-filter);
  --dsw-elevation-stroke-color: var(--dsw-alias-border-l1);
  box-shadow: var(--dsw-elevation-prominent);
  color: var(--dsw-alias-label-secondary);
  font-family: var(--dsw-font-family);
  font-size: 13px;
  line-height: 20px;
}
.dsh-shot-heading {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 4px;
}
.dsh-shot-heading strong {
  color: var(--dsw-alias-label-primary);
  font-size: 14px;
  font-weight: 600;
}
.dsh-shot-note {
  margin: 0 0 10px;
  color: var(--dsw-alias-label-tertiary);
  font-size: 11px;
  line-height: 16px;
}
.dsh-shot-modes {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
}
.dsh-shot-mode {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  min-height: 66px;
  padding: 9px 6px 8px;
  border: 1px solid var(--dsw-alias-border-l2);
  border-radius: var(--dsw-radius-md);
  background: transparent;
  color: var(--dsw-alias-label-secondary);
  font: inherit;
  font-size: 12px;
  line-height: 18px;
  cursor: pointer;
}
.dsh-shot-mode svg { color: var(--dsw-alias-label-tertiary); }
@media (hover: hover) {
  .dsh-shot-mode:hover {
    background: var(--dsw-alias-interactive-bg-hover);
    color: var(--dsw-alias-label-primary);
  }
}
.dsh-shot-mode[aria-pressed="true"] {
  border-color: var(--dsw-alias-state-business-primary);
  background: var(--dsw-alias-interactive-bg-hover);
  color: var(--dsw-alias-label-primary);
}
.dsh-shot-mode[aria-pressed="true"] svg { color: var(--dsw-alias-state-business-primary); }
.dsh-shot-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 12px;
}
.dsh-shot-row-label {
  flex: none;
  color: var(--dsw-alias-label-tertiary);
  font-size: 12px;
}
.dsh-shot-delays {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
}
.dsh-shot-delay {
  min-width: 38px;
  height: 26px;
  padding: 0 8px;
  border: 1px solid transparent;
  border-radius: var(--dsw-radius-sm);
  background: var(--dsw-alias-interactive-bg-hover);
  color: var(--dsw-alias-label-secondary);
  font: inherit;
  font-size: 12px;
  cursor: pointer;
}
.dsh-shot-delay[aria-pressed="true"] {
  border-color: var(--dsw-alias-state-business-primary);
  color: var(--dsw-alias-label-primary);
  background: var(--dsw-alias-interactive-bg-hover-solid);
}
.dsh-shot-start {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 36px;
  margin-top: 14px;
  border: none;
  border-radius: var(--dsw-radius-md);
  background: var(--dsw-alias-label-primary);
  color: var(--dsw-alias-bg-layer-3);
  font: inherit;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
}
.dsh-shot-start:disabled { opacity: 0.6; cursor: default; }
@media (hover: hover) {
  .dsh-shot-start:hover:not(:disabled) { background: var(--dsw-alias-label-secondary); }
}
.dsh-shot-error {
  margin-top: 10px;
  padding: 6px 8px;
  border-radius: var(--dsw-radius-sm);
  background: var(--dsw-alias-interactive-bg-hover);
  color: var(--dsw-alias-state-error-primary);
  font-size: 12px;
  line-height: 18px;
}
.dsh-shot-toast {
  position: fixed;
  left: 50%;
  bottom: 132px;
  z-index: 1200;
  transform: translateX(-50%);
  max-width: min(420px, calc(100vw - 32px));
  padding: 8px 14px;
  border-radius: var(--dsw-radius-md);
  background: var(--dsw-specific-menu);
  -webkit-backdrop-filter: var(--dsw-menu-backdrop-filter);
  backdrop-filter: var(--dsw-menu-backdrop-filter);
  --dsw-elevation-stroke-color: var(--dsw-alias-border-l1);
  box-shadow: var(--dsw-elevation-prominent);
  color: var(--dsw-alias-label-primary);
  font-family: var(--dsw-font-family);
  font-size: 13px;
  line-height: 20px;
  text-align: center;
}
.dsh-shot-toast[data-kind="error"] { color: var(--dsw-alias-state-error-primary); }
`

    function currentLanguage() {
      const tag = String(document.documentElement.lang || navigator.language || 'zh').toLowerCase()
      return tag.startsWith('zh') ? 'zh' : 'en'
    }

    function translate(t, key, vars) {
      let value = typeof t === 'function' ? t(key) : key
      if (value === key) value = (currentLanguage() === 'zh' ? zh : en)[key] ?? key
      if (vars !== undefined) {
        for (const [name, replacement] of Object.entries(vars)) {
          value = value.split(`{${name}}`).join(String(replacement))
        }
      }
      return value
    }

    let tokenPromise = null
    function getToken() {
      tokenPromise ??= fetch(`${API}/token`, { credentials: 'same-origin' })
        .then(async (response) => {
          if (!response.ok) throw new Error(`token HTTP ${response.status}`)
          const payload = await response.json()
          if (typeof payload.token !== 'string' || payload.token.length === 0) throw new Error('missing token')
          return payload.token
        })
        .catch((error) => {
          tokenPromise = null
          throw error
        })
      return tokenPromise
    }

    function readPreferences() {
      try {
        const raw = localStorage.getItem(STORAGE_KEY)
        if (raw === null) return { mode: 'region', delay: 0 }
        const parsed = JSON.parse(raw)
        return {
          mode: MODES.includes(parsed.mode) ? parsed.mode : 'region',
          delay: DELAYS.includes(parsed.delay) ? parsed.delay : 0,
        }
      } catch {
        return { mode: 'region', delay: 0 }
      }
    }

    function writePreferences(mode, delay) {
      try { localStorage.setItem(STORAGE_KEY, JSON.stringify({ mode, delay })) } catch { /* private mode */ }
    }

    function CameraIcon({ size = 16 }) {
      return h('svg', { viewBox: '0 0 16 16', width: size, height: size, 'aria-hidden': true, fill: 'none' },
        h('path', {
          d: 'M2.6 5.1h2.1l.8-1.2h5l.8 1.2h2.1c.5 0 .9.4.9.9v6c0 .5-.4.9-.9.9H2.6a.9.9 0 0 1-.9-.9v-6c0-.5.4-.9.9-.9Z',
          stroke: 'currentColor', strokeWidth: 1.35, strokeLinejoin: 'round',
        }),
        h('circle', { cx: 8, cy: 8.6, r: 2.35, stroke: 'currentColor', strokeWidth: 1.35 }),
      )
    }

    function SpinnerIcon() {
      return h('svg', { viewBox: '0 0 16 16', width: 16, height: 16, className: 'dsh-shot-spin', 'aria-hidden': true, fill: 'none' },
        h('circle', { cx: 8, cy: 8, r: 5.6, stroke: 'currentColor', strokeOpacity: 0.28, strokeWidth: 1.8 }),
        h('path', { d: 'M8 2.4a5.6 5.6 0 0 1 5.6 5.6', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round' }),
      )
    }

    function RegionIcon() {
      return h('svg', { viewBox: '0 0 20 20', width: 22, height: 22, 'aria-hidden': true, fill: 'none' },
        h('rect', { x: 2.5, y: 2.5, width: 15, height: 15, rx: 2, stroke: 'currentColor', strokeWidth: 1.4, strokeDasharray: '3 2.5' }),
        h('path', { d: 'M7 2.5v3M13 2.5v3M7 14.5v3M13 14.5v3M2.5 7h3M2.5 13h3M14.5 7h3M14.5 13h3', stroke: 'currentColor', strokeWidth: 1.4, strokeLinecap: 'round' }),
      )
    }

    function WindowIcon() {
      return h('svg', { viewBox: '0 0 20 20', width: 22, height: 22, 'aria-hidden': true, fill: 'none' },
        h('rect', { x: 2.5, y: 4.5, width: 11, height: 9, rx: 1.5, stroke: 'currentColor', strokeWidth: 1.4 }),
        h('path', { d: 'M2.5 7.5h11', stroke: 'currentColor', strokeWidth: 1.4 }),
        h('path', { d: 'M6 16.5h9.5a2 2 0 0 0 2-2V8', stroke: 'currentColor', strokeWidth: 1.4, strokeLinecap: 'round' }),
      )
    }

    function FullscreenIcon() {
      return h('svg', { viewBox: '0 0 20 20', width: 22, height: 22, 'aria-hidden': true, fill: 'none' },
        h('path', { d: 'M3 7V3h4M13 3h4v4M17 13v4h-4M7 17H3v-4', stroke: 'currentColor', strokeWidth: 1.5, strokeLinecap: 'round', strokeLinejoin: 'round' }),
      )
    }

    function ClockIcon() {
      return h('svg', { viewBox: '0 0 16 16', width: 14, height: 14, 'aria-hidden': true, fill: 'none' },
        h('circle', { cx: 8, cy: 8, r: 5.6, stroke: 'currentColor', strokeWidth: 1.3 }),
        h('path', { d: 'M8 4.8V8l2.2 1.4', stroke: 'currentColor', strokeWidth: 1.3, strokeLinecap: 'round', strokeLinejoin: 'round' }),
      )
    }

    const MODE_ICONS = { region: RegionIcon, window: WindowIcon, fullscreen: FullscreenIcon }

    function ScreenshotControl(props) {
      const t = props.t
      const tr = (key, vars) => translate(t, key, vars)
      const failLocalized = (key) => {
        const error = new Error(tr(key))
        error.dshScreenshotLocalized = true
        return error
      }
      const failureText = (caught) => {
        if (caught instanceof Error && caught.dshScreenshotLocalized === true) return caught.message
        const message = caught instanceof Error ? caught.message : String(caught)
        if (/only available on Windows/i.test(message)) return tr('error.unavailable')
        if (/already in progress/i.test(message)) return tr('error.busy')
        if (/token|HTTP 403|HTTP 501/i.test(message)) return tr('error.token')
        if (/timed out|timeout/i.test(message)) return tr('error.timeout')
        return tr('error.failed')
      }
      const [open, setOpen] = React.useState(false)
      const [busy, setBusy] = React.useState(false)
      const [error, setError] = React.useState(null)
      const [toast, setToast] = React.useState(null)
      const initial = React.useMemo(readPreferences, [])
      const [mode, setMode] = React.useState(initial.mode)
      const [delay, setDelay] = React.useState(initial.delay)
      const [position, setPosition] = React.useState(null)
      const triggerRef = React.useRef(null)
      const panelRef = React.useRef(null)
      const live = React.useRef({ sessionId: undefined, inputActions: undefined, ordinary: true, subagent: null, mounted: true })
      const toastTimer = React.useRef(null)

      const sessionId = props.sessionId
      const inputActions = props.inputActions
      const useSession = props.useSession
      const useInput = props.useInput
      const subagent = useSession === undefined ? null : useSession(s => s.subagent)
      const removed = useSession === undefined ? false : useSession(s => s.removed)
      const phase = useInput === undefined ? 'plain' : useInput(s => s.phase)
      const continuable = subagent !== null && subagent?.address?.mode === 'continuable'
      const canAttach = subagent === null || continuable
      const disabled = busy || removed || phase !== 'plain' || !canAttach || sessionId === undefined

      live.current = {
        sessionId,
        inputActions,
        ordinary: subagent === null,
        subagent,
        mounted: true,
      }

      React.useEffect(() => {
        live.current.mounted = true
        return () => { live.current.mounted = false }
      }, [])

      const showToast = React.useCallback((kind, text) => {
        setToast({ kind, text })
        if (toastTimer.current !== null) clearTimeout(toastTimer.current)
        toastTimer.current = setTimeout(() => { setToast(null); toastTimer.current = null }, kind === 'error' ? 4200 : 2200)
      }, [])

      React.useEffect(() => () => {
        if (toastTimer.current !== null) clearTimeout(toastTimer.current)
      }, [])

      const place = React.useCallback(() => {
        const anchor = triggerRef.current
        const panel = panelRef.current
        if (anchor === null) return
        const rect = anchor.getBoundingClientRect()
        const width = panel === null ? 322 : panel.offsetWidth
        const height = panel === null ? 300 : panel.offsetHeight
        const margin = 12
        const gap = 8
        let left = rect.left
        left = Math.min(Math.max(margin, left), window.innerWidth - width - margin)
        let top = rect.top - height - gap
        if (top < margin) top = Math.min(window.innerHeight - height - margin, rect.bottom + gap)
        setPosition({ left, top })
      }, [])

      React.useLayoutEffect(() => {
        if (!open) { setPosition(null); return undefined }
        place()
        const frame = requestAnimationFrame(place)
        const onResize = () => { place() }
        window.addEventListener('resize', onResize)
        window.addEventListener('scroll', onResize, true)
        return () => {
          cancelAnimationFrame(frame)
          window.removeEventListener('resize', onResize)
          window.removeEventListener('scroll', onResize, true)
        }
      }, [open, place])

      React.useEffect(() => {
        if (!open) return undefined
        const onPointerDown = (event) => {
          const target = event.target
          if (triggerRef.current?.contains(target) === true) return
          if (panelRef.current?.contains(target) === true) return
          setOpen(false)
        }
        const onKeyDown = (event) => {
          if (event.key === 'Escape') {
            event.stopPropagation()
            event.preventDefault()
            setOpen(false)
            requestAnimationFrame(() => { triggerRef.current?.focus() })
          }
        }
        document.addEventListener('pointerdown', onPointerDown, true)
        document.addEventListener('keydown', onKeyDown, true)
        return () => {
          document.removeEventListener('pointerdown', onPointerDown, true)
          document.removeEventListener('keydown', onKeyDown, true)
        }
      }, [open])

      const attach = React.useCallback(async (blob, name) => {
        const current = live.current
        if (current.mounted !== true) return
        if (current.sessionId === undefined) throw failLocalized('error.attach')
        if (current.sessionId !== sessionId) throw failLocalized('error.session')
        const file = new File([blob], name, { type: 'image/png' })
        const conversation = pluginContext.get('conversation')
        const actions = current.inputActions
        if (conversation !== undefined && typeof conversation.createDrafts === 'function' && actions !== undefined) {
          const drafts = conversation.createDrafts(current.sessionId, [file], current.ordinary)
          const accepted = actions.addAttachments(drafts.map(draft => draft.id))
          if (accepted !== true) {
            try { conversation.releaseDraftAttachments(drafts) } catch { /* best effort */ }
            throw failLocalized('error.attach')
          }
          showToast('ok', tr('added'))
          return
        }
        // Defensive fallback for a future Host without the concrete draft
        // method: use the composer's ordinary file-drop intake.
        const transfer = new DataTransfer()
        transfer.items.add(file)
        const target = triggerRef.current?.closest('[data-composer-card]') ?? document.body
        target.dispatchEvent(new DragEvent('drop', { dataTransfer: transfer, bubbles: true, cancelable: true }))
        showToast('ok', tr('added'))
      }, [sessionId, showToast, tr])

      const start = React.useCallback(async () => {
        if (busy) return
        setBusy(true)
        setError(null)
        setOpen(false)
        writePreferences(mode, delay)
        try {
          const token = await getToken()
          const response = await fetch(`${API}/capture?token=${encodeURIComponent(token)}`, {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
              'Content-Type': 'application/json',
              'X-DSH-Screenshot-Token': token,
            },
            body: JSON.stringify({ mode, delay, lang: currentLanguage(), token }),
          })
          if (!response.ok) {
            let message = tr('error.failed')
            try {
              const payload = await response.json()
              if (typeof payload.error === 'string' && payload.error.length > 0) message = payload.error
            } catch { /* keep generic */ }
            throw new Error(message)
          }
          const contentType = response.headers.get('content-type') || ''
          if (contentType.includes('application/json')) {
            const payload = await response.json()
            if (payload.cancelled === true) return
            throw new Error(typeof payload.error === 'string' ? payload.error : tr('error.failed'))
          }
          const blob = await response.blob()
          const encodedName = response.headers.get('x-dsh-screenshot-name')
          let name = `screenshot-${Date.now()}.png`
          if (encodedName !== null) {
            try { name = decodeURIComponent(encodedName) } catch { /* keep fallback */ }
          }
          await attach(blob, name)
        } catch (caught) {
          if (!(caught instanceof Error && caught.dshScreenshotLocalized === true)) {
            console.error('[dsh-screenshot] capture failed:', caught)
          }
          const friendly = failureText(caught)
          setError(friendly)
          setOpen(true)
          showToast('error', friendly)
        } finally {
          if (live.current.mounted === true) setBusy(false)
        }
      }, [attach, busy, delay, mode, showToast, tr])

      const chooseMode = (next) => {
        setMode(next)
        writePreferences(next, delay)
      }
      const chooseDelay = (next) => {
        setDelay(next)
        writePreferences(mode, next)
      }

      const modeLabel = { region: tr('mode.region'), window: tr('mode.window'), fullscreen: tr('mode.fullscreen') }
      const delayLabel = value => value === 0 ? tr('delay.off') : tr('delay.seconds', { count: value })

      const trapFocus = (event) => {
        if (event.key !== 'Tab' || panelRef.current === null) return
        const focusable = [...panelRef.current.querySelectorAll('button:not(:disabled)')]
        if (focusable.length === 0) return
        const first = focusable[0]
        const last = focusable[focusable.length - 1]
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault()
          last.focus()
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault()
          first.focus()
        }
      }

      const panel = open && h('div', {
        ref: panelRef,
        className: 'dsh-shot-panel',
        role: 'dialog',
        'aria-label': tr('title'),
        style: {
          left: `${position === null ? -9999 : position.left}px`,
          top: `${position === null ? -9999 : position.top}px`,
        },
        onPointerDown: event => { event.stopPropagation() },
        onClick: event => { event.stopPropagation() },
        onKeyDown: trapFocus,
      },
        h('div', { className: 'dsh-shot-heading' },
          h('strong', null, tr('title')),
        ),
        h('p', { className: 'dsh-shot-note' }, delay === 0 ? tr('hint.instant') : tr('hint.delayed')),
        h('div', { className: 'dsh-shot-modes', role: 'group', 'aria-label': tr('modeGroup') },
          MODES.map(value => {
            const Icon = MODE_ICONS[value]
            return h('button', {
              key: value,
              type: 'button',
              className: 'dsh-shot-mode',
              'aria-pressed': mode === value ? 'true' : 'false',
              autoFocus: mode === value,
              onClick: () => { chooseMode(value) },
            }, h(Icon), h('span', null, modeLabel[value]))
          }),
        ),
        h('div', { className: 'dsh-shot-row' },
          h('span', { className: 'dsh-shot-row-label' }, h(ClockIcon), ' ', tr('delay')),
          h('div', { className: 'dsh-shot-delays', role: 'group', 'aria-label': tr('delay') },
            DELAYS.map(value => h('button', {
              key: value,
              type: 'button',
              className: 'dsh-shot-delay',
              'aria-pressed': delay === value ? 'true' : 'false',
              onClick: () => { chooseDelay(value) },
            }, delayLabel(value))),
          ),
        ),
        error !== null && h('div', { className: 'dsh-shot-error', role: 'alert' }, error),
        h('button', {
          type: 'button',
          className: 'dsh-shot-start',
          onClick: () => { void start() },
        }, busy ? tr('busy') : tr('start')),
      )

      return h(React.Fragment, null,
        h('button', {
          ref: triggerRef,
          type: 'button',
          className: 'dsh-shot-trigger',
          'aria-label': tr('tooltip'),
          'aria-haspopup': 'dialog',
          'aria-expanded': open ? 'true' : 'false',
          title: tr('tooltip'),
          disabled,
          'aria-busy': busy ? 'true' : undefined,
          onClick: () => { setOpen(value => !value); setError(null) },
        }, busy ? h(SpinnerIcon) : h(CameraIcon)),
        panel === false ? null : (typeof document === 'undefined' ? null : createPortal(panel, document.body)),
        toast !== null && typeof document !== 'undefined'
          ? createPortal(h('div', {
            className: 'dsh-shot-toast',
            'data-kind': toast.kind,
            role: toast.kind === 'error' ? 'alert' : 'status',
          }, toast.text), document.body)
          : null,
      )
    }

    let pluginContext = null

    return {
      inject: ['slots', 'locale'],
      apply(pluginCtx) {
        pluginContext = pluginCtx
        pluginCtx.effect(() => pluginCtx.locale.register(NS, { en, zh }), 'dsh-screenshot: dictionaries')
        pluginCtx.effect(() => {
          const style = document.createElement('style')
          style.dataset.dshScreenshot = ''
          style.textContent = CSS
          document.head.appendChild(style)
          return () => { style.remove() }
        }, 'dsh-screenshot: styles')
        pluginCtx.slots.inject('conversation.input.left', () => pluginCtx.slots.register({
          name: 'conversation.input.left',
          id: 'dsh-screenshot',
          order: 10,
          label: () => pluginCtx.locale.bind(NS)('tooltip'),
          locale: NS,
        }, ScreenshotControl))
      },
    }
  },
})
