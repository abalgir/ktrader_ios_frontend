import SwiftUI
import Combine

// ---------------------------------------------------------------------------
// MARK: - ViewModel
// ---------------------------------------------------------------------------

@MainActor
class DashboardViewModel: ObservableObject {

    // Header
    @Published var portfolioValue:  Double = 0
    @Published var cash:            Double = 0
    @Published var deposit:         Double = 0

    // Returns — rebased to $290K inception baseline (matches Streamlit)
    @Published var inceptionReturn: Double = 0
    @Published var inceptionDollar: Double = 0
    @Published var ytdReturn:       Double = 0
    @Published var ytdDollar:       Double = 0
    @Published var asOf:            String = ""

    // Benchmarks
    @Published var sp500Return:     Double = 0
    @Published var nasdaqReturn:    Double = 0

    // Positions
    @Published var positions:       [StockPosition] = []

    // Detailed P&L
    @Published var detailedPL:      DetailedPL? = nil

    // Alpha vs SPY (closed-trade hold-window comparison; optional, never blocks dashboard)
    @Published var alpha:           AlphaSummary? = nil

    // State
    @Published var isLoading:       Bool   = false
    @Published var errorMsg:        String? = nil
    @Published var lastRefresh:     Date?  = nil

    // Computed totals
    var totalTodayPL: Double { positions.reduce(0) { $0 + $1.todayPL } }

    // Inception baseline — same as Streamlit INCEPTION_BASELINE_EQUITY
    private let inceptionBaseline: Double = 290_000.0

    // ---------------------------------------------------------------------------
    func load() async {
        isLoading = true
        errorMsg  = nil

        do {
            async let retFetch  = NetworkManager.shared.fetchPortfolioReturns()
            async let posFetch  = NetworkManager.shared.fetchLivePositions()
            async let depFetch  = NetworkManager.shared.fetchDeposit()
            async let plFetch   = NetworkManager.shared.fetchDetailedPL()
            async let sp500Fetch = NetworkManager.shared.fetchSP500Return()
            async let nasdaqFetch = NetworkManager.shared.fetchNasdaqReturn()

            // Alpha is OPTIONAL — try? so a failure here never blanks the dashboard
            async let alphaFetch  = try? NetworkManager.shared.fetchAlphaVsSpy()

            let (ret, pos, dep, pl, sp500, nasdaq) = try await (
                retFetch, posFetch, depFetch, plFetch, sp500Fetch, nasdaqFetch
            )
            let alphaResp = await alphaFetch

            // Header
            portfolioValue = pos.accountInfo?.portfolioValue ?? 0
            cash           = pos.accountInfo?.cash           ?? 0
            deposit        = dep
            asOf           = ret.asOf ?? ""

            // Rebase inception return to $290K baseline (same as Streamlit)
            // inception_dollar = current_equity - 290K
            // inception_return = (current_equity / 290K - 1) * 100
            let equity = portfolioValue > 0 ? portfolioValue : (ret.equityCurrent ?? 0)
            inceptionDollar = equity - inceptionBaseline
            inceptionReturn = inceptionBaseline > 0
                ? ((equity / inceptionBaseline) - 1.0) * 100.0
                : 0.0

            // YTD comes directly from backend (snapshot-based, correct)
            ytdReturn = ret.ytdReturn
            ytdDollar = ret.ytdDollar

            // Positions — parse the JSON string
            if let jsonStr  = pos.positionJson,
               let jsonData = jsonStr.data(using: .utf8) {
                positions = (try? JSONDecoder().decode([StockPosition].self,
                                                       from: jsonData)) ?? []
            }

            // Benchmarks
            sp500Return  = sp500
            nasdaqReturn = nasdaq

            // Detailed P&L
            detailedPL   = pl

            // Alpha vs SPY — set if fetch succeeded, leave previous value if it didn't
            if let a = alphaResp {
                alpha = a.summary
            }

            lastRefresh  = Date()

        } catch {
            errorMsg = error.localizedDescription
            print("❌ Dashboard load error: \(error)")
        }

        isLoading = false
    }
}

// ---------------------------------------------------------------------------
// MARK: - DashboardView
// ---------------------------------------------------------------------------

struct DashboardView: View {

