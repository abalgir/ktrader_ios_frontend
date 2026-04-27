import Foundation
import Combine

// ---------------------------------------------------------------------------
// MARK: - Configuration
// ---------------------------------------------------------------------------

enum APIConfig {
    static let host    = Bundle.main.infoDictionary?["BASE_HOST"] as? String ?? ""
    static let baseURL = "https://\(host)/api"
    static let apiKey  = Bundle.main.infoDictionary?["API_KEY"]  as? String ?? ""
}

// ---------------------------------------------------------------------------
// MARK: - Log response model
// ---------------------------------------------------------------------------

struct LogResponse: Decodable {
    let file:    String
    let key:     String
    let lines:   [String]
    let count:   Int
    let message: String?
}

// ---------------------------------------------------------------------------
// MARK: - Available log files
// ---------------------------------------------------------------------------

struct LogFile: Identifiable, Hashable {
    let id:    String
    let label: String
}

extension LogFile {
    static let all: [LogFile] = [
        LogFile(id: "auto_invest",         label: "App Log"),
        LogFile(id: "auto_live_trade",     label: "Buy Engine"),
        LogFile(id: "auto_sell_trade",     label: "Sell Engine"),
        LogFile(id: "phase1_fundamentals", label: "Phase 1 Fundamentals"),
        LogFile(id: "phase1_plus",         label: "Phase 1+"),
        LogFile(id: "phase2_indicator",    label: "Phase 2 Indicator"),
        LogFile(id: "store_data",          label: "Store Data"),
    ]
}

// ---------------------------------------------------------------------------
// MARK: - NetworkManager
// ---------------------------------------------------------------------------

@MainActor
class NetworkManager: ObservableObject {

    static let shared = NetworkManager()
    private init() {}

    // ---------------------------------------------------------------------------
    // MARK: - Log fetch
    // ---------------------------------------------------------------------------
    func fetchLog(fileKey: String) async throws -> LogResponse {
        try await get("/logs?file=\(fileKey)", as: LogResponse.self)
    }

    // ---------------------------------------------------------------------------
    // MARK: - Dashboard fetches
    // ---------------------------------------------------------------------------
    func fetchPortfolioReturns() async throws -> PortfolioReturns {
        try await get("/portfolio_returns", as: PortfolioReturns.self)
    }

    func fetchLivePositions() async throws -> LivePositionsResponse {
        try await get("/live_positions", as: LivePositionsResponse.self)
    }

    func fetchDeposit() async throws -> Double {
        try await get("/live_deposit", as: Double.self)
    }

    func fetchDetailedPL() async throws -> DetailedPL {
        try await get("/portfolio_detailed_pl", as: DetailedPL.self)
    }

    func fetchSP500Return() async throws -> Double {
        try await get("/current_year_sp500_return", as: Double.self)
    }

    func fetchNasdaqReturn() async throws -> Double {
        try await get("/current_year_nasdaq_return", as: Double.self)
    }

    func fetchAlphaVsSpy() async throws -> AlphaVsSpy {
        try await get("/portfolio/alpha_vs_spy", as: AlphaVsSpy.self)
    }

    // ---------------------------------------------------------------------------
    // MARK: - Tax Analysis
    // ---------------------------------------------------------------------------
    func fetchTaxAnalysis() async throws -> TaxAnalysis {
        try await get("/tax_analysis", as: TaxAnalysis.self)
    }
    
    // ---------------------------------------------------------------------------
    // MARK: - Settings
    // ---------------------------------------------------------------------------
    func fetchConfig() async throws -> AppConfig {
        try await get("/get_config", as: AppConfig.self)
    }

    func saveConfig(_ config: AppConfig) async throws {
        guard let url = URL(string: "\(APIConfig.baseURL)/save_config") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(APIConfig.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(config)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("❌ save_config failed: \(body)")
            throw URLError(.badServerResponse)
        }
    }

    // ---------------------------------------------------------------------------
    // MARK: - Generic GET — all fetches go through here
    // ---------------------------------------------------------------------------
    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
//        print("🔑 baseURL: \(APIConfig.baseURL)")
//        print("🔑 apiKey: \(APIConfig.apiKey)")

        guard let url = URL(string: "\(APIConfig.baseURL)\(path)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(APIConfig.apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("❌ HTTP \(http.statusCode) for \(path): \(body)")
            throw URLError(.badServerResponse)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("❌ Decode error for \(path): \(error)")
            print("   Raw JSON: \(body.prefix(300))")
            throw error
        }
    }
}
