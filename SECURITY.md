# Security

## What this plugin does with screen data

- Screen capture starts only from an explicit user click on **Start capture**.
- A local `powershell.exe` child process draws the selection overlay, captures
  the screen with GDI/`PrintWindow`, and writes one PNG under
  `$DSH_HOME/screenshots`.
- The PNG is returned to the same-origin DSH page and attached to the current
  session's draft through the normal DSH attachment path.
- The plugin has no outbound network calls, no telemetry, and no credentials.

## Local HTTP route

The Host half registers `/api/dsh-screenshot` on the DSH Web server:

- `GET /api/dsh-screenshot/token` returns a random per-activation token.
- `POST /api/dsh-screenshot/capture` requires that token and a mode/delay body.

The token exists so a random web page cannot trigger an interactive capture in
the background. It is readable only by code that can reach the DSH Web server on
loopback; cross-origin pages cannot read the token response. This is a
same-user local trust boundary, not a network security boundary — do not bind
the DSH Web server to an untrusted network while using this plugin.

The route accepts the token from the query string, the
`X-DSH-Screenshot-Token` header, or the JSON body, because the Desktop fetch
bridge may not preserve custom headers. The token is short-lived and changes
when the Host plugin restarts.

## Process execution

The Host spawns:

```
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
  -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass
  -File host\screenshot.ps1 ...
```

The script is shipped in the package and is not downloaded at runtime. It
contains no `Invoke-WebRequest`, `Start-Process`, registry writes, or
credential access. The capture overlay hides itself from the captured image
(the frozen desktop snapshot is taken before the overlay is shown).

## Reporting

Open an issue on the repository. Do not include screenshots that contain
personal data; describe the behavior instead.