    @StateObject private var vm = DashboardViewModel()
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.portfolioValue == 0 {
                    ProgressView("Loading dashboard…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            headerSection
                            returnsSection
                            benchmarkSection
                            alphaSection
                            positionsSection
                            detailedPLSection
                        }
                        .padding()
                    }
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 6) {
                        if vm.isLoading {
                            ProgressView().scaleEffect(0.7)
                        }
                        if let last = vm.lastRefresh {
                            Text(last, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .alert("Load Error", isPresented: .constant(vm.errorMsg != nil)) {
                Button("Retry")   { Task { await vm.load() } }
                Button("Dismiss") { vm.errorMsg = nil }
            } message: {
                Text(vm.errorMsg ?? "")
            }
        }
        .task { await vm.load() }
        .onReceive(timer) { _ in Task { await vm.load() } }
    }

    // ---------------------------------------------------------------------------
    // MARK: - Sections
    // ---------------------------------------------------------------------------

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Account Overview")
            HStack(spacing: 12) {
                KPICard(title: "Portfolio",
                        value: fmtCurrency(vm.portfolioValue),
                        color: .primary)
                KPICard(title: "Cash",
                        value: fmtCurrency(vm.cash),
                        color: .blue)
                KPICard(title: "Deposit",
                        value: fmtCurrency(vm.deposit),
                        color: .secondary)
            }
        }
        .cardStyle()
    }

    private var returnsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("Performance")
                Spacer()
                if !vm.asOf.isEmpty {
                    Text("as of \(vm.asOf)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 12) {
                KPICard(title: "Inception ROI",
                        value: fmtPct(vm.inceptionReturn),
                        color: vm.inceptionReturn >= 0 ? .green : .red)
                KPICard(title: "Inception $",
                        value: fmtCurrency(vm.inceptionDollar),
                        color: vm.inceptionDollar >= 0 ? .green : .red)
            }
            HStack(spacing: 12) {
                KPICard(title: "YTD ROI",
                        value: fmtPct(vm.ytdReturn),
                        color: vm.ytdReturn >= 0 ? .green : .red)
                KPICard(title: "YTD $",
                        value: fmtCurrency(vm.ytdDollar),
                        color: vm.ytdDollar >= 0 ? .green : .red)
            }
        }
        .cardStyle()
    }

    private var benchmarkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Benchmark (Calendar YTD)")
            let deltasp = vm.ytdReturn - vm.sp500Return
            let deltand = vm.ytdReturn - vm.nasdaqReturn
            HStack(spacing: 12) {
                KPICard(title: "S&P 500",
                        value: fmtPct(vm.sp500Return),
                        subtitle: "you: \(deltasp >= 0 ? "+" : "")\(fmtPct(deltasp)) vs index",
                        color: deltasp >= 0 ? .green : .red)
                KPICard(title: "Nasdaq",
                        value: fmtPct(vm.nasdaqReturn),
                        subtitle: "you: \(deltand >= 0 ? "+" : "")\(fmtPct(deltand)) vs index",
                        color: deltand >= 0 ? .green : .red)
            }
        }
        .cardStyle()
    }

    private var alphaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Closed Trades vs SPY (Matched Hold Windows)")

            if let a = vm.alpha, a.totalClosedPositions > 0 {
                Text("\(a.totalClosedPositions) positions • avg \(Int(a.avgHoldDays))-day hold • \(a.earliestEntry) → \(a.latestExit)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Verdict pill — one-glance answer to "is the algo good?"
                let verdict = alphaVerdict(a)
                HStack(spacing: 6) {
                    Text(verdict.label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(verdict.fg.opacity(0.15))
                        .foregroundColor(verdict.fg)
                        .cornerRadius(6)
                    Spacer()
                }
                .padding(.top, 2)

                HStack(spacing: 12) {
                    KPICard(title: "Portfolio (ann.)",
                            value: fmtPct(a.portfolioReturnAnnualizedPct),
                            subtitle: "\(fmtPct(a.portfolioReturnPct)) per trade",
                            color: a.portfolioReturnAnnualizedPct >= 0 ? .green : .red)
                    KPICard(title: "SPY (ann.)",
                            value: fmtPct(a.spySameWindowReturnAnnualizedPct),
                            subtitle: "\(fmtPct(a.spySameWindowReturnPct)) per trade",
                            color: a.spySameWindowReturnAnnualizedPct >= 0 ? .green : .red)
                }
                HStack(spacing: 12) {
                    KPICard(title: "Alpha (ann.)",
                            value: "\(a.alphaAnnualizedPct >= 0 ? "+" : "")\(fmtPct(a.alphaAnnualizedPct))",
                            subtitle: "\(a.alphaPct >= 0 ? "+" : "")\(fmtPct(a.alphaPct)) per trade",
                            color: a.alphaAnnualizedPct >= 0 ? .green : .red)
                    KPICard(title: "Hit Rate",
                            value: fmtPct(a.hitRatePct),
                            subtitle: "% trades beating SPY",
                            color: a.hitRatePct >= 50 ? .green : .red)
                }
                HStack(spacing: 12) {
                    KPICard(title: "Total $ Alpha",
                            value: "\(a.totalDollarAlpha >= 0 ? "+" : "")\(fmtCurrency(a.totalDollarAlpha))",
                            subtitle: "cumulative $ vs SPY",
                            color: a.totalDollarAlpha >= 0 ? .green : .red)
                }

                // How to read this
                Text(verdict.hint)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                Text("Annualized = per-trade rate × turnover. Assumes constant trade pacing; not your actual realized annual return.")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()
            } else {
                Text("No closed positions yet")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .cardStyle()
    }

    // ---------------------------------------------------------------------------
    // Alpha verdict — one-glance "is this good?" classifier.
    // Bands chosen for a personal swing-trading system on US equities.
    // Alpha here is per-trade (matched hold window), not annualised.
    // ---------------------------------------------------------------------------
    private func alphaVerdict(_ a: AlphaSummary) -> (label: String, fg: Color, hint: String) {
        if a.alphaPct < 0 {
            return (
                "UNDERPERFORMING SPY",
                .red,
                "On average your closed trades trail SPY held over the same days. The system is not adding value vs passive."
            )
        }
        if a.alphaPct < 1.0 || a.hitRatePct < 50 {
            return (
                "NO MEANINGFUL EDGE",
                .gray,
                "Alpha is positive but small, or hit rate is sub-50%. Could easily be noise. Compare $-alpha to brokerage costs and time spent."
            )
        }
        if a.alphaPct >= 3.0 && a.hitRatePct >= 55 {
            return (
                "SOLID EDGE",
                .green,
                "Alpha ≥ 3pp and hit rate ≥ 55%. The system is meaningfully beating passive SPY-holding on apples-to-apples hold windows."
            )
        }
        return (
            "MODEST EDGE",
            .blue,
            "Real positive alpha, but not strong. Edge exists; size is modest. Watch over time; don't tune to chase."
        )
    }

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("Positions (\(vm.positions.count))")
                Spacer()
                let pl = vm.totalTodayPL
                Text("Today: \(fmtCurrency(pl))")
                    .font(.caption)
                    .foregroundColor(pl >= 0 ? .green : .red)
            }

            if vm.positions.isEmpty {
                Text("No positions")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                // Header row
                HStack {
                    Text("Ticker")
                        .frame(width: 55, alignment: .leading)
                    Text("Price")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Mkt Val")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("ROI%")
                        .frame(width: 58, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                Divider()

                ForEach(vm.positions.sorted { $0.inceptionPL > $1.inceptionPL }) { pos in
                    PositionRow(pos: pos)
                    Divider()
                }
            }
        }
        .cardStyle()
    }

    private var detailedPLSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Detailed P&L (EOD)")
            if let pl = vm.detailedPL {
                PLRow(label: "Current Year Deposit",
                      value: fmtCurrency(pl.ytdDeposit ?? 0))
                PLRow(label: "Realized P&L (YTD)",
                      value: fmtCurrency(pl.ytdRealizedPL ?? 0),
                      color: (pl.ytdRealizedPL ?? 0) >= 0 ? .green : .red)
                PLRow(label: "YTD Change Unrealized P&L",
                      value: fmtCurrency(pl.ytdUnrealizedPL ?? 0),
                      color: (pl.ytdUnrealizedPL ?? 0) >= 0 ? .green : .red)
                PLRow(label: "YTD Portfolio Change",
                      value: fmtCurrency(pl.ytdPortfolioValue ?? 0),
                      color: (pl.ytdPortfolioValue ?? 0) >= 0 ? .green : .red)
            } else {
                Text("No P&L data")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .cardStyle()
    }

    // ---------------------------------------------------------------------------
    // MARK: - Helpers
    // ---------------------------------------------------------------------------

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func fmtCurrency(_ v: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: v)) ?? "$0"
    }

    private func fmtPct(_ v: Double) -> String {
        String(format: "%.2f%%", v)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Reusable sub-views
// ---------------------------------------------------------------------------

struct KPICard: View {
    let title:    String
    let value:    String
    var subtitle: String? = nil
    var color:    Color   = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let sub = subtitle {
                Text(sub)
                    .font(.caption2)
                    .foregroundColor(color.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
}

struct PositionRow: View {
    let pos: StockPosition

    var body: some View {
        HStack {
            Text(pos.ticker)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 55, alignment: .leading)
            Text(String(format: "$%.2f", pos.price))
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(String(format: "$%.0f", pos.marketValue))
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(String(format: "%.1f%%", pos.pctChange))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(pos.pctChange >= 0 ? .green : .red)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}

struct PLRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.vertical, 2)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Card style
// ---------------------------------------------------------------------------

extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
    }
}

#Preview {
    DashboardView()
}
