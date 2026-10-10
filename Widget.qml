import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Flying Tulip bar widget: FT market price, 24h application fees, wallet HF
// (lowest across chains with debt), total PnL, total FT earned and ftPUT gain.
// Left click on a segment opens its page on flyingtulip.com; the logo (or the pill
// padding) toggles the info panel with charts. Right click: wallet editor.
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
  readonly property string wallet: String(effective("wallet", "")).trim()
  readonly property bool walletValid: Model.isAddress(wallet)
  readonly property int pollSec: Math.max(15, Number(effective("refreshIntervalSec", 60)) || 60)
  readonly property real hfWarn: Model.parseThreshold(effective("hfWarn", 1.40), 1.40)
  readonly property real hfCritical: Math.min(hfWarn, Model.parseThreshold(effective("hfCritical", 1.30), 1.30))
  readonly property int cooldownMin: Math.max(1, Number(effective("notifyCooldownMin", 30)) || 30)
  readonly property int priceChainId: Number(effective("priceChainId", 1)) === 146 ? 146 : 1
  // Tests set this to stub out notify-send so no real notification is shown.
  readonly property bool notificationsEnabled: setting("notificationsEnabled", true) !== false

  // ---- durable state file ------------------------------------------------------
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/flyingtulip-ft-bar"
  readonly property var persistedKeys: ["wallet", "refreshIntervalSec", "hfWarn", "hfCritical", "notifyCooldownMin", "priceChainId"]

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
    }
    onLoadFailed: { root.saved = ({}); root.stateLoaded = true; root.migrateEntry() }
  }

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
  property var notifyState: ({ level: 0, last: {} })
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
  function openInfo() { mode = "info"; refreshSlow() }
  property string editText: ""
  function openEditor() { editText = wallet; editError = ""; mode = "edit" }

  // ---- networking ------------------------------------------------------------
  function getJson(path, ok, fail) {
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

  function evaluateAlerts() {
    var res = Model.decideNotify(notifyState, lowest, {
      warn: hfWarn, critical: hfCritical, cooldownMs: cooldownMin * 60000
    }, Date.now())
    notifyState = res.state
    if (res.notify) {
      var t = Model.notifyText(res.notify)
      notifyLog = notifyLog.concat([t.title + " | " + t.body])
      if (notificationsEnabled)
        Quickshell.execDetached(["notify-send", "-a", "Flying Tulip", "-u", t.urgency, "-i", "dialog-warning", t.title, t.body])
    }
  }

  // ---- wallet editor: persisted through Omarchy's own settings writer ---------
  property string editError: ""
  function currentEntry() {
    var e = {}
    var s = settings || {}
    for (var k in s) e[k] = s[k]
    return e
  }
  function saveWallet(raw) {
    var text = String(raw || "").trim()
    var next = ""
    if (text !== "") {
      next = Model.normalizeWallet(text)
      if (next === "") { editError = "Not a valid address (0x + 40 hex characters)"; return false }
    }
    // Durable file first: this is what survives updates and reinstalls.
    writeState({ wallet: next })
    // Best effort: keep the shell.json entry in sync too (a plain fallback copy).
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function") {
      var entry = currentEntry()
      entry.id = moduleName
      entry.wallet = next
      bar.shell.updateEntryInline(moduleName, entry)
    }
    editError = ""
    mode = ""
    // The shell reloads settings; refresh right away without waiting for that.
    pendingWallet = next
    Qt.callLater(refresh)
    return true
  }
  property string pendingWallet: ""

  Timer {
    interval: root.pollSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: { root.now = Date.now(); root.refresh() }
  }
  Timer { interval: 20000; running: true; repeat: true; onTriggered: root.now = Date.now() }
  onWalletChanged: {
    points = null; pointsRows = []; rank = null; pointsAt = 0; rankAt = 0
    notifyState = ({ level: 0, last: {} }); chains = []; pnlByChain = ({}); rewards = null; puts = null
    rewardsSeries = null
    positions = []; positionsLoaded = false
    accountAt = 0; rewardsAt = 0; putsAt = 0
    Qt.callLater(refresh)
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
  function openUrl(url) { Qt.openUrlExternally(url); if (mode === "info") close() }
  readonly property string marketLink: Model.marketUrl("FT-ftUSD", priceChainId)
  function openStats() { openUrl(Model.PAGES.fees) }
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

  // One segment: faint tulip label + value. Left click opens `url`; right click is the
  // wallet editor and middle click a refresh, as on the rest of the pill.
  component Seg: Item {
    id: seg
    property string label: ""
    property string value: ""
    property color valueColor: root.fg
    property bool dim: false
    property string url: Model.SITE
    implicitWidth: segRow.implicitWidth
    implicitHeight: segRow.implicitHeight
    Row {
      id: segRow
      spacing: 4
      opacity: seg.dim ? 0.5 : (segMa.containsMouse ? 1 : 0.92)
      Behavior on opacity { NumberAnimation { duration: 200 } }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: seg.label
        visible: seg.label !== ""
        color: segMa.containsMouse ? root.cTulip300 : root.cTulip400
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: seg.value
        color: seg.valueColor
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        font.underline: segMa.containsMouse
      }
    }
    MouseArea {
      id: segMa
      anchors.fill: parent
      anchors.margins: -3
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true
      onClicked: function (m) {
        if (m.button === Qt.RightButton) root.mode === "edit" ? root.close() : root.openEditor()
        else if (m.button === Qt.MiddleButton) root.refresh()
        else Qt.openUrlExternally(seg.url)
      }
    }
  }

  Rectangle {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(18, root.barSize - 8)
    width: row.implicitWidth + 16
    radius: height / 2
    color: root.mode !== "" ? Qt.rgba(117 / 255, 89 / 255, 255, 0.22) : (pillHover.hovered ? Qt.rgba(117 / 255, 89 / 255, 255, 0.14) : "transparent")
    border.width: root.mode !== "" || pillHover.hovered ? 1 : 0
    border.color: Qt.rgba(117 / 255, 89 / 255, 255, 0.45)
    Behavior on color { ColorAnimation { duration: 140 } }
    HoverHandler { id: pillHover }

    Grid {
      id: row
      anchors.centerIn: parent
      flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
      rows: root.vertical ? 8 : 1
      columns: root.vertical ? 1 : 8
      spacing: Style.space(10)

      // The logo toggles the info panel (the pill padding does too, see pillArea).
      Item {
        width: Style.bar.iconCanvas
        height: Style.font.body + 4
        TulipGlyph { anchors.centerIn: parent; size: Style.bar.iconCanvas; color: root.cTulip }
        MouseArea {
          anchors.fill: parent
          anchors.margins: -3
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function (m) {
            if (m.button === Qt.RightButton) root.mode === "edit" ? root.close() : root.openEditor()
            else if (m.button === Qt.MiddleButton) root.refresh()
            else root.mode === "info" ? root.close() : root.openInfo()
          }
        }
      }
      Seg { url: root.marketLink; label: ""; value: Model.fmtPrice(root.price ? root.price.price : NaN); dim: root.isStale(root.priceAt) }
      Seg { url: Model.PAGES.fees; label: "fees"; value: Model.fmtUsd(root.fees ? root.fees.period24h : NaN); dim: root.isStale(root.feesAt) }
      Item {
        visible: !root.walletValid
        implicitWidth: setSeg.implicitWidth
        implicitHeight: setSeg.implicitHeight
        // Not a site page: opens the wallet editor.
        Seg { id: setSeg; label: ""; value: "set wallet"; valueColor: root.cAmber; url: "" }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton; onClicked: root.openEditor() }
      }
      Seg { url: Model.PAGES.health; visible: root.walletValid; label: "HF"; value: root.accountAt === 0 ? "—" : (root.lowest ? Model.fmtHf(root.lowest.hf) : "∞"); valueColor: root.hfColor; dim: root.isStale(root.accountAt) }
      Seg { url: Model.PAGES.portfolio; visible: root.walletValid; label: "PnL"; value: Model.fmtSignedUsd(root.totalPnl); valueColor: root.deltaColor(root.totalPnl); dim: root.isStale(root.accountAt) }
      Seg { url: Model.PAGES.rewards; visible: root.walletValid; label: "FT earned"; value: Model.fmtFt(root.rewards ? root.rewards.totalFt : NaN); dim: root.isStale(root.rewardsAt) }
      Seg { url: Model.PAGES.points; visible: root.walletValid; label: "pts"; value: Model.fmtPoints(root.points ? root.points.total : NaN); dim: root.isStale(root.pointsAt) }
      Seg { url: Model.PAGES.put; visible: root.showPut; label: "PUT"; value: root.putGain ? Model.fmtPct(root.putGain.gainPct) : "—"; valueColor: root.putGain ? root.deltaColor(root.putGain.gainUsd) : root.fg; dim: root.isStale(root.putsAt) || root.isStale(root.priceAt) }
    }
  }

  // Pill padding and gaps (the segments and logo handle their own clicks, drawn above
  // this): left click toggles the info panel. Right click: wallet editor. Middle: refresh.
  MouseArea {
    id: pillArea
    anchors.fill: parent
    z: -1
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function (m) {
      if (m.button === Qt.RightButton) root.mode === "edit" ? root.close() : root.openEditor()
      else if (m.button === Qt.MiddleButton) root.refresh()
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

  // ---- wallet editor -----------------------------------------------------------
  KeyboardPanel {
    id: editPanel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.mode === "edit"
    centerOnBar: true
    padding: 0
    focusTarget: editInput
    contentWidth: editPanel.fittedContentWidth(Style.space(420))
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
            Text { textFormat: Text.PlainText; text: "Wallet address"; color: root.cText; font.family: root.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { textFormat: Text.PlainText; text: "Public address only. Saved to your Omarchy config."; color: root.cFaint; font.family: root.fam; font.pixelSize: 10 }
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
            text: "0x… paste an address (empty clears it)"
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
            Text { anchors.centerIn: parent; text: "Save"; color: "white"; font.family: root.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
            MouseArea { id: saveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.saveWallet(editInput.text) }
          }
          Rectangle {
            width: 84; height: 32; radius: 9; color: "transparent"
            border.width: 1; border.color: clearMa.containsMouse ? root.cRed : root.cBorder
            Behavior on border.color { ColorAnimation { duration: 120 } }
            Text { anchors.centerIn: parent; text: "Clear"; color: root.cSub; font.family: root.fam; font.pixelSize: 12 }
            MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.saveWallet("") }
          }
          Rectangle {
            width: 84; height: 32; radius: 9; color: "transparent"
            border.width: 1; border.color: cancelMa.containsMouse ? root.cTulip : root.cBorder
            Behavior on border.color { ColorAnimation { duration: 120 } }
            Text { anchors.centerIn: parent; text: "Cancel"; color: root.cSub; font.family: root.fam; font.pixelSize: 12 }
            MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
          }
        }
      }
    }
  }
}
