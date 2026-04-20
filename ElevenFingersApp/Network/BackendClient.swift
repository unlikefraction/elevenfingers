import Foundation

struct OCRResult: Decodable {
    let text: String
    let elapsed_ms: Int
}

struct STTResult: Decodable {
    let text: String
    let language: String?
    let elapsed_ms: Int
}

struct WriterResult: Decodable {
    let text: String
    let elapsed_ms: Int
}

struct WriterRequestBody: Encodable {
    let ocr: String?
    let stt: String?
    let dictionary: String?
}

enum BackendError: Error {
    case invalidResponse
    case http(Int, String)
}

final class BackendClient {
    static let shared = BackendClient()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    func ocr(image: Data, dictionary: String?) async throws -> OCRResult {
        let url = BackendConfig.baseURL().appendingPathComponent("ocr")
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func boundaryLine() { body.append("--\(boundary)\r\n".data(using: .utf8)!) }

        boundaryLine()
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"canvas.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(image)
        body.append("\r\n".data(using: .utf8)!)

        if let dictionary, !dictionary.isEmpty {
            boundaryLine()
            body.append("Content-Disposition: form-data; name=\"dictionary\"\r\n\r\n".data(using: .utf8)!)
            body.append(dictionary.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return try await send(request: request, body: body)
    }

    func stt(audio: Data, languageCode: String) async throws -> STTResult {
        let url = BackendConfig.baseURL().appendingPathComponent("stt")
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func boundaryLine() { body.append("--\(boundary)\r\n".data(using: .utf8)!) }

        boundaryLine()
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"current.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)

        boundaryLine()
        body.append("Content-Disposition: form-data; name=\"language_code\"\r\n\r\n".data(using: .utf8)!)
        body.append(languageCode.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return try await send(request: request, body: body)
    }

    func writer(ocr: String?, stt: String?, dictionary: String?) async throws -> WriterResult {
        let url = BackendConfig.baseURL().appendingPathComponent("writer")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = WriterRequestBody(ocr: ocr, stt: stt, dictionary: dictionary)
        let body = try JSONEncoder().encode(payload)

        return try await send(request: request, body: body)
    }

    private func send<T: Decodable>(request: URLRequest, body: Data) async throws -> T {
        var request = request
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw BackendError.http(http.statusCode, msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
