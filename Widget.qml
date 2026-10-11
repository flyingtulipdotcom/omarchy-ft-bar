import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Flying Tulip bar widget: FT market price, 24h application fees, wallet HF
// (lowest across chains with debt), total PnL, total FT earned and ftPUT gain.
// Left click anywhere on the bar widget toggles the info panel (the bar itself opens no links);
// every flyingtulip.com link lives inside the panel. Right click: wallet editor.
// Data: public https://api.flyingtulip.com only. See README.md.
BarWidget {
  id: root
  moduleName: "flyingtulip.ft-bar"

  // ---- settings ---------------------------------------------------------------
  // Durable per-user file first (survives plugin updates, reinstalls and layout rewrites),
  // then the inline shell.json entry, then the default. See README "Where settings live".
  property var saved: ({})
  property bool stateLoaded: false
  function effective(name, fallback) {
    var v = saved[name]
    return v !== undefined && v !== null ? v : setting(name, fallback)
  }
  // Wallets to show (the saved list, plus the single "wallet" of 1.0.x). One is shown at a time: the bar and the
  // panel follow it; every rotateSec the next one is shown, except while one is low (see the rotation timer).
  readonly property var wallets: Model.walletList(effective("wallets", []), effective("wallet", ""))
  property string shown: ""
  readonly property int walletIndex: Math.max(0, wallets.indexOf(shown))
  readonly property string wallet: wallets.length ? wallets[walletIndex] : ""
  readonly property bool walletValid: wallet !== ""
  readonly property int rotateSec: Math.max(10, Number(effective("rotateSec", 60)) || 60)
  // Panel tab, kept in the state file: market | account | positions
  readonly property string tab: ["market", "account", "positions"].indexOf(String(saved.tab)) >= 0 ? String(saved.tab) : (walletValid ? "account" : "market")
  function setTab(t) { if (String(saved.tab) !== t) { writeState({ tab: t }); stat("Tab view", { tab: t }) } }
  readonly property int pollSec: Math.max(15, Number(effective("refreshIntervalSec", 60)) || 60)
  readonly property real hfWarn: Model.parseThreshold(effective("hfWarn", 1.40), 1.40)
  readonly property real hfCritical: Math.min(hfWarn, Model.parseThreshold(effective("hfCritical", 1.30), 1.30))
  readonly property int cooldownMin: Math.max(1, Number(effective("notifyCooldownMin", 30)) || 30)
  readonly property int priceChainId: Number(effective("priceChainId", 1)) === 146 ? 146 : 1
  // Tests set this to stub out notify-send so no real notification is shown.
  readonly property bool notificationsEnabled: setting("notificationsEnabled", true) !== false

  // ---- durable state file ------------------------------------------------------
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/flyingtulip-ft-bar"
  readonly property var persistedKeys: ["wallets", "wallet", "rotateSec", "analytics", "refreshIntervalSec", "hfWarn", "hfCritical", "notifyCooldownMin", "priceChainId"]

  FileView {
    id: stateFile
    path: root.stateDir + "/settings.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var obj = {}
      try { var p = JSON.parse(text()); if (p && typeof p === "object" && !Array.isArray(p)) obj = p } catch (e) {}
      root.saved = obj
      root.stateLoaded = true
      root.migrateEntry()
      if (!root.launchSent) { root.launchSent = true; launchTimer.start() }
    }
    onLoadFailed: { root.saved = ({}); root.stateLoaded = true; root.migrateEntry(); if (!root.launchSent) { root.launchSent = true; launchTimer.start() } }
  }

  // ---- anonymous usage stats (Plausible), see the README "Anonymous usage stats" ----
  // Only the event name, platform, widget version and a few plain values (os, tab, element, url, level, endpoint, a
  // wallet count bucket) leave the machine, by a background curl, fire and forget. Never a wallet address, balance or
  // position. Off ("analytics": false, Advanced in the wallet editor): nothing is sent at all.
  readonly property bool analytics: effective("analytics", true) !== false
  property var statState: ({ hour: -1, counts: {} })
  property var statErrAt: ({})
  property double statPageAt: 0
  property bool launchSent: false
  property string osLabel: ""
  FileView { path: "/etc/os-release"; printErrors: false; onLoaded: root.osLabel = Model.osName(text()); onLoadFailed: root.osLabel = "Linux" }
  function stat(name, props) {
    if (!analytics) return false
    if (!Model.statAllowed(statState, name, Date.now())) return false
    try { Quickshell.execDetached(Model.statArgs(Model.statBody(name, props))) } catch (e) { /* never matters */ }
    return true
  }
  function sendPageview() {
    if (stat("pageview", { os: osLabel || "Linux", host: "Quickshell", walletsConfigured: Model.walletsBucket(wallets.length) }))
      statPageAt = Date.now()
  }
  // the launch pageview a moment after the settings are read, then one a day while the shell runs
  Timer { id: launchTimer; interval: 3000; onTriggered: root.sendPageview() }
  Timer { interval: 3600000; running: true; repeat: true; onTriggered: if (root.launchSent && Date.now() - root.statPageAt >= 86400000) root.sendPageview() }
  // a failed or unusable answer, at most once an hour per endpoint
  function statFetchError(path) {
    var ep = Model.statEndpoint(path)
    if (!ep) return
    var t = Date.now()
    if (t - (statErrAt[ep] || 0) < 3600000) return
    statErrAt[ep] = t
    stat("Fetch error", { endpoint: ep })
  }
  // every element that opens flyingtulip.com: count the click (its element id, the URL without any address), open it
  function openLink(element, url) {
    stat("Link click", { element: element, url: url })
    Qt.openUrlExternally(url)
  }
  function manualNext() { if (wallets.length > 1) { stat("Wallet switch"); nextWallet() } }
  function manualRefresh() { stat("Refresh"); refresh(); refreshSlow(true) }
  function setAnalytics(on) { writeState({ analytics: !!on }) }

  // Merge `patch` into the saved settings and write the file atomically.
  function writeState(patch) {
    var next = {}
    for (var k in saved) next[k] = saved[k]
    for (var p in patch) next[p] = patch[p]
    saved = next
    Quickshell.execDetached(["mkdir", "-p", stateDir])
    writeTimer.restart()
  }
  Timer { id: writeTimer; interval: 150; onTriggered: stateFile.setText(JSON.stringify(root.saved, null, 2) + "\n") }

  // One-time migration: values still only on the shell.json entry are copied into the file.
  function migrateEntry() {
    if (!stateLoaded) return
    var patch = {}, any = false
    for (var i = 0; i < persistedKeys.length; i++) {
      var k = persistedKeys[i]
      if (saved[k] !== undefined) continue
      var v = settings ? settings[k] : undefined
      if (v === undefined || v === null || v === "") continue
      patch[k] = v; any = true
    }
    if (any) writeState(patch)
  }
  onSettingsChanged: migrateEntry()
  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])

  // ---- data (each source keeps its last good value + timestamp) ------------
  property var price: null
  property var fees: null
  property var feesSeries: null
  property var klines: null
  property var chains: []
  property var pnlByChain: ({})
  property var rewards: null
  property var puts: null          // null = no PUTs (or not loaded)
  property var rewardsSeries: null      // cumulative FT earned, all chains
  property string histRange: "30d"       // 7d | 30d | 90d | all
  property string histSeries: "earned"   // earned | claimed
  readonly property var rewardsHist: rewardsSeries ? Model.dailyGains(rewardsSeries, "earned").slice(-30) : null
  property var positions: []
  property bool positionsLoaded: false
  property var points: null
  property var pointsRows: []
  property var rank: null          // {rank,total} or null when not found
  property double pointsAt: 0
  property double rankAt: 0
  property double priceAt: 0
  property double feesAt: 0
  property double accountAt: 0
  property double rewardsAt: 0
  property double putsAt: 0
  property double slowAt: 0
  property double now: Date.now()
  property bool lastRefreshFailed: false
  property var notifyStates: ({})  // wallet -> alert state (once per crossing, per wallet)
  property var watchState: ({})    // hidden wallet -> {chains, at, debt, failAt, busy}: background health check
  property var walletCache: ({})   // wallet -> its account values, swapped back in when it is shown again
  property string lastWallet: ""
  property double shownAt: 0
  property string mode: ""         // "" | "info" | "edit"
  property int generation: 0
  property var notifyLog: []       // last notifications decided (for tests/debug)

  readonly property int staleMs: pollSec * 3000
  function isStale(ts) { return ts === 0 || now - ts > staleMs }

  readonly property var lowest: Model.lowestHf(chains)
  readonly property real totalPnl: {
    var sum = 0, any = false
    for (var k in pnlByChain) { sum += pnlByChain[k]; any = true }
    return any ? sum : NaN
  }
  readonly property int hfLevel: lowest ? Model.levelFor(lowest.hf, { warn: hfWarn, critical: hfCritical }, 0) : 0
  readonly property var putGain: puts && price ? Model.putGain(puts, price.price) : null

  // shell.summon/hide/toggle routing contract (open/close/opened on the widget root)
  readonly property bool opened: mode !== ""
  function open() { openInfo() }
  function close() { mode = "" }
  function openInfo() { mode = "info"; stat("Panel open"); refreshSlow() }
  property string editText: ""
  function openEditor() { editText = ""; editIndex = -1; editError = ""; advancedOpen = false; mode = "edit"; stat("Settings open") }
  property bool advancedOpen: false
  property int editIndex: -1      // -1: the box adds a wallet; otherwise it replaces wallets[editIndex]

  // ---- networking ------------------------------------------------------------
  function getJson(path, ok, failCb) {
    var fail = function () { statFetchError(path); failCb() }
    var xhr = new XMLHttpRequest()
    xhr.timeout = 15000
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status !== 200) { fail(); return }
      var body
      try { body = JSON.parse(xhr.responseText) } catch (e) { fail(); return }
      try { ok(body) } catch (e2) { console.warn("flyingtulip.ft-bar: parse error " + path + ": " + e2); fail() }
    }
    xhr.ontimeout = fail
    xhr.onerror = fail
    xhr.open("GET", Model.API + path)
    xhr.setRequestHeader("Accept", "application/json")
    xhr.send()
  }

  // Chart series change slowly: fetched at most every 10 minutes (and when the panel opens).
  function refreshSlow(force) {
    if (!force && Date.now() - slowAt < 600000) return
    slowAt = Date.now()
    getJson("/fees/application?period=1m&granularity=day", function (b) {
      var s = Model.parseFeesSeries(b); if (s) feesSeries = s
    }, function () { slowAt = 0 })
    getJson("/mm/spot/market/klines?symbol=FT-ftUSD&chainId=" + priceChainId + "&interval=1d&limit=30", function (b) {
      var k = Model.parseKlines(b); if (k) klines = k
    }, function () { slowAt = 0 })
  }

  // Cumulative FT earned over time (all chains) for the selected range.
  function refreshHistory() {
    if (!walletValid) return
    var r = histRange, w = wallet
    getJson("/account/rewards/history?address=" + encodeURIComponent(w) + "&range=" + r, function (b) {
      if (r !== histRange || w !== wallet) return
      var s = Model.parseRewardsSeries(b); if (s) rewardsSeries = s
    }, function () {})
  }
  function setHistRange(r) { histRange = r; rewardsSeries = null; refreshHistory() }

  function refresh() {
    var gen = ++generation
    var failed = false
    function bad() { failed = true; lastRefreshFailed = true }
    function good() { if (!failed) lastRefreshFailed = false }

    getJson("/mm/spot/tickers?chainId=" + priceChainId, function (b) {
      var p = Model.parsePrice(b)
      if (!p && priceChainId !== 146) return getJson("/mm/spot/tickers?chainId=146", function (b2) {
        var p2 = Model.parsePrice(b2); if (p2) { price = p2; priceAt = Date.now() } else bad(); good()
      }, bad)
      if (p) { price = p; priceAt = Date.now(); good() } else bad()
    }, bad)

    getJson("/fees/application?period=1d&granularity=day", function (b) {
      var f = Model.parseFees(b); if (f) { fees = f; feesAt = Date.now(); good() } else bad()
    }, bad)

    refreshSlow()

    if (!walletValid) { chains = []; pnlByChain = ({}); rewards = null; puts = null; return }
    var w = encodeURIComponent(wallet)

    // HF: /mm/lend returns one block per chain; Monad (143) is requested
    // separately and simply absent until the API serves it.
    var lendParts = [], lendDone = 0, lendOk = 0
    function lendPart(list, ok) {
      lendParts.push(list); lendDone++; if (ok) lendOk++
      if (lendDone < 2 || gen !== generation) return
      if (lendOk === 0) return   // main /mm/lend call failed: keep last values (they dim when stale)
      chains = Model.mergeChains(lendParts)
      accountAt = Date.now()
      evaluateAlerts()
      good()
    }
    getJson("/mm/lend?user=" + w, function (b) { lendPart(Model.parseLend(b), true) }, function () { bad(); lendPart([], false) })
    getJson("/mm/lend?user=" + w + "&chainId=143", function (b) { lendPart(Model.parseLend(b), false) }, function () { lendPart([], false) })

    // PnL: unrealizedPnl of /mm/spot/account/summary per chain.
    var pnl = {}, pnlDone = 0, pnlOk = 0, ids = [146, 1, 56, 143]
    for (var i = 0; i < ids.length; i++) (function (id) {
      function fin() {
        pnlDone++
        if (pnlDone < ids.length || gen !== generation) return
        if (pnlOk > 0) { pnlByChain = pnl; accountAt = Date.now() } else bad()
      }
      getJson("/mm/spot/account/summary?address=" + w + "&chainId=" + id, function (b) {
        var s = Model.parseSummary(b)
        if (s) { pnl[id] = s.pnlUsd; pnlOk++ }
        fin()
      }, function () { if (id !== 143) bad(); fin() })   // 143 has no spot indexer yet (404/400)
    })(ids[i])

    getJson("/account/dashboard?address=" + w + "&view=rewards", function (b) {
      if (gen !== generation) return
      var r = Model.parseRewards(b); if (r) { rewards = r; rewardsAt = Date.now(); good() } else bad()
    }, bad)

    // Points: GET /points (all-chains entry) + /points/breakdown; rank via leaderboard search.
    getJson("/points?walletAddress=" + w, function (b) {
      if (gen !== generation) return
      var p = Model.parsePoints(b); if (p) { points = p; pointsAt = Date.now(); good(); refreshRank() } else bad()
    }, bad)
    getJson("/points/breakdown?walletAddress=" + w + "&page=1&limit=50", function (b) {
      if (gen !== generation) return
      pointsRows = Model.parsePointsBreakdown(b)
    }, function () {})

    var posByChain = {}, posDone = 0, posOk = 0, posIds = [146, 1, 56]
    for (var pi = 0; pi < posIds.length; pi++) (function (id) {
      function fin() {
        posDone++
        if (posDone < posIds.length || gen !== generation) return
        if (posOk > 0) {
          var all = []
          for (var k in posByChain) all = all.concat(posByChain[k])
          positions = Model.sortPositions(all); positionsLoaded = true
        }
      }
      getJson("/mm/spot/account/positions?address=" + w + "&chainId=" + id, function (b) {
        posByChain[id] = Model.parsePositions(b); posOk++; fin()
      }, fin)
    })(posIds[pi])

    refreshHistory()

    // ftPUT positions. No positions -> puts = null -> hidden.
    getJson("/tge/ftPUT/user/" + w, function (b) {
      if (gen !== generation) return
      puts = Model.parsePuts(b); putsAt = Date.now(); good()
    }, bad)
  }

  // Leaderboard is sorted by points (500 per page): binary-search the page, then find the wallet.
  function refreshRank() {
    if (!walletValid || !points || (Date.now() - rankAt < 600000 && rank !== null)) return
    rankAt = Date.now()
    var w = wallet, mine = points.total
    var lo = 1, hi = 14, steps = 0
    function probe(page) {
      getJson("/points/leaderboard?page=" + page + "&limit=500", function (b) {
        if (w !== wallet) return
        var r = Model.rankInPage(b, w, mine)
        if (r.found) { rank = { rank: r.rank, total: r.total }; return }
        hi = Math.min(hi, Math.max(1, Math.ceil(r.total / 500)))
        if (r.dir === -1) hi = page - 1
        else if (r.dir === 1) lo = page + 1
        else { rank = null; return }
        if (lo > hi || ++steps > 8) { rank = null; return }
        probe(Math.floor((lo + hi) / 2))
      }, function () { rankAt = 0 })
    }
    probe(Math.floor((lo + hi) / 2))
  }

  // Alerts for one wallet from a fresh /mm/lend read: once per crossing, per wallet, naming the wallet when there are
  // several. A hidden wallet that just turned low is shown at once.
  function alertFor(w, lowestEntry) {
    var prev = notifyStates[w] || { level: 0, last: {} }
    var res = Model.decideNotify(prev, lowestEntry, {
      warn: hfWarn, critical: hfCritical, cooldownMs: cooldownMin * 60000
    }, Date.now())
    var next = {}
    for (var k in notifyStates) next[k] = notifyStates[k]
    next[w] = res.state
    notifyStates = next
    if (res.notify) {
      if (wallets.length > 1) res.notify.wallet = Model.shortAddr(w)
      var t = Model.notifyText(res.notify)
      notifyLog = notifyLog.concat([t.title + " | " + t.body])
      stat("HF alert shown", { level: res.notify.level === 2 ? "danger" : "warning" })
      if (notificationsEnabled)
        Quickshell.execDetached(["notify-send", "-a", "Flying Tulip", "-u", t.urgency, "-i", "dialog-warning", t.title, t.body])
    }
    if (res.state.level > (prev.level || 0) && w !== wallet) showWallet(w)
  }
  function evaluateAlerts() { if (walletValid) alertFor(wallet, lowest) }

  // ---- several wallets ----------------------------------------------------------
  function hasDebt(list) {
    for (var i = 0; list && i < list.length; i++) if (list[i].debtUsd > 0.01) return true
    return false
  }
  // the wallet at or below the warning line (the lowest one when several are), or ""
  function pinnedWallet() {
    var best = "", bestHf = Infinity
    for (var i = 0; i < wallets.length; i++) {
      var w = wallets[i], st = notifyStates[w]
      if (!st || !(st.level >= 1)) continue
      // the shown wallet's own chains; a hidden one's from its last background read, else from when it was shown
      var hidden = (watchState[w] && watchState[w].chains) || (walletCache[w] && walletCache[w].chains) || []
      var lo = Model.lowestHf(w === wallet ? chains : hidden)
      if (lo && lo.hf < bestHf) { best = w; bestHf = lo.hf }
    }
    return best
  }
  function showWallet(w) { if (wallets.indexOf(w) >= 0) { shown = w; shownAt = Date.now(); rotateTimer.restart() } }
  function nextWallet() { if (wallets.length > 1) showWallet(wallets[(walletIndex + 1) % wallets.length]) }

  // Background health check of the hidden wallets: /mm/lend only, every poll while a wallet has debt, every 10 minutes
  // otherwise, and only those (the shown wallet is read in full by refresh()).
  function watchHidden() {
    var t = Date.now()
    for (var i = 0; i < wallets.length; i++) (function (w) {
      if (w === wallet) return
      var s = watchState[w] || {}
      var due = !s.busy && (!s.at || t - s.at >= (s.debt ? pollSec * 1000 : 600000)) && (!s.failAt || t - s.failAt >= 60000)
      if (!due) return
      s.busy = true; watchState[w] = s
      // all chains, and Monad which /mm/lend serves separately (absent until the API has it)
      var parts = [], done = 0, failed = false
      function fin() {
        if (++done < 2) return
        if (failed) { watchState[w] = { chains: s.chains, at: s.at, debt: s.debt, failAt: Date.now(), busy: false }; return }
        var list = Model.mergeChains(parts)
        watchState[w] = { chains: list, at: Date.now(), debt: hasDebt(list), busy: false }
        if (wallets.indexOf(w) >= 0 && w !== wallet) alertFor(w, Model.lowestHf(list))
      }
      getJson("/mm/lend?user=" + encodeURIComponent(w), function (b) { parts.unshift(Model.parseLend(b)); fin() }, function () { failed = true; fin() })
      getJson("/mm/lend?user=" + encodeURIComponent(w) + "&chainId=143", function (b) { parts.push(Model.parseLend(b)); fin() }, fin)
    })(wallets[i])
  }

  // Rotation: the next wallet every rotateSec, except while one is low: that one stays (a manual switch away from it
  // comes back at the next tick).
  Timer {
    id: rotateTimer
    interval: root.rotateSec * 1000
    running: root.wallets.length > 1
    repeat: true
    onTriggered: {
      var pin = root.pinnedWallet()
      if (pin) root.showWallet(pin)
      else root.nextWallet()
    }
  }

  // ---- wallet editor: persisted in the state file (and the shell.json entry as a fallback copy) ---------
  property string editError: ""
  function currentEntry() {
    var e = {}
    var s = settings || {}
    for (var k in s) e[k] = s[k]
    return e
  }
  function saveWallets(list) {
    // Durable file first: this is what survives updates and reinstalls. "wallet" stays the first one for 1.0.x.
    writeState({ wallets: list, wallet: list[0] || "" })
    // Best effort: keep the shell.json entry in sync too (a plain fallback copy).
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function") {
      var entry = currentEntry()
      entry.id = moduleName
      entry.wallets = list
      entry.wallet = list[0] || ""
      bar.shell.updateEntryInline(moduleName, entry)
    }
    editError = ""
    Qt.callLater(refresh)
  }
  // The box adds a wallet (editIndex -1) or replaces the one picked for editing; several addresses can be pasted.
  function saveWallet(raw) {
    var p = Model.parseWallets(raw)
    if (p.bad.length) { editError = "Not a valid address: " + String(p.bad[0]).slice(0, 24) + " (0x + 40 hex characters)"; return false }
    if (!p.list.length) { mode = ""; return true }
    var list = wallets.slice()
    if (editIndex >= 0 && editIndex < list.length) list.splice(editIndex, 1, p.list[0])
    else for (var i = 0; i < p.list.length; i++) if (list.indexOf(p.list[i]) < 0) list.push(p.list[i])
    var dedup = Model.parseWallets(list).list
    if (dedup.some(function (w) { return wallets.indexOf(w) < 0 })) stat("Wallet added")
    if (wallets.some(function (w) { return dedup.indexOf(w) < 0 })) stat("Wallet removed")
    saveWallets(dedup)
    showWallet(editIndex >= 0 ? p.list[0] : p.list[p.list.length - 1])
    editText = ""; editIndex = -1
    return true
  }
  function removeWallet(w) { stat("Wallet removed"); saveWallets(wallets.filter(function (x) { return x !== w })) }
  function editWallet(i) { editIndex = i; editText = wallets[i]; editError = "" }
  property string pendingWallet: ""

  Timer {
    interval: root.pollSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: { root.now = Date.now(); root.refresh(); root.watchHidden() }
  }
  Timer { interval: 20000; running: true; repeat: true; onTriggered: root.now = Date.now() }
  // the values that belong to one wallet: parked when it is hidden, brought back when it is shown again
  readonly property var walletProps: ["chains", "pnlByChain", "rewards", "puts", "positions", "positionsLoaded", "points",
    "pointsRows", "rank", "pointsAt", "rankAt", "accountAt", "rewardsAt", "putsAt", "rewardsSeries"]
  onWalletChanged: {
    generation++                                    // late answers for the previous wallet are dropped
    if (lastWallet !== "") {
      var c = {}
      for (var i = 0; i < walletProps.length; i++) c[walletProps[i]] = root[walletProps[i]]
      var wc = {}
      for (var k in walletCache) wc[k] = walletCache[k]
      wc[lastWallet] = c
      walletCache = wc
    }
    var back = walletCache[wallet]
    if (back) { for (var j = 0; j < walletProps.length; j++) root[walletProps[j]] = back[walletProps[j]] }
    else {
      points = null; pointsRows = []; rank = null; pointsAt = 0; rankAt = 0
      chains = []; pnlByChain = ({}); rewards = null; puts = null
      rewardsSeries = null
      positions = []; positionsLoaded = false
      accountAt = 0; rewardsAt = 0; putsAt = 0
    }
    lastWallet = wallet
    Qt.callLater(refresh)
  }
  onWalletsChanged: {
    // forget the values and alert state of wallets that were removed
    var wc = {}, ns = {}, ws = {}
    for (var i = 0; i < wallets.length; i++) {
      var w = wallets[i]
      if (walletCache[w]) wc[w] = walletCache[w]
      if (notifyStates[w]) ns[w] = notifyStates[w]
      if (watchState[w]) ws[w] = watchState[w]
    }
    walletCache = wc; notifyStates = ns; watchState = ws
    Qt.callLater(watchHidden)
  }
  onPriceChainIdChanged: { slowAt = 0; Qt.callLater(refresh) }

  // ---- Flying Tulip palette ----------------------
  readonly property color cBg: "#0e0e11"
  readonly property color cBorder: Qt.rgba(76 / 255, 76 / 255, 82 / 255, 0.5)
  readonly property color cText: "#e4e4e7"
  readonly property color cSub: "#a1a1aa"
  readonly property color cFaint: "#71717a"
  readonly property color cTulip: "#7559ff"
  readonly property color cTulip300: "#b7b1ff"
  readonly property color cTulip400: "#9385ff"
  readonly property color cGreen: "#0fd727"
  readonly property color cRed: "#ef4444"
  readonly property color cAmber: "#f5a524"
  readonly property string nerdFont: bar ? bar.fontFamily : "monospace"
  function deltaColor(v) { return !isFinite(v) || Math.abs(v) < 0.005 ? cSub : (v > 0 ? cGreen : cRed) }
  // Open a public flyingtulip.com page in the default browser; the panel closes after.
  function openUrl(url, element) { stat("Link click", { element: element || "panel", url: url }); Qt.openUrlExternally(url); if (mode === "info") close() }
  readonly property string marketLink: Model.marketUrl("FT-ftUSD", priceChainId)
  function lastUpdate() { return Math.max(priceAt, feesAt, accountAt) }
  function ago(ts) {
    if (ts === 0) return "never"
    var s = Math.max(0, Math.round((now - ts) / 1000))
    return s < 90 ? s + "s ago" : Math.round(s / 60) + "m ago"
  }

  // ---- bar presentation -----------------------------------------------------
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color hfColor: !lowest ? fg : (hfLevel === 2 ? cRed : (hfLevel === 1 ? cAmber : cGreen))
  readonly property bool showPut: walletValid && putGain !== null
  readonly property string fam: "Noto Sans"

  implicitWidth: pill.width
  implicitHeight: barSize

  // One segment: faint tulip label + value.
  component Seg: Row {
    property string label: ""
    property string value: ""
    property color valueColor: root.fg
    property bool dim: false
    spacing: 4
    opacity: dim ? 0.5 : 1
    Behavior on opacity { NumberAnimation { duration: 200 } }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.label
      visible: parent.label !== ""
      color: root.cTulip400
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.value
      color: parent.valueColor
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }

  Rectangle {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(18, root.barSize - 8)
    width: row.implicitWidth + 16
    radius: height / 2
    color: root.mode !== "" ? Qt.rgba(117 / 255, 89 / 255, 255, 0.22) : (hoverArea.containsMouse ? Qt.rgba(117 / 255, 89 / 255, 255, 0.14) : "transparent")
    border.width: root.mode !== "" || hoverArea.containsMouse ? 1 : 0
    border.color: Qt.rgba(117 / 255, 89 / 255, 255, 0.45)
    Behavior on color { ColorAnimation { duration: 140 } }

    Grid {
      id: row
      anchors.centerIn: parent
      flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
      rows: root.vertical ? 10 : 1
      columns: root.vertical ? 1 : 10
      spacing: Style.space(10)

      Item {
        width: Style.bar.iconCanvas
        height: Style.font.body + 4
        TulipGlyph { anchors.centerIn: parent; size: Style.bar.iconCanvas; color: root.cTulip }
      }
      Seg { label: ""; value: Model.fmtPrice(root.price ? root.price.price : NaN); dim: root.isStale(root.priceAt) }
      Seg { label: "fees"; value: Model.fmtUsd(root.fees ? root.fees.period24h : NaN); dim: root.isStale(root.feesAt) }
      Seg {
        visible: !root.walletValid
        label: ""
        value: "set wallet"
        valueColor: root.cAmber
      }
      Seg { visible: root.walletValid; label: "HF"; value: root.accountAt === 0 ? "—" : (root.lowest ? Model.fmtHf(root.lowest.hf) : "∞"); valueColor: root.hfColor; dim: root.isStale(root.accountAt) }
      Seg { visible: root.walletValid; label: "PnL"; value: Model.fmtSignedUsd(root.totalPnl); valueColor: root.deltaColor(root.totalPnl); dim: root.isStale(root.accountAt) }
      Seg { visible: root.walletValid; label: "FT earned"; value: Model.fmtFt(root.rewards ? root.rewards.totalFt : NaN); dim: root.isStale(root.rewardsAt) }
      Seg { visible: root.walletValid; label: "pts"; value: Model.fmtPoints(root.points ? root.points.total : NaN); dim: root.isStale(root.pointsAt) }
      Seg { visible: root.showPut; label: "PUT"; value: root.putGain ? Model.fmtPct(root.putGain.gainPct) : "—"; valueColor: root.putGain ? root.deltaColor(root.putGain.gainUsd) : root.fg; dim: root.isStale(root.putsAt) || root.isStale(root.priceAt) }
      // several wallets: which one the bar shows, then the switch icon (a click on it shows the next wallet)
      Seg { visible: root.wallets.length > 1; label: ""; value: Model.shortAddr(root.wallet); valueColor: root.cSub }
      Item {
        id: switchIcon
        visible: root.wallets.length > 1
        width: switchText.implicitWidth + 6
        height: Style.font.body + 4
        Text {
          id: switchText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "⇄"
          color: root.switchHovered ? "white" : root.cTulip300
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body + 2
          font.bold: true
        }
      }
    }
  }

  // The switch icon sits inside the bar widget, under the one MouseArea that takes every click: hit-test it here.
  property bool switchHovered: false
  function overSwitch(x, y) {
    if (!switchIcon.visible) return false
    var p = switchIcon.mapToItem(hoverArea, 0, 0)
    return x >= p.x - 3 && x <= p.x + switchIcon.width + 3 && y >= p.y - 4 && y <= p.y + switchIcon.height + 4
  }
  // Left click: info panel (on the switch icon: the next wallet). Right click: wallet editor. Middle click: refresh.
  MouseArea {
    id: hoverArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onPositionChanged: function (m) { root.switchHovered = root.overSwitch(m.x, m.y) }
    onExited: root.switchHovered = false
    onClicked: function (m) {
      if (m.button === Qt.LeftButton && root.overSwitch(m.x, m.y)) { root.manualNext(); return }
      if (m.button === Qt.RightButton) root.mode === "edit" ? root.close() : root.openEditor()
      else if (m.button === Qt.MiddleButton) root.manualRefresh()
      else if (!root.walletValid && root.mode === "") root.openInfo()
      else root.mode === "info" ? root.close() : root.openInfo()
    }
  }

  // ---- info panel ------------------------------------------------------------
  KeyboardPanel {
    id: infoPanel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.mode === "info"
    centerOnBar: true
    padding: 0
    focusTarget: infoKeys
    contentWidth: infoPanel.fittedContentWidth(Style.space(400))
    contentHeight: infoPanel.fittedContentHeight(info.implicitHeight, Style.space(820))

    Rectangle {
      anchors.fill: parent
      color: root.cBg
      radius: Style.cornerRadius
      clip: true

      PanelKeyCatcher {
        id: infoKeys
        anchors.fill: parent
        onCloseRequested: root.close()

        Flickable {
          anchors.fill: parent
          contentWidth: width
          contentHeight: info.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          Info { id: info; width: parent.width; h: root }
        }
      }
    }
  }

  // ---- wallet editor: the wallet list (show, edit, remove) and a box to add one ------------------------------------
  KeyboardPanel {
    id: editPanel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.mode === "edit"
    centerOnBar: true
    padding: 0
    focusTarget: editInput
    contentWidth: editPanel.fittedContentWidth(Style.space(440))
    contentHeight: editPanel.fittedContentHeight(editCol.implicitHeight + 32)

    Rectangle {
      anchors.fill: parent
      color: root.cBg
      radius: Style.cornerRadius
      opacity: root.mode === "edit" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 180 } }

      Column {
        id: editCol
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 10

        Row {
          spacing: 9
          Rectangle {
            width: 30; height: 30; radius: 9; color: "#0c091a"
            border.width: 1; border.color: Qt.rgba(117 / 255, 89 / 255, 255, 0.4)
            TulipGlyph { anchors.centerIn: parent; size: 20; color: root.cTulip }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { textFormat: Text.PlainText; text: "Wallets"; color: root.cText; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { textFormat: Text.PlainText; text: "Public addresses only. With several, the bar shows them in turn."; color: root.cFaint; font.family: root.fam; font.pixelSize: 10 }
          }
        }

        // the list: click an address to show it, the pencil to edit it, the cross to remove it
        Repeater {
          model: root.wallets
          Rectangle {
            width: editCol.width
            height: 30
            radius: 8
            color: modelData === root.wallet ? Qt.rgba(117 / 255, 89 / 255, 255, 0.14) : Qt.rgba(1, 1, 1, 0.03)
            Text {
              x: 10; anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: (modelData === root.wallet ? "● " : "○ ") + modelData.slice(0, 10) + "…" + modelData.slice(-8) + (root.editIndex === index ? "  editing" : "")
              color: modelData === root.wallet ? root.cTulip300 : root.cSub
              font.family: root.nerdFont
              font.pixelSize: 12
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showWallet(modelData) }
            }
            Row {
              anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
              spacing: 4
              Rectangle {
                width: 24; height: 22; radius: 6; color: penMa.containsMouse ? Qt.rgba(117 / 255, 89 / 255, 255, 0.2) : "transparent"
                Text { anchors.centerIn: parent; text: "✎"; color: root.cSub; font.pixelSize: 12 }
                MouseArea { id: penMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.editWallet(index) }
              }
              Rectangle {
                width: 24; height: 22; radius: 6; color: delMa.containsMouse ? Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.2) : "transparent"
                Text { anchors.centerIn: parent; text: "✕"; color: delMa.containsMouse ? root.cRed : root.cSub; font.pixelSize: 11 }
                MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.removeWallet(modelData) }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 38
          radius: 10
          color: Qt.rgba(24 / 255, 24 / 255, 27 / 255, 0.65)
          border.width: 1
          border.color: root.editError !== "" ? root.cRed : (editInput.activeFocus ? root.cTulip : root.cBorder)
          Behavior on border.color { ColorAnimation { duration: 120 } }
          TextInput {
            id: editInput
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            color: root.cText
            selectionColor: root.cTulip
            font.family: root.fam
            font.pixelSize: 12
            clip: true
            text: root.editText
            onTextChanged: { root.editText = text; root.editError = "" }
            Keys.onPressed: function (event) {
              if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.saveWallet(editInput.text); event.accepted = true }
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 12
            visible: editInput.text === ""
            textFormat: Text.PlainText
            text: root.editIndex >= 0 ? "0x… the new address for this wallet" : "0x… paste an address to add"
            color: root.cFaint
            font.family: root.fam
            font.pixelSize: 12
          }
        }
        Text {
          width: parent.width
          visible: root.editError !== ""
          textFormat: Text.PlainText
          text: root.editError
          color: root.cRed
          wrapMode: Text.WordWrap
          font.family: root.fam
          font.pixelSize: 11
        }
        Row {
          spacing: 8
          layoutDirection: Qt.LeftToRight
          Rectangle {
            width: 84; height: 32; radius: 9
            color: saveMa.containsMouse ? root.cTulip400 : root.cTulip
            Behavior on color { ColorAnimation { duration: 120 } }
            Text { anchors.centerIn: parent; text: root.editIndex >= 0 ? "Save" : "Add"; color: "white"; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
            MouseArea { id: saveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.saveWallet(editInput.text) }
          }
          Rectangle {
            width: 84; height: 32; radius: 9; color: "transparent"
            border.width: 1; border.color: cancelMa.containsMouse ? root.cTulip : root.cBorder
            Behavior on border.color { ColorAnimation { duration: 120 } }
            Text { anchors.centerIn: parent; text: "Done"; color: root.cSub; font.family: root.fam; font.pixelSize: 12 }
            MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.editIndex = -1; root.close() } }
          }
        }

        // Advanced settings, folded away
        Rectangle { width: parent.width; height: 1; color: root.cBorder }
        Text {
          textFormat: Text.PlainText
          text: (root.advancedOpen ? "▾ " : "▸ ") + "Advanced settings"
          color: advMa.containsMouse ? root.cTulip300 : root.cSub
          font.family: root.fam; font.pixelSize: 11
          MouseArea { id: advMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.advancedOpen = !root.advancedOpen }
        }
        Row {
          visible: root.advancedOpen
          spacing: 10
          Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: "Anonymous usage stats"; color: root.cText; font.family: root.fam; font.pixelSize: 12 }
          Rectangle {
            width: 52; height: 24; radius: 12
            anchors.verticalCenter: parent.verticalCenter
            color: root.analytics ? Qt.rgba(117 / 255, 89 / 255, 255, 0.35) : "transparent"
            border.width: 1; border.color: root.analytics ? root.cTulip : root.cBorder
            Text { anchors.centerIn: parent; text: root.analytics ? "On" : "Off"; color: root.analytics ? root.cTulip300 : root.cSub; font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setAnalytics(!root.analytics) }
          }
        }
        Text {
          visible: root.advancedOpen
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Counts launches, panel opens, tabs and links used, with the platform and version. Never a wallet, balance or position."
          color: root.cFaint; font.family: root.fam; font.pixelSize: 10
        }
      }
    }
  }
}
