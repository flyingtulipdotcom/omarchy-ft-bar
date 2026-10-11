// bun test.js  (live: WALLET=0x... bun test.js)
const M = require("./Model.js")
const assert = require("assert")
const cfg = { warn: 1.4, critical: 1.3, cooldownMs: 30 * 60e3 }
const e = hf => ({ hf, name: "Sonic", liqHf: 1.25 })
let st = { level: 0, last: {} }, r
r = M.decideNotify(st, e(2), cfg, 0); assert(!r.notify); st = r.state
r = M.decideNotify(st, e(1.39), cfg, 1e3); assert(r.notify && r.notify.level === 1); st = r.state
r = M.decideNotify(st, e(1.38), cfg, 2e3); assert(!r.notify)                     // same level: once
r = M.decideNotify(st, e(1.29), cfg, 3e3); assert(r.notify && r.notify.level === 2); st = r.state
r = M.decideNotify(st, e(1.33), cfg, 4e3); assert(!r.notify && r.state.level === 2) // hysteresis holds crit
st = r.state
r = M.decideNotify(st, e(1.6), cfg, 5e3); assert(!r.notify && r.state.level === 0); st = r.state
r = M.decideNotify(st, e(1.39), cfg, 6e3); assert(!r.notify)                      // re-cross inside cooldown
r = M.decideNotify(r.state, null, cfg, 7e3); assert(r.state.level === 0)
assert.equal(M.fmtHf(null), "∞"); assert.equal(M.fmtUsd(1152.98), "$1.15k"); assert.equal(M.fmtSignedUsd(-5), "-$5.00")
console.log("unit ok")
const W = process.env.WALLET
if (W) (async () => {
  const j = u => fetch("https://api.flyingtulip.com" + u).then(r => r.json())
  console.log(M.parseFees(await j("/fees/application?period=1d&granularity=day")))
  console.log(M.parsePrice(await j("/mm/spot/tickers?chainId=1")))
  const ch = M.mergeChains([M.parseLend(await j("/mm/lend?user=" + W)), M.parseLend(await j("/mm/lend?user=" + W + "&chainId=143"))])
  console.log(ch.map(c => [c.name, c.hf, c.debtUsd, c.liqHf]), M.lowestHf(ch))
  for (const c of [146, 1, 56]) console.log(M.parseSummary(await j(`/mm/spot/account/summary?address=${W}&chainId=${c}`)))
})()

// ---- ftPUT / wallet
const put = { data: { positions: [
  { nft_id: "1", token_symbol: "USDT", token_decimals: 6, chain_id: 1, strike: "99960146", current_capital: "1000000000", current_ft: "9996014600000000000000", withdrawn_ft: "0", created_at: "2026-01-18T16:25:40Z" },
  { nft_id: "5000", token_symbol: "WETH", token_decimals: 18, chain_id: 1, strike: "204858535229", current_capital: "76118530000000000000", current_ft: "1459353055958469337000000", withdrawn_ft: "100000000000000000000000", created_at: "2026-02-14" } ] } }
const pp = M.parsePuts(put)
assert.equal(pp.count, 2); assert(Math.abs(pp.costUsd - (999.60146 + 76.11853 * 2048.58535229)) < 1e-3)
assert(Math.abs(pp.ftHeld - (9996.0146 + 1559353.055958469)) < 1e-3)
const g = M.putGain(pp, 0.15); assert(Math.abs(g.gainUsd - (pp.ftHeld * 0.15 - pp.costUsd)) < 1e-6)
assert.equal(M.parsePuts({ data: { positions: null } }), null)
assert.equal(M.normalizeWallet(" 0x000000000000000000000000000000000000dEaD "), "0x000000000000000000000000000000000000dead")
assert.equal(M.normalizeWallet("0x123"), ""); assert.equal(M.normalizeWallet("000000000000000000000000000000000000dEaD"), "")
assert.equal(M.fmtPct(-3.456), "-3.5%")
console.log("put/wallet ok", g)
assert.equal(M.parseFeesSeries({ data: { series: [{ date: "2026-10-01", total_usd: "12.5" }] } })[0].total, 12.5)
assert.equal(M.parseKlines([{ time: 1791417600000, close: "0.14" }])[0].date, "2026-10-08")
assert.equal(M.parseKlines({}), null)
console.log("series ok")
const pts = M.parsePoints({ data: { chains: [{ isAllChains: false, userMetrics: { totalPoints: 1 } }, { isAllChains: true, userMetrics: { totalPoints: 1234567.5, claimedPoints: 0, unclaimedPoints: 1234567.5 } }] } })
assert.equal(Math.round(pts.total), 1234568); assert.equal(M.fmtPoints(30153181), "30.2M"); assert.equal(M.fmtPoints(NaN), "—")
const lb = { data: { pagination: { total: 99 }, leaderboard: [{ userWallet: "0xAA", rank: 5, totalPoints: 90 }, { userWallet: "0xBB", rank: 6, totalPoints: 80 }] } }
assert.equal(M.rankInPage(lb, "0xbb", 80).rank, 6); assert.equal(M.rankInPage(lb, "0xcc", 95).dir, -1); assert.equal(M.rankInPage(lb, "0xcc", 10).dir, 1)
assert.equal(M.parsePointsBreakdown({ data: { pointsBreakdown: [{ productLabel: "Lend", activityLabel: "Borrow", positionUsd: 5, multiplier: 1 }] } })[0].label, "Lend Borrow")
console.log("points ok")
const D = 86400, base = 1790000000 - (1790000000 % D)
const rh = M.parseRewardsHistory({ data: { points: [0, 1, 2, 3].map(i => ({ timestampUnixSeconds: base + i * D + D - 1, totalEarnedFtRaw: String(BigInt(100 + i * 10) * 10n ** 18n) })) } }, base + 10 * D)
assert.equal(rh.length, 3); assert.equal(Math.round(rh[0].gain), 10)
assert.equal(M.parseRewardsHistory({ data: { points: [] } }), null)
console.log("rewards history ok")
const pr = M.parsePositions([{ positionId: "x", chainId: 146, network: "Sonic", symbol: "wS-ftUSD", sizeCurrency: "wS", side: "long", size: "1007088.24", entryPrice: "0.0393", markPrice: "0.0450", pnlAmount: "5780.1", pnlPct: "120.3", blendedLeverage: "9.44" }, { size: "0", symbol: "A-B" }])
assert.equal(pr.length, 1); assert.equal(pr[0].side, "long"); assert.equal(M.fmtSize(pr[0].size), "1.01M"); assert(Math.abs(pr[0].valueUsd - 1007088.24 * 0.045) < 1)
assert.deepEqual(M.parsePositions({}), [])
console.log("positions ok")
const rs = M.parseRewardsSeries({ data: { points: [0, 1, 2, 3].map(i => ({ timestampUnixSeconds: base + i * D + D - 1, totalEarnedFtRaw: String(BigInt(100 + i * 10) * 10n ** 18n), claimedFtRaw: "0" })) } }, base + 10 * D)
assert.equal(rs.length, 4); assert.equal(Math.round(rs[3].earned), 130)
const dg = M.dailyGains(rs, "earned"); assert.equal(dg.length, 3); assert.equal(Math.round(dg[1].gain), 10)
assert.equal(M.parseRewardsSeries({ data: { points: [] } }), null)
console.log("rewards series ok")

