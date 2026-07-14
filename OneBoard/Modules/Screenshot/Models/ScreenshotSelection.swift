import CoreGraphics

enum ScreenshotResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    func center(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

enum ScreenshotSelectionPhase: Equatable {
    case selecting
    case adjusting
    case locked
}

enum ScreenshotSelectionAction: Equatable {
    case annotate(AnnotationTool)
    case copy
    case save
    case pin
    case ocr
    case translate
}

enum ScreenshotLockedRoute: Equatable {
    case annotation(AnnotationTool)
    case copy
    case save
    case pin
    case ocr
    case translate

    static func route(for action: ScreenshotSelectionAction) -> ScreenshotLockedRoute {
        switch action {
        case .annotate(let tool): return .annotation(tool)
        case .copy: return .copy
        case .save: return .save
        case .pin: return .pin
        case .ocr: return .ocr
        case .translate: return .translate
        }
    }
}

enum ScreenshotSelectionGeometry {
    static func moved(_ rect: CGRect, by translation: CGSize, inside bounds: CGRect) -> CGRect {
        let x = min(max(rect.minX + translation.width, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + translation.height, bounds.minY), bounds.maxY - rect.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: rect.size)
    }

    static func resized(
        _ rect: CGRect,
        handle: ScreenshotResizeHandle,
        to point: CGPoint,
        inside bounds: CGRect,
        minimumSize: CGSize
    ) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .topLeft, .left, .bottomLeft:
            minX = min(max(point.x, bounds.minX), maxX - minimumSize.width)
        default: break
        }
        switch handle {
        case .topRight, .right, .bottomRight:
            maxX = max(min(point.x, bounds.maxX), minX + minimumSize.width)
        default: break
        }
        switch handle {
        case .bottomLeft, .bottom, .bottomRight:
            minY = min(max(point.y, bounds.minY), maxY - minimumSize.height)
        default: break
        }
        switch handle {
        case .topLeft, .top, .topRight:
            maxY = max(min(point.y, bounds.maxY), minY + minimumSize.height)
        default: break
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct ScreenshotSelectionModel {
    private enum DragOperation {
        case creating(anchor: CGPoint)
        case moving(anchor: CGPoint, originalRect: CGRect)
        case resizing(handle: ScreenshotResizeHandle, originalRect: CGRect)
    }

    static let minimumSize = CGSize(width: 24, height: 24)
    static let handleHitRadius: CGFloat = 10

    private(set) var rect: CGRect?
    private(set) var phase: ScreenshotSelectionPhase
    private var dragOperation: DragOperation?

    init(rect: CGRect? = nil) {
        self.rect = rect
        self.phase = rect == nil ? .selecting : .adjusting
    }

    mutating func begin(at point: CGPoint, bounds: CGRect) {
        guard phase != .locked else { return }

        if let rect,
           let handle = handle(at: point, in: rect, hitRadius: Self.handleHitRadius) {
            dragOperation = .resizing(handle: handle, originalRect: rect)
            return
        }
        if let rect, rect.contains(point) {
            dragOperation = .moving(anchor: point, originalRect: rect)
            return
        }

        let point = clamped(point, to: bounds)
        rect = CGRect(origin: point, size: .zero)
        phase = .selecting
        dragOperation = .creating(anchor: point)
    }

    mutating func update(to point: CGPoint, bounds: CGRect) {
        guard phase != .locked, let dragOperation else { return }

        switch dragOperation {
        case .creating(let anchor):
            let point = clamped(point, to: bounds)
            rect = CGRect(
                x: min(anchor.x, point.x),
                y: min(anchor.y, point.y),
                width: abs(point.x - anchor.x),
                height: abs(point.y - anchor.y)
            )
        case .moving(let anchor, let originalRect):
            rect = ScreenshotSelectionGeometry.moved(
                originalRect,
                by: CGSize(width: point.x - anchor.x, height: point.y - anchor.y),
                inside: bounds
            )
        case .resizing(let handle, let originalRect):
            rect = ScreenshotSelectionGeometry.resized(
                originalRect,
                handle: handle,
                to: point,
                inside: bounds,
                minimumSize: Self.minimumSize
            )
        }
    }

    mutating func end(at point: CGPoint, bounds: CGRect) {
        guard phase != .locked, dragOperation != nil else { return }
        update(to: point, bounds: bounds)
        dragOperation = nil

        guard let rect,
              rect.width >= Self.minimumSize.width,
              rect.height >= Self.minimumSize.height else {
            self.rect = nil
            phase = .selecting
            return
        }
        phase = .adjusting
    }

    mutating func lock() -> CGRect? {
        guard phase == .adjusting, let rect else { return nil }
        phase = .locked
        dragOperation = nil
        return rect
    }

    mutating func unlockAfterFailedCrop() {
        guard phase == .locked, rect != nil else { return }
        phase = .adjusting
    }

    func handle(at point: CGPoint, in rect: CGRect? = nil, hitRadius: CGFloat) -> ScreenshotResizeHandle? {
        guard let rect = rect ?? self.rect else { return nil }
        return ScreenshotResizeHandle.allCases.first { handle in
            let center = handle.center(in: rect)
            return hypot(point.x - center.x, point.y - center.y) <= hitRadius
        }
    }

    private func clamped(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }
}
