import AppKit

enum CalloutGeometry {
    static func textRect(for target: CGRect, canvas: CGSize, fontSize: CGFloat) -> CGRect {
        let width = min(max(120, fontSize * 10), max(40, canvas.width))
        let height = max(30, fontSize * 1.8)
        let below = target.maxY + 36
        let y = below + height <= canvas.height ? below : max(0, target.minY - height - 36)
        return CGRect(x: min(max(0, target.midX), max(0, canvas.width - width)), y: y, width: width, height: height)
    }

    /// 从文字框边缘出发，箭头指向被标注框的边缘。
    static func connector(target: CGRect, label: CGRect) -> (start: CGPoint, end: CGPoint) {
        func edge(of rect: CGRect, toward point: CGPoint) -> CGPoint {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let dx = point.x - center.x, dy = point.y - center.y
            let scale = min(dx == 0 ? CGFloat.infinity : rect.width / 2 / abs(dx),
                            dy == 0 ? CGFloat.infinity : rect.height / 2 / abs(dy))
            guard scale.isFinite else { return center }
            return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
        }
        return (edge(of: label, toward: CGPoint(x: target.midX, y: target.midY)),
                edge(of: target, toward: CGPoint(x: label.midX, y: label.midY)))
    }
}
