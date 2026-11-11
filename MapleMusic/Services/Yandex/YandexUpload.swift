import Foundation

enum YandexUpload {
    static func isTrustedTarget(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return ["yandex.net", "yandex.ru", "yandex.com"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    static func send(_ source: URL, to target: URL, fileName: String) async throws {
        guard isTrustedTarget(target), source.isFileURL else { throw MusicServiceError.invalidResponse }
        let boundary = "MapleMusic-" + UUID().uuidString
        let safeName = fileName.components(separatedBy: CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: "\"\\/"))).joined(separator: "_")
        let body = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: body) }
        guard FileManager.default.createFile(atPath: body.path, contents: nil, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]) else { throw MusicServiceError.offlineUnavailable }
        try writeBody(from: source, to: body, boundary: boundary, name: safeName)
        var request = URLRequest(url: target, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // The target URL is already signed; no OAuth header or cookies are sent.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.upload(for: request, fromFile: body, delegate: NoRedirects())
        guard let http = response as? HTTPURLResponse else { throw MusicServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MusicServiceError.http(http.statusCode) }
    }

    private static func writeBody(from source: URL, to destination: URL, boundary: String, name: String) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: audio/mpeg\r\n\r\n"
        try output.write(contentsOf: Data(header.utf8))
        while let bytes = try input.read(upToCount: 256 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: bytes)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
