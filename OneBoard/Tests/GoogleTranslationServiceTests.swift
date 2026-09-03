import Foundation
import XCTest
@testable import OneBoardKit

final class GoogleTranslationServiceTests: XCTestCase {
    override func tearDown() {
        GoogleTranslationURLProtocol.handler = nil
        super.tearDown()
    }

    func testRateLimitHTMLReturnsActionableErrorWithoutLeakingResponseBody() async throws {
        let html = "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\"><html>Sorry...</html>"
        GoogleTranslationURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html; charset=UTF-8"]
            )!
            return (response, Data(html.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GoogleTranslationURLProtocol.self]
        let service = GoogleTranslationService(session: URLSession(configuration: configuration))

        do {
            _ = try await service.translate("Invalid authorize request", from: "en", to: "zh-Hans")
            XCTFail("Expected Google rate-limit failure")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Google 翻译请求过于频繁，当前网络已被 Google 暂时限制。请稍后重试，或切换 Apple/DeepSeek。"
            )
            XCTAssertFalse(error.localizedDescription.contains("DOCTYPE"))
        }
    }
}

private final class GoogleTranslationURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw TranslationServiceError.translationFailed("Missing handler")
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
