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
        // TODO: 对接第三方 OCR API（百度、Google 等）
        throw OCRServiceError.notImplemented
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
