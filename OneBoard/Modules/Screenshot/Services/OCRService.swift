import AppKit
import Vision

/// OCR 服务协议
protocol OCRServiceProtocol {
    func recognizeText(in image: NSImage, language: String) async throws -> String
}

/// Apple Vision OCR 实现（默认，离线免费）
final class AppleVisionOCRService: OCRServiceProtocol {
    func recognizeText(in image: NSImage, language: String) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRServiceError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [language]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return "" }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

/// 第三方 OCR 服务（扩展点，后续实现）
final class ThirdPartyOCRService: OCRServiceProtocol {
    func recognizeText(in image: NSImage, language: String) async throws -> String {
        // TODO: 对接第三方 OCR API（百度、Google 等）
        throw OCRServiceError.notImplemented
    }
}

enum OCRServiceError: Error {
    case invalidImage
    case notImplemented
    case recognitionFailed(String)
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