# Flying Tulip for the Omarchy bar

A bar widget that puts [Flying Tulip](https://flyingtulip.com) in the Omarchy top bar:

    [tulip] $0.1502  fees $954  HF ∞  PnL $0.00  FT earned 470.8  pts 1.2M  PUT +50.2%

(Numbers above are illustrative.) With no wallet set, the bar shows the FT price, 24h application fees and a
"set wallet" prompt. Set a public wallet address to also see health factor, PnL, FT rewards, points, ftPUT gain and
open positions. Click the widget for an info panel with charts.

All data comes from the public Flying Tulip API (`https://api.flyingtulip.com`). No API keys, no RPC, no private data.
The widget only ever reads data for the public address you give it.

## Install

From the Omarchy plugin marketplace, or directly from this repository:

    omarchy plugin add https://github.com/flyingtulipdotcom/omarchy-ft-bar --enable
    omarchy plugin enable flyingtulip.ft-bar --section right --index 0

To remove it: `omarchy plugin remove flyingtulip.ft-bar`.

A bar widget that is already mounted is not re-instantiated on file changes, so after editing QML run
`omarchy-restart-shell`.

## Set your wallet (no JSON editing)

- click "set wallet" in the bar, or right-click the widget, or press the gear in the click panel;
- paste the 0x address and press Enter. It is validated (0x + 40 hex), stored lowercase in your Omarchy shell settings,
  and everything refreshes at once;
- "Clear" removes it again (HF, PnL, rewards, points, PUT and positions hide).

## Settings

Optional, on the widget's entry in your Omarchy `shell.json`:

| key | default | meaning |
|---|---|---|
| `wallet` | `""` | public address to track (normally set from the UI) |
| `refreshIntervalSec` | `60` | poll interval in seconds (min 15) |
| `hfWarn` | `"1.40"` | warning notification at or below this health factor |
| `hfCritical` | `"1.30"` | critical notification at or below this health factor (keep above 1.25) |
| `notifyCooldownMin` | `30` | minimum minutes between two notifications of the same level |
| `priceChainId` | `1` | chain for the FT-ftUSD market price: 1 Ethereum or 146 Sonic |
| `notificationsEnabled` | `true` | set false to disable desktop notifications |

## Interactions

left click: info panel (gear = wallet, refresh icon, "Open dashboard" opens flyingtulip.com) ·
right click: wallet editor · middle click: refresh.

## What each number is

- **FT price**: FT-ftUSD market price (`/mm/spot/tickers`), with a 30-day line from `/mm/spot/market/klines`.
  This is a market price, not the NAV used for accounting.
- **Fees**: last 24h application fees (`/fees/application`), with 31-day bars and the day-over-day change between the
  last two finished days.
- **HF**: lowest `healthFactor` among your chains that carry debt (`/mm/lend?user=`). No debt shows `∞`; colours follow
  your thresholds.
- **PnL**: sum of `unrealizedPnl` from `/mm/spot/account/summary` across chains.
- **FT earned**: sftUSD yield (claimed + pending) plus Lend FT rewards (received + pending), summed over chains
  (`/account/dashboard?view=rewards`), with a cumulative "FT earned over time" line (all chains, ranges 7d / 30d / 90d / all, Total earned or Claimed) and daily bars, both from `/account/rewards/history?address=&range=`.
- **Points**: `/points` totals, rank from `/points/leaderboard`, earning positions from `/points/breakdown`.
- **ftPUT gain**: from `/tge/ftPUT/user/<wallet>`. cost = sum(current_capital x strike); value =
  (current_ft + withdrawn_ft) x FT market price; gain = value - cost, also shown as a percentage. Hidden with no PUTs.
- **Positions**: `/mm/spot/account/positions` per chain: asset, side, leverage, size, entry, mark, unrealized PnL.

## Liquidation alerts

Positions can be liquidated while the health factor is below 1.25. A warning notification fires at or below `hfWarn`,
a critical one at or below `hfCritical`; each fires once per upward crossing with a 0.05 hysteresis and a cooldown per
level. Alert state is kept in memory only.

## Offline behaviour

Each source keeps its last good value and dims when older than 3 poll intervals. Nothing throws into the bar.

## Tests

`bun test.js` runs the pure logic in `Model.js` (alert state machine, parsers, formatters).

## Disclaimer

Informational only. This is not financial advice and not a substitute for monitoring your positions yourself.
Figures can be delayed, incomplete or wrong. The software is provided "as is", without warranty of any kind (see
[LICENSE](LICENSE)).

## License

MIT, see [LICENSE](LICENSE). The Flying Tulip name and logo are trademarks of Flying Tulip and are not covered by the
MIT license.
