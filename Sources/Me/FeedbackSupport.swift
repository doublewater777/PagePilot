import Foundation
import UIKit

struct FeedbackPayload: Equatable, Encodable {
    let message: String
    let appVersion: String
    let osVersion: String
}

enum FeedbackValidationError: Error, Equatable {
    case emptyMessage
    case messageTooLong
}

struct FeedbackPayloadBuilder {
    static let maximumMessageLength = 2_000

    var appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    var osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString

    static func messageLength(_ message: String) -> Int {
        message.unicodeScalars.count
    }

    func build(message: String) throws -> FeedbackPayload {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FeedbackValidationError.emptyMessage }
        guard Self.messageLength(message) <= Self.maximumMessageLength else {
            throw FeedbackValidationError.messageTooLong
        }
        return FeedbackPayload(message: trimmed, appVersion: appVersion, osVersion: osVersion)
    }
}

enum FeedbackSubmissionError: Error, Equatable {
    case networkFailure
    case messageTooLong
    case rateLimited
    case rejected

    var localizationKey: String {
        switch self {
        case .networkFailure: return "feedback_network_failure"
        case .messageTooLong: return "feedback_message_too_long"
        case .rateLimited: return "feedback_rate_limited"
        case .rejected: return "feedback_rejected"
        }
    }
}

struct FeedbackSubmissionService {
    var session: URLSession = .shared
    var endpoint: URL = URL(string: "https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com/pagepilotFeedback")!

    @MainActor
    func submit(_ payload: FeedbackPayload) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(RequestBody(
            appInstanceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            appSignature: "pagepilot-app-signature-v1",
            message: payload.message,
            appVersion: payload.appVersion,
            osVersion: payload.osVersion
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeedbackSubmissionError.networkFailure
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let result = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
            throw FeedbackSubmissionError.rejected
        }
        guard result.ok else {
            switch result.error?.code {
            case "MESSAGE_TOO_LONG": throw FeedbackSubmissionError.messageTooLong
            case "RATE_LIMITED": throw FeedbackSubmissionError.rateLimited
            default: throw FeedbackSubmissionError.rejected
            }
        }
    }

    private struct RequestBody: Encodable {
        let appInstanceId: String
        let appSignature: String
        let message: String
        let appVersion: String
        let osVersion: String
    }

    private struct ResponseBody: Decodable {
        let ok: Bool
        let error: BackendError?
    }

    private struct BackendError: Decodable {
        let code: String
    }
}
