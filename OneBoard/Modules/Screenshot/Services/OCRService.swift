import AppKit
import Vision

/// OCR 服务协议
protocol OCRServiceProtocol {
    func recognizeText(in image: NSImage, language: String) async throws -> String
}

/// Apple Vision OCR 实现（默认，离线免费）
final class AppleVisionOCRService: OCRServiceProtocol {
    func recognizeText(in image: NSImage, language: String) async throws -> String {
        guard let cgImage = Self.makeCGImage(from: image) else {
            throw OCRServiceError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = Self.preferredLanguages(primary: language, request: request)
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.01

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return "" }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private static func makeCGImage(from image: NSImage) -> CGImage? {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgImage
        }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.cgImage
    }

    private static func preferredLanguages(primary: String, request: VNRecognizeTextRequest) -> [String] {
        let fallbacks = [primary, "zh-Hans", "zh-Hant", "en-US", "en"]
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let usable = fallbacks.filter { supported.contains($0) }
        return usable.isEmpty ? [primary] : Array(NSOrderedSet(array: usable)) as? [String] ?? [primary]
    }
}

/// 第三方 OCR 服务（扩展点，后续实现）
final class ThirdPartyOCRService: OCRServiceProtocol {
    func recognizeText(in image: NSImage, language: String) async throws -> String {
        guard let raw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.ocrAIProviderID),
              let id = UUID(uuidString: raw),
              let profile = AIProviderStore.shared.profiles.first(where: { $0.id == id && $0.kind == .custom }) else {
            throw OCRServiceError.recognitionFailed("请先在设置中选择 AI 服务")
        }
        let key = try SQLiteAIProviderSecretVault().load(for: profile.id)
        let request = try AIImageOCRRequest.make(image: image, language: language, profile: profile, key: key)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OCRServiceError.recognitionFailed("\(profile.title) 识别失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）")
        }
        do {
            return try ConfiguredAITranslationService.parse(data, format: profile.apiFormat ?? .recommendedValue(for: profile.client, baseURL: profile.baseURL)).text
        } catch {
            throw OCRServiceError.recognitionFailed("AI 服务未返回可用文字")
        }
    }
}

private enum AIImageOCRRequest {
    static func make(image: NSImage, language: String, profile: AIProviderProfile, key: String) throws -> URLRequest {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { throw OCRServiceError.invalidImage }
        let base64 = jpeg.base64EncodedString()
        let dataURL = "data:image/jpeg;base64,\(base64)"
        let prompt = "Recognize all visible text in this image, prioritizing language \(language). Preserve reading order and line breaks. Return only the recognized text."
        let format = profile.apiFormat ?? .recommendedValue(for: profile.client, baseURL: profile.baseURL)
        var request = try ConfiguredAITranslationService.request(profile: profile, key: key, text: prompt, source: nil, target: "plain text")
        guard var body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] else {
            throw OCRServiceError.recognitionFailed("AI 请求格式无效")
        }
        switch format {
        case .openAIChat:
            body["messages"] = [["role": "user", "content": [["type": "text", "text": prompt], ["type": "image_url", "image_url": ["url": dataURL]]]]]
        case .openAIResponses:
            body["input"] = [["role": "user", "content": [["type": "input_text", "text": prompt], ["type": "input_image", "image_url": dataURL]]]]
        case .anthropic:
            body["messages"] = [["role": "user", "content": [["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]], ["type": "text", "text": prompt]]]]
        case .geminiNative:
            body["contents"] = [["role": "user", "parts": [["text": prompt], ["inline_data": ["mime_type": "image/jpeg", "data": base64]]]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

enum OCRServiceError: LocalizedError {
    case invalidImage
    case notImplemented
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "图片格式无效，无法识别"
        case .notImplemented:
            return "第三方 OCR 暂未配置"
        case .recognitionFailed(let message):
            return message
        }
    }
}

/// OCR 服务工厂
enum OCRServiceFactory {
    static func create() -> OCRServiceProtocol {
        let serviceType = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.ocrServiceType) ?? "apple"
        switch serviceType {
        case "third_party":
            return ThirdPartyOCRService()
        default:
            return AppleVisionOCRService()
        }
    }
}
