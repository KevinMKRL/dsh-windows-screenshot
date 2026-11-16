/**
 * DSH screenshot plugin — Host half.
 *
 * Owns the Windows-native capture process and serves the small same-origin HTTP
 * surface the Web client uses:
 *
 *   GET  /api/dsh-screenshot/token    -> { token }
 *   POST /api/dsh-screenshot/capture  -> image/png (or JSON when cancelled/failed)
 *
 * The token is only readable from a same-origin page, so a random page cannot
 * start an interactive capture behind the user's back.
 */
import { spawn } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { mkdir, readFile, unlink } from 'node:fs/promises'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

/** Mounted webserver routes need this service. */
export const inject = ['webServer']

const ROUTE = '/api/dsh-screenshot'
const SCRIPT = fileURLToPath(new URL('./host/screenshot.ps1', import.meta.url))
const TOKEN = randomBytes(24).toString('hex')
const CAPTURE_TIMEOUT_MS = 10 * 60 * 1000
const MAX_DIAGNOSTIC = 16 * 1024

/** Windows system PowerShell, independent of the user's PATH. */
function powershellPath() {
  const root = process.env.SystemRoot || process.env.windir || 'C:\\Windows'
  return join(root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
}

/** Directory screenshots are kept in; also returned to the user in the UI. */
function screenshotDir() {
  const home = process.env.DSH_HOME || join(homedir(), '.dsh')
  return join(home, 'screenshots')
}

/** Timestamped PNG name; never reuse a name so cached previews cannot go stale. */
function screenshotName() {
  const now = new Date()
  const pad = (value, width = 2) => String(value).padStart(width, '0')
  return `screenshot-${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`
    + `-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}-${pad(now.getMilliseconds(), 3)}.png`
}

/** Write one JSON response. */
function json(res, status, value) {
  const body = JSON.stringify(value)
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  })
  res.end(body)
}

/** Read a request body up to a small bound. */
function readBody(req, limit = 64 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0
    const chunks = []
    req.on('data', (chunk) => {
      size += chunk.length
      if (size > limit) {
        reject(new Error('request body too large'))
        req.destroy()
        return
      }
      chunks.push(chunk)
    })
    req.on('end', () => { resolve(Buffer.concat(chunks).toString('utf8')) })
    req.on('error', reject)
  })
}

/** Run the PowerShell snipping overlay and return its parsed result. */
function runCapture({ mode, delay, lang }) {
  return new Promise((resolve, reject) => {
    const outputPath = join(screenshotDir(), screenshotName())
    const resultPath = join(tmpdir(), `dsh-screenshot-${randomBytes(8).toString('hex')}.json`)
    const args = [
      '-NoProfile', '-NonInteractive', '-STA', '-ExecutionPolicy', 'Bypass',
      '-File', SCRIPT,
      '-Mode', mode,
      '-Delay', String(delay),
      '-OutputPath', outputPath,
      '-ResultPath', resultPath,
      '-Language', lang === 'en' ? 'en' : 'zh',
      '-RestorePid', String(process.pid),
    ]
    const child = spawn(powershellPath(), args, {
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    let diagnostics = ''
    const collect = (chunk) => {
      if (diagnostics.length < MAX_DIAGNOSTIC) diagnostics += chunk.toString('utf8')
    }
    child.stdout?.on('data', collect)
    child.stderr?.on('data', collect)
    let settled = false
    const finish = async (result) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      try { await unlink(resultPath) } catch { /* absent on failures */ }
      if (result.ok) {
        try {
          const bytes = await readFile(result.path)
          resolve({ ok: true, bytes, name: result.path.split(/[\\/]/).at(-1) ?? screenshotName(), result })
        } catch (error) {
          reject(error)
        }
        return
      }
      if (result.cancelled) {
        resolve({ ok: false, cancelled: true })
        return
      }
      reject(new Error(result.error || diagnostics || 'screenshot process failed'))
    }
    const timer = setTimeout(() => {
      try { child.kill() } catch { /* already gone */ }
      if (!settled) {
        settled = true
        reject(new Error('screenshot timed out'))
      }
    }, CAPTURE_TIMEOUT_MS)
    child.on('error', (error) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      reject(error)
    })
    child.on('close', async () => {
      if (settled) return
      let result
      try {
        result = JSON.parse(await readFile(resultPath, 'utf8'))
      } catch (error) {
        settled = true
        clearTimeout(timer)
        try { await unlink(resultPath) } catch { /* absent */ }
        reject(new Error(diagnostics.trim() || `screenshot process produced no result (${error.message})`))
        return
      }
      await finish(result)
    })
  })
}

/**
 * Register the capture route.
 * @param ctx - Plugin context carrying the Web server.
 */
export function apply(ctx) {
  let active = null
  ctx.effect(() => ctx.webServer.register({
    kind: 'prefix',
    path: ROUTE,
    handler: async (req, res) => {
      try {
        const url = new URL(req.url ?? '/', 'http://127.0.0.1')
        const path = url.pathname

        if (path === `${ROUTE}/token` && req.method === 'GET') {
          json(res, 200, { token: TOKEN, platform: process.platform })
          return
        }

        if (path === `${ROUTE}/capture` && req.method === 'POST') {
          if (process.platform !== 'win32') {
            json(res, 501, { ok: false, error: 'Screenshots are only available on Windows.' })
            return
          }
          const body = await readBody(req)
          let payload = {}
          try { payload = JSON.parse(body || '{}') } catch { /* validated below */ }
          // Same-origin pages fetch the token first; accept it from the query,
          // the header, or the JSON body so the Electron fetch bridge cannot
          // break the check by dropping a custom header.
          const suppliedToken = url.searchParams.get('token')
            ?? req.headers['x-dsh-screenshot-token']
            ?? payload.token
          if (suppliedToken !== TOKEN) {
            json(res, 403, { ok: false, error: 'Invalid screenshot token.' })
            return
          }
          if (active !== null) {
            json(res, 409, { ok: false, error: 'A screenshot is already in progress.' })
            return
          }
          const mode = payload.mode
          if (mode !== 'region' && mode !== 'window' && mode !== 'fullscreen') {
            json(res, 400, { ok: false, error: 'Unknown screenshot mode.' })
            return
          }
          const delay = Number.isInteger(payload.delay) ? payload.delay : 0
          if (delay < 0 || delay > 60) {
            json(res, 400, { ok: false, error: 'Delay must be between 0 and 60 seconds.' })
            return
          }
          const lang = typeof payload.lang === 'string' ? payload.lang : 'zh'
          active = runCapture({ mode, delay, lang })
          let capture
          try {
            capture = await active
          } finally {
            active = null
          }
          if (capture.cancelled) {
            json(res, 200, { ok: false, cancelled: true })
            return
          }
          res.writeHead(200, {
            'Content-Type': 'image/png',
            'Content-Length': capture.bytes.length,
            'Cache-Control': 'no-store',
            'X-DSH-Screenshot-Name': encodeURIComponent(capture.name),
          })
          res.end(capture.bytes)
          return
        }

        json(res, 404, { ok: false, error: 'Unknown screenshot route.' })
      } catch (error) {
        try {
          json(res, 500, { ok: false, error: error instanceof Error ? error.message : String(error) })
        } catch { /* response already started */ }
      }
    },
  }), 'dsh-screenshot: capture routes')
}
