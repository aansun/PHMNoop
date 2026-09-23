import Foundation
import StrandImport
import WhoopStore

struct StravaUploadResponse: Decodable {
    let id: Int?
    let activityId: Int?
    let status: String?
    let error: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case status, error, message
    }
}

struct StravaActivitySummary: Decodable {
    let id: Int?
    let sportType: String?
    let startDate: String?
    let externalId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sportType = "sport_type"
        case startDate = "start_date"
        case externalId = "external_id"
    }
}

/// Small Strava V3 client for the opt-in iOS integration. Uploads are initiated by the user or
/// the separately enabled automatic mode; the read path only reconciles the user's recent ledger.
final class StravaAPIClient {
    private let credentials: StravaCredentials
    private let session: URLSession

    init(credentials: StravaCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    func validAccessToken() async throws -> String {
        guard let tokens = StravaTokenStore.load() else { throw StravaError.notConnected }
        if !tokens.isExpired { return tokens.accessToken }
        let request = StravaOAuth.refreshRequest(credentials: credentials, refreshToken: tokens.refreshToken)
        do {
            let (data, response) = try await session.data(for: request)
            try StravaOAuthProvider.validate(response, data: data)
            let refreshed = try StravaOAuth.parseTokenResponse(data)
            guard StravaTokenStore.save(refreshed) else {
                throw StravaError.tokenExchange("Could not refresh Strava tokens in Keychain")
            }
            return refreshed.accessToken
        } catch let error as StravaError {
            throw error
        } catch {
            throw StravaError.network(error.localizedDescription)
        }
    }

    func upload(row: WorkoutRow, route: [RouteMath.LatLng]) async throws -> StravaUploadResponse {
        guard route.count >= 2 else { throw StravaError.noRoute }
        let token = try await validAccessToken()
        let points = route.map { RoutePoint(lat: $0.lat, lon: $0.lon) }
        let file = RouteExporter.render(
            .fit, route: points, startTs: row.startTs, endTs: row.endTs, sport: row.sport,
            distanceM: row.distanceM, energyKcal: row.energyKcal, avgHr: row.avgHr, maxHr: row.maxHr)
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: StravaOAuth.apiBase.appendingPathComponent("uploads"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: [
                "name": WorkoutSource.displaySport(row.sport),
                "sport_type": StravaActivityType.value(for: row.sport),
                "data_type": "fit",
                "external_id": "noop-\(row.startTs)-\(row.sport)",
            ],
            file: file,
            filename: "noop-\(row.startTs).fit")

        do {
            let (data, response) = try await session.data(for: request)
            try StravaOAuthProvider.validate(response, data: data)
            guard let upload = try? JSONDecoder().decode(StravaUploadResponse.self, from: data),
                  upload.id != nil else { throw StravaError.invalidUpload }
            return upload
        } catch let error as StravaError {
            throw error
        } catch {
            throw StravaError.network(error.localizedDescription)
        }
    }

    func waitForUploadCompletion(_ initial: StravaUploadResponse,
                                 attempts: Int = 10,
                                 intervalNanoseconds: UInt64 = 2_000_000_000) async throws -> StravaUploadResponse {
        guard let uploadId = initial.id, initial.activityId == nil, initial.error == nil else { return initial }
        var latest = initial
        for _ in 0..<max(attempts, 0) {
            try await Task.sleep(nanoseconds: intervalNanoseconds)
            latest = try await uploadStatus(uploadId: uploadId)
            if latest.activityId != nil || latest.error != nil { break }
        }
        return latest
    }

    func uploadStatus(uploadId: Int) async throws -> StravaUploadResponse {
        let token = try await validAccessToken()
        var request = URLRequest(url: StravaOAuth.apiBase.appendingPathComponent("uploads/\(uploadId)"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            try StravaOAuthProvider.validate(response, data: data)
            guard let status = try? JSONDecoder().decode(StravaUploadResponse.self, from: data) else {
                throw StravaError.invalidUpload
            }
            return status
        } catch let error as StravaError {
            throw error
        } catch {
            throw StravaError.network(error.localizedDescription)
        }
    }

    func recentActivities(after: Int, before: Int, pageSize: Int = 200) async throws -> [StravaActivitySummary] {
        let token = try await validAccessToken()
        var all: [StravaActivitySummary] = []

        for page in 1...5 {
            var components = URLComponents(
                url: StravaOAuth.apiBase.appendingPathComponent("athlete/activities"),
                resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "after", value: String(after)),
                URLQueryItem(name: "before", value: String(before)),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(min(max(pageSize, 1), 200))),
            ]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await session.data(for: request)
                try StravaOAuthProvider.validate(response, data: data)
                let pageItems = try JSONDecoder().decode([StravaActivitySummary].self, from: data)
                all.append(contentsOf: pageItems)
                if pageItems.count < min(max(pageSize, 1), 200) { break }
            } catch let error as StravaError {
                throw error
            } catch {
                throw StravaError.network(error.localizedDescription)
            }
        }
        return all
    }

    func deauthorize() async throws {
        let token = try await validAccessToken()
        let request = StravaOAuth.deauthorizeRequest(accessToken: token)
        let (data, response) = try await session.data(for: request)
        try StravaOAuthProvider.validate(response, data: data)
    }

    private static func multipartBody(boundary: String, fields: [String: String], file: Data,
                                      filename: String) -> Data {
        var body = Data()
        let line = "\r\n"
        for (name, value) in fields {
            body.append(Data("--\(boundary)\(line)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\(line)\(line)".utf8))
            body.append(Data(value.utf8))
            body.append(Data(line.utf8))
        }
        body.append(Data("--\(boundary)\(line)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(line)".utf8))
        body.append(Data("Content-Type: application/octet-stream\(line)\(line)".utf8))
        body.append(file)
        body.append(Data(line.utf8))
        body.append(Data("--\(boundary)--\(line)".utf8))
        return body
    }
}
