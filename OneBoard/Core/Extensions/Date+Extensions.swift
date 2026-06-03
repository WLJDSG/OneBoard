import Foundation

extension Date {
    /// 相对时间描述（例如 "2 分钟前"、"1 小时前"）
    var timeAgoDescription: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 0 { return "刚刚" }

        let minute: TimeInterval = 60
        let hour: TimeInterval = 3600
        let day: TimeInterval = 86400
        let week: TimeInterval = 604800

        switch interval {
        case ..<minute:
            return "刚刚"
        case ..<hour:
            let minutes = Int(interval / minute)
            return "\(minutes) 分钟前"
        case ..<day:
            let hours = Int(interval / hour)
            return "\(hours) 小时前"
        case ..<week:
            let days = Int(interval / day)
            return "\(days) 天前"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd"
            return formatter.string(from: self)
        }
    }

    /// 简短时间格式
    var shortTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    /// 简短日期格式
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: self)
    }
}