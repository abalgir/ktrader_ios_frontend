import Foundation

// ---------------------------------------------------------------------------
// MARK: - Portfolio Returns
// Matches exactly: /api/portfolio_returns
// ---------------------------------------------------------------------------

struct PortfolioReturns: Decodable {
    let inceptionReturn:  Double
    let inceptionDollar:  Double
    let ytdReturn:        Double
    let ytdDollar:        Double
    let asOf:             String?
    let equityCurrent:    Double?

    enum CodingKeys: String, CodingKey {
        case inceptionReturn  = "inception_return"
        case inceptionDollar  = "inception_dollar"
        case ytdReturn        = "ytd_return"
        case ytdDollar        = "ytd_dollar"
        case asOf             = "as_of"
        case equityCurrent    = "equity_current"
    }
}

// ---------------------------------------------------------------------------
// MARK: - Account Info
// Note: Alpaca returns all numeric fields as STRINGS ("cash": "7507.36")
// We use a custom init to handle both String and Double
// ---------------------------------------------------------------------------

struct AccountInfo {
    let portfolioValue: Double
    let cash:           Double
    let accountNumber:  String
}

extension AccountInfo: Decodable {
    enum CodingKeys: String, CodingKey {
        case portfolioValue = "portfolio_value"
        case cash
        case accountNumber  = "account_number"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // portfolio_value — try Double first, then String
        if let d = try? c.decode(Double.self, forKey: .portfolioValue) {
            portfolioValue = d
        } else if let s = try? c.decode(String.self, forKey: .portfolioValue) {
            portfolioValue = Double(s) ?? 0
        } else {
            portfolioValue = 0
        }

        // cash — same pattern
        if let d = try? c.decode(Double.self, forKey: .cash) {
            cash = d
        } else if let s = try? c.decode(String.self, forKey: .cash) {
            cash = Double(s) ?? 0
        } else {
            cash = 0
        }

        accountNumber = (try? c.decode(String.self, forKey: .accountNumber)) ?? ""
    }
}

// ---------------------------------------------------------------------------
// MARK: - Live Positions Response
// ---------------------------------------------------------------------------

struct LivePositionsResponse: Decodable {
    let accountInfo:  AccountInfo?
    let positionJson: String?

    enum CodingKeys: String, CodingKey {
        case accountInfo  = "account_info"
        case positionJson = "position_json"
    }
}

// ---------------------------------------------------------------------------
// MARK: - Single Stock Position
// Parsed from positionJson string — keys are exactly as shown in the JSON
// ---------------------------------------------------------------------------

struct StockPosition: Decodable, Identifiable {
    var id = UUID()
    let ticker:        String
    let price:         Double
    let tradedPrice:   Double
    let closingPrice:  Double
    let quantity:      Double
    let cost:          Double
    let marketValue:   Double
    let inceptionPL:   Double
    let ytdPL:         Double

    enum CodingKeys: String, CodingKey {
        case ticker       = "Ticker"
        case price        = "Price"
        case tradedPrice  = "Traded Price"
        case closingPrice = "Closing Price"
        case quantity     = "Quantity"
        case cost         = "Cost"
        case marketValue  = "Market Value"
        case inceptionPL  = "Inception P&L"
        case ytdPL        = "YTD P&L"
    }

    var pctChange: Double {
        guard tradedPrice > 0 else { return 0 }
        return ((price - tradedPrice) / tradedPrice) * 100
    }

    var todayPL: Double {
        return (price - closingPrice) * quantity
    }
}

// ---------------------------------------------------------------------------
// MARK: - Detailed P&L
// Matches exactly: /api/portfolio_detailed_pl
// ---------------------------------------------------------------------------

struct DetailedPL: Decodable {
    let ytdDeposit:        Double?
    let ytdRealizedPL:     Double?
    let ytdUnrealizedPL:   Double?
    let ytdPortfolioValue: Double?

    enum CodingKeys: String, CodingKey {
        case ytdDeposit        = "YTD_deposit"
        case ytdRealizedPL     = "YTD_realized_pl"
        case ytdUnrealizedPL   = "YTD_unrealized_pl"
        case ytdPortfolioValue = "YTD_total_portfolio_value"
    }
}

// ---------------------------------------------------------------------------
// MARK: - Alpha vs SPY
// Matches exactly: /api/portfolio/alpha_vs_spy
// ---------------------------------------------------------------------------

struct AlphaVsSpy: Decodable {
    let computedAt: String
    let summary:    AlphaSummary

    enum CodingKeys: String, CodingKey {
        case computedAt = "computed_at"
        case summary
    }
}

struct AlphaSummary: Decodable {
    let totalClosedPositions:           Int
    let earliestEntry:                  String
    let latestExit:                     String
    let avgHoldDays:                    Double
    let portfolioReturnPct:             Double
    let portfolioReturnAnnualizedPct:   Double
    let spySameWindowReturnPct:         Double
    let spySameWindowReturnAnnualizedPct: Double
    let alphaPct:                       Double
    let alphaAnnualizedPct:             Double
    let hitRatePct:                     Double
    let totalDollarAlpha:               Double

    enum CodingKeys: String, CodingKey {
        case totalClosedPositions             = "total_closed_positions"
        case earliestEntry                    = "earliest_entry"
        case latestExit                       = "latest_exit"
        case avgHoldDays                      = "avg_hold_days"
        case portfolioReturnPct               = "portfolio_return_pct"
        case portfolioReturnAnnualizedPct     = "portfolio_return_annualized_pct"
        case spySameWindowReturnPct           = "spy_same_window_return_pct"
        case spySameWindowReturnAnnualizedPct = "spy_same_window_return_annualized_pct"
        case alphaPct                         = "alpha_pct"
        case alphaAnnualizedPct               = "alpha_annualized_pct"
        case hitRatePct                       = "hit_rate_pct"
        case totalDollarAlpha                 = "total_dollar_alpha"
    }
}
