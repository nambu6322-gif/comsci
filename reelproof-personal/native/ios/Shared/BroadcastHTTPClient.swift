import Foundation

final class BroadcastHTTPClient: NSObject, URLSessionTaskDelegate {
    static let delegate = BroadcastHTTPClient()
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()
    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void) {
        // A server redirect must never forward credentials or captured content.
        completionHandler(nil)
    }
}