// ---- page links: every element opens a real flyingtulip.com page
assert.equal(M.marketUrl("FT-ftUSD", 1), "https://flyingtulip.com/trade/?symbol=FT-ftUSD&chainId=1&marketType=spot")
assert.equal(M.marketUrl("wS-ftUSD", 146), "https://flyingtulip.com/trade/?symbol=wS-ftUSD&chainId=146&marketType=spot")
assert.equal(M.marketUrl("", NaN), "https://flyingtulip.com/trade/?symbol=FT-ftUSD&marketType=spot")
for (const k in M.PAGES) assert(/^https:\/\/flyingtulip\.com\/([a-z-]+\/)*$/.test(M.PAGES[k]), k)
console.log("links ok")

// ---- FT earned breakdown and points per chain (two real wallet shapes, addresses removed)
// The smaller wallet claimed sftUSD yield months ago; the larger one only supplies Lend and earns
// small rewards whose raw amounts have 16 to 17 digits (0.001 to 0.1 FT), which the old rawFt
// read as trillions of FT.
assert(Math.abs(M.rawUnits("60167126473248989", 18) - 0.060167126473248989) < 1e-15)
assert(Math.abs(M.rawUnits("3646974199494715", 18) - 0.003646974199494715) < 1e-15)
const SMALL = { success: true, data: { chains: [
  { chainId: 1, staking: { pending_yield_ft: "0", claimed_yield_ft: "0", claimed_yield_indexed_through_block: 26165977 }, lend: { userMetrics: { ftRewards: null, ftRewardsError: null } } },
  { chainId: 146, staking: { pending_yield_ft: "0", claimed_yield_ft: "95386787178560501045", claimed_yield_indexed_through_block: 80722469 }, lend: { userMetrics: { ftRewards: null } } }] } }
const LARGE = { success: true, data: { chains: [
  { chainId: 1, staking: { pending_yield_ft: "0", claimed_yield_ft: "0", claimed_yield_indexed_through_block: 26165977 }, lend: { userMetrics: { ftRewards: { receivedFtRaw: "0", pendingFtRaw: "60167126473248989" } } } },
  { chainId: 146, staking: { pending_yield_ft: "0", claimed_yield_ft: "0", claimed_yield_indexed_through_block: 80722469 }, lend: { userMetrics: { ftRewards: { receivedFtRaw: "743020047575476813", pendingFtRaw: "59654073282058744" } } } }] } }
const rs1 = M.parseRewards(SMALL), rl = M.parseRewards(LARGE)
assert(Math.abs(rs1.totalFt - 95.386787178560501) < 1e-9 && rs1.lendFt === 0)
assert(Math.abs(rl.totalFt - 0.862841247331) < 1e-9, rl.totalFt); assert.equal(M.fmtFt(rl.totalFt), "0.86")
assert.equal(M.earnedByChain(rs1), "Sonic 95.4"); assert.equal(M.earnedByChain(rl), "Ethereum 0.06, Sonic 0.80")
assert(isNaN(M.parseRewards({ success: true, data: { sectionErrors: { lend: "x" }, chains: [{ chainId: 146 }] } }).totalFt))
const pts2 = M.parsePoints({ data: { chains: [
  { chainData: { id: 146, name: "Sonic" }, isAllChains: false, userMetrics: { totalPoints: 45757.02690673988 } },
  { chainData: { id: 1, name: "Ethereum" }, isAllChains: false, userMetrics: { totalPoints: 616132.7877936237 } },
  { chainData: null, isAllChains: true, userMetrics: { totalPoints: 661889.8147003637 } }] } })
assert.deepEqual(pts2.chains.map(c => c.name + " " + M.fmtPoints(c.points)), ["Ethereum 616K", "Sonic 45.8K"])
console.log("earned breakdown / points per chain ok")
