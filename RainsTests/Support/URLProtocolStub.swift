import Foundation

/// In-memory URLProtocol that returns canned `(Data, HTTPURLResponse)` pairs
/// keyed by the request URL's path. Use with a `URLSessionConfiguration` that
/// lists this class in `protocolClasses` to fake network calls in tests.
final class URLProtocolStub: URLProtocol {
    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data

        init(status: Int = 200, headers: [String: String] = ["Content-Type": "application/json"], body: Data) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    /// Path → response mapping. Reset between tests via `URLProtocolStub.reset()`.
    static var responses: [String: Response] = [:]

    /// Recorded requests, in arrival order, for assertion in tests.
    static var requests: [URLRequest] = []

    static func reset() {
        responses = [:]
        requests = []
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        URLProtocolStub.requests.append(request)

        let path = request.url?.path ?? ""
        guard let response = URLProtocolStub.responses[path] else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "URLProtocolStub",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "no stub for path: \(path)"]
            ))
            return
        }

        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
