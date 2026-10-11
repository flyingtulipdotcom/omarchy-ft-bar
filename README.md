# Flying Tulip for the Omarchy bar

A bar widget that puts [Flying Tulip](https://flyingtulip.com) in the Omarchy top bar:

    [tulip] $0.1502  fees $954  HF ∞  PnL $0.00  FT earned 470.8  pts 1.2M  PUT +50.2%  0xd67d…6fcd ⇄

(Numbers above are illustrative.) With no wallet set, the bar shows the FT price, 24h application fees and a
"set wallet" prompt. Add one or more public wallet addresses to also see health factor, PnL, FT rewards, points, ftPUT
gain and open positions. Click the widget for an info panel in three tabs (Market, Account, Positions), so nothing
needs scrolling; the panel remembers the last tab.

## Several wallets

- The bar shows one wallet at a time and moves to the next one every minute (`rotateSec`). With more than one wallet
  the bar ends with the shown wallet's short address and a switch icon ⇄: click the icon for the next wallet now.
- If any wallet's health factor is at or below your warning threshold, that wallet is shown at once and stays shown
  while it is low (a click on ⇄ peeks at the others; the next minute it comes back). The notification names the wallet.
- The wallets you are not looking at are checked in the background: their health factor (`/mm/lend`) every refresh
  while they have debt, every 10 minutes otherwise. Everything else is fetched for the wallet shown only, so a second
  wallet adds about one extra request per refresh, not a second full refresh.
- The panel header shows which wallet it is about ("0xd67d…6fcd  1/2") with the same ⇄ button.

All data comes from the public Flying Tulip API (`https://api.flyingtulip.com`). No API keys, no RPC, no private data.
The widget only ever reads data for the public address you give it.

## Install

From the Omarchy plugin marketplace, or directly from this repository:

    omarchy plugin add https://github.com/flyingtulipdotcom/omarchy-ft-bar --enable
    omarchy plugin enable flyingtulip.ft-bar --section right --index 0

To remove it: `omarchy plugin remove flyingtulip.ft-bar`.

A bar widget that is already mounted is not re-instantiated on file changes, so after editing QML run
`omarchy-restart-shell`.

## Set your wallets (no JSON editing)

- click "set wallet" in the bar, or right-click the widget, or press the gear in the click panel;
- paste a 0x address and press Enter (or Add). It is validated (0x + 40 hex), stored lowercase in a per-user state file
  (see below), and shown at once. Several addresses separated by commas or spaces can be pasted together;
- the list in the editor: click an address to show it, ✎ to replace it with another address, ✕ to remove it.

## Where settings live

Your wallet and your overrides are kept in a per-user file that plugin updates, removal and re-adding never touch:

    $XDG_STATE_HOME/flyingtulip-ft-bar/settings.json     (default: ~/.local/state/flyingtulip-ft-bar/settings.json)

It is written atomically by the wallet editor. On start the widget reads this file first, then falls back to the same
key on the widget's entry in `shell.json`, then to the default. Values found only on the `shell.json` entry are copied into
the file once. Delete the file to forget the wallet. (A copy of the wallet is also kept on the `shell.json` entry as a
plain fallback, but the file wins.)

## Settings

Optional keys, read from the file above or from the widget's entry in your Omarchy `shell.json` (the file wins):

| key | default | meaning |
|---|---|---|
| `wallets` | `[]` | public addresses to track (normally set from the UI) |
| `wallet` | `""` | the single address of 1.0.x, still read (kept equal to the first of `wallets`) |
| `rotateSec` | `60` | seconds each wallet is shown before the next one (min 10) |
| `tab` | | the panel tab last shown (written by the panel) |
| `refreshIntervalSec` | `60` | poll interval in seconds (min 15) |
| `hfWarn` | `"1.40"` | warning notification at or below this health factor |
| `hfCritical` | `"1.30"` | critical notification at or below this health factor (keep above 1.25) |
| `notifyCooldownMin` | `30` | minimum minutes between two notifications of the same level |
| `priceChainId` | `1` | chain for the FT-ftUSD market price: 1 Ethereum or 146 Sonic |
| `notificationsEnabled` | `true` | set false to disable desktop notifications |

## Interactions

The bar widget opens no links: left click anywhere on it toggles the info panel, right click is the
wallet editor, middle click a refresh.

Inside the panel every element opens its page on flyingtulip.com in the default browser:

| Panel element | Opens |
| --- | --- |
| header logo and title, footer | `/` |
| FT price stat and chart | `/trade/?symbol=FT-ftUSD&chainId=<priceChainId>&marketType=spot` |
| fees stats, daily fees chart, fee breakdown | `/statistics/` |
| health factor card and each chain row | `/lend/dashboard/` |
| PnL card, positions card | `/trade/portfolio/` |
| each position row | that market's `/trade/?symbol=...&chainId=...&marketType=spot` |
| FT earned card and both FT earned charts | `/rewards/` |
| points card | `/rewards/leaderboard/` |
| points positions | `/rewards/my-activity/` |
| ftPUT gain card and ftPUT positions | `/allocation/positions/` |

The gear and refresh buttons and the range pills keep their actions.

## What each number is

- **FT price**: FT-ftUSD market price (`/mm/spot/tickers`), with a 30-day line from `/mm/spot/market/klines`.
  This is a market price, not the NAV used for accounting.
- **Fees**: last 24h application fees (`/fees/application`), with 31-day bars and the day-over-day change between the
  last two finished days.
- **HF**: lowest `healthFactor` among your chains that carry debt (`/mm/lend?user=`). No debt shows `∞`; colours follow
  your thresholds.
- **PnL**: sum of `unrealizedPnl` from `/mm/spot/account/summary` across chains.
- **FT earned**: all time and all chains. sftUSD yield (claimed + pending) plus Lend FT rewards (received + pending),
  summed over chains (`/account/dashboard?view=rewards`). The panel card splits it into sftUSD yield and Lend and by
  chain. It is what the wallet's sftUSD staking and Lend supply have paid out over time, so it does not follow the
  wallet's current size: a small wallet that staked sftUSD for months can show more than a large wallet that only
  started supplying Lend last week. FT held in ftPUTs is not counted. The panel also has a cumulative "FT earned over
  time" line (all chains, ranges 7d / 30d / 90d / all, Total earned or Claimed) and daily bars, both from
  `/account/rewards/history?address=&range=`.
- **Points**: the all-chains total from `/points` (the number the leaderboard ranks), split per chain in the panel,
  rank from `/points/leaderboard`, earning positions from `/points/breakdown`. The big number on flyingtulip.com/rewards
  is one chain at a time (the chain picker in the site header), and the all-networks total is the small line under it.
- **ftPUT gain**: from `/tge/ftPUT/user/<wallet>`. cost = sum(current_capital x strike); value =
  (current_ft + withdrawn_ft) x FT market price; gain = value - cost, also shown as a percentage. Hidden with no PUTs.
- **Positions**: `/mm/spot/account/positions` per chain: asset, side, leverage, size, entry, mark, unrealized PnL.

## Liquidation alerts

Positions can be liquidated while the health factor is below 1.25. A warning notification fires at or below `hfWarn`,
a critical one at or below `hfCritical`; each fires once per upward crossing with a 0.05 hysteresis and a cooldown per
level, for each wallet separately. Alert state is kept in memory only.

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
