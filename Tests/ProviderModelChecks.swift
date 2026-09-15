enum L10n { static let isEnglish = true }
@main struct Checks {
 @MainActor static func main() async {
  let suite = "TokenDeck.Test." + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let prefs = ProductPreferences(defaults: defaults)
  assert(prefs.enabled == ["codex","grok","kimi","openrouter"])
  prefs.selected = "grok"
  prefs.setEnabled(id:"grok",enabled:false)
  assert(prefs.selected == "codex")
  for id in ["kimi","openrouter","codex"] { prefs.setEnabled(id:id,enabled:false) }
  assert(prefs.enabled == ["codex"])
  prefs.setEnabled(id:"deepseek",enabled:true);prefs.selected="deepseek"
  assert(ProductPreferences(defaults:defaults).selected == "deepseek")
  let fixture = #"[{"provider":"grok","account":"first","usage":{"primary":{"usedPercent":41,"windowMinutes":300,"resetsAt":"2026-09-16T12:00:00.123Z"}}},{"provider":"grok","account":"second","usage":{"primary":{"usedPercent":80}}}]"#
  let rows=ProviderCLI.decodeRows(Data(fixture.utf8),provider:"grok")
  assert(rows.count == 2 && rows[0].account == "first" && rows[1].windows[0].remaining == 20)
  assert(rows[0].windows[0].durationMinutes == 300)
  assert(ProviderCLI.decodeRows(Data(fixture.utf8),provider:"cursor").isEmpty)
  let credits = #"[{"provider":"openrouter","usage":{"details":[{"title":"Credits","rows":[{"label":"Remaining","value":"$4.00"}]}]}}]"#
  assert(ProviderCLI.decodeRows(Data(credits.utf8),provider:"openrouter")[0].details?[0].rows?[0].value == "$4.00")
  let err = #"[{"provider":"kimi","error":{"message":"sensitive token","code":1}}]"#
  assert(ProviderCLI.decodeRows(Data(err.utf8),provider:"kimi")[0].errorMessage?.contains("sensitive") == false)
  print("PASS preferences: defaults, deselection, last enabled, persistence")
  print("PASS parser: multi-account, provider isolation, dates, time window, credits, safe error")
  var calls: [String: Int] = [:]
  var concurrent = 0
  var peak = 0
  let store = ProviderUsageStore(fetch: { provider in
   calls[provider, default: 0] += 1
   concurrent += 1; peak = max(peak, concurrent)
   try? await Task.sleep(nanoseconds: 100_000_000)
   concurrent -= 1
   return ProviderCLI.Result(rows: [])
  })
  async let first: Void = store.refresh(provider: "grok")
  async let duplicate: Void = store.refresh(provider: "grok")
  async let other: Void = store.refresh(provider: "kimi")
  _ = await (first, duplicate, other)
  assert(calls["grok"] == 1 && calls["kimi"] == 1 && peak == 2)
  assert(!store.loading)
  await store.refresh(provider: "grok")
  assert(calls["grok"] == 1)
  print("PASS refresh: duplicate coalescing, independent providers, cooldown, loading cleanup")
  let costJSON = #"[{"provider":"codex","last30DaysTokens":1200,"last30DaysCostUSD":0.4,"daily":[{"date":"2026-09-14","totalTokens":1200,"totalCost":0.4,"modelBreakdowns":[{"modelName":"test-model","totalTokens":1200,"cost":0.4}]}],"projects":[{"name":"synthetic","totalTokens":1200,"totalCost":0.4}]}]"#
  let cost = try! JSONDecoder().decode([LocalCost].self, from: Data(costJSON.utf8))[0]
  assert(cost.daily?.first?.modelBreakdowns?.first?.cost == 0.4)
  assert(cost.projects?.first?.totalTokens == 1200)
  let partial = try! JSONDecoder().decode(LocalCost.self, from: Data(#"{"provider":"codex"}"#.utf8))
  assert(partial.last30DaysCostUSD == nil && partial.sortedDays.isEmpty)
  assert(ProductPreferences.catalog.contains { $0.id == "copilot" })
  assert(!ProductPreferences(defaults: defaults).enabled.contains("copilot"))
  print("PASS cost: daily/model/project schema, missing values; optional Copilot")
  let now = Date(timeIntervalSince1970: 10000)
  let pace = UsagePaceEstimate(remainingPercent: 25, durationMinutes: 100, resetsAt: now.addingTimeInterval(3000), now: now)!
  assert(pace.expectedRemainingPercent == 50 && pace.deficitPercent == 25)
  assert(abs(pace.estimatedSecondsUntilEmpty! - 1000) < 0.001 && !pace.willLastToReset)
  assert(UsagePaceEstimate(remainingPercent: 100, durationMinutes: 100, resetsAt: now.addingTimeInterval(3000), now: now)?.estimatedSecondsUntilEmpty == nil)
  assert(UsagePaceEstimate(remainingPercent: 25, durationMinutes: 0, resetsAt: now, now: now) == nil)
  assert(UsagePaceEstimate(remainingPercent: .nan, durationMinutes: 100, resetsAt: now.addingTimeInterval(3000), now: now) == nil)
  print("PASS pace: linear estimate, zero usage, invalid windows and non-finite inputs")
  guard CommandLine.arguments.contains("--live") else { return }
  for id in ["grok","openrouter"] {
   let result=await ProviderCLI.fetch(provider:id)
   assert(!result.rows.isEmpty)
   assert(result.rows.contains { $0.errorMessage == nil })
   print("PASS live query with multi-account fallback: \(id)")
  }
 }
}
