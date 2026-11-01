# Rulebook Reporter — read-only MT5 watcher EA

A MetaTrader 5 Expert Advisor that **only looks and reports**. It watches
the account it is attached to and emits a JSON event whenever something
happens — so an external tool (a dashboard, a logger, a coaching/review
system) can follow your trading without ever touching your trades.

## What it reports

| Event | When |
|---|---|
| `POSITION_OPEN` | A position appears |
| `POSITION_SLTP_CHANGE` | Stop-loss or take-profit changes |
| `POSITION_CLOSE` | A position disappears |
| `DEAL` | Every entry/exit fill |
| `HEARTBEAT` | Every 60s (configurable): balance, equity, open count |

## What it never does

There is **no order-sending code in this file at all** — no `OrderSend`,
no `CTrade`, no position close/modify calls. It cannot open, close, or
change any trade. Verify it yourself before installing:

```
grep -n "OrderSend\|CTrade" RulebookReporter.mq5   # → no matches
```

It also never sees or sends your account password.

## Install

1. In MT5: **File → Open Data Folder → MQL5 → Experts**, copy
   `RulebookReporter.mq5` there.
2. Open it in MetaEditor and compile (**F7**) — expect "0 errors".
3. Drag the EA onto **any one chart** of the account. Done — by default
   it runs in LOCAL MODE (see below).

## Modes

- **Local mode (default):** leave `InpWatcherURL` empty. Events are
  written to a log file in the MT5 Files folder and printed to the
  Experts journal. Nothing leaves your computer.
- **Watcher mode:** set `InpWatcherURL` to your own HTTPS endpoint.
  Each event is POSTed as JSON. Set `InpSharedSecret` and the EA sends
  it as an `X-Reporter-Token` header so your endpoint can reject
  strangers. You must also whitelist the URL in MT5 under
  **Tools → Options → Expert Advisors → "Allow WebRequest for listed URL"**.

## Example event

```json
{"event":"POSITION_OPEN","account_login":12345678,"account_server":"Broker-Demo","account_tag":"demo","time_server":"2026-10-20 12:00:03","balance":2000.00,"equity":2000.00, ...}
```

## Privacy, stated plainly

In watcher mode the payload includes your **account login number**
(not the password) plus balance/equity and position details — sent
**only** to the URL you set. If that bothers you, stay in local mode,
or strip the field; the source is short and commented.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `InpWatcherURL` | *(empty)* | Watcher endpoint; empty = local mode |
| `InpSharedSecret` | *(empty)* | Token sent as `X-Reporter-Token` header |
| `InpPollSeconds` | 3 | Position poll interval |
| `InpHeartbeatSecs` | 60 | Heartbeat interval |
| `InpLocalAlerts` | true | Popup alert on position open/close |
| `InpAccountTag` | *(empty)* | Free label, e.g. `demo` / `live` |

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, ship it; no warranty.
Trading involves risk; this tool only reports, it does not advise.
