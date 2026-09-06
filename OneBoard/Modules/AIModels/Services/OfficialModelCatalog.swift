import Foundation

/// 只读取 Codex 自己缓存的目录，不混入第三方模型或静态猜测的型号。
enum OfficialModelCatalog {
    static func codexModels(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".codex/models_cache.json")) else { return [] }
        return parse(data)
    }
    static func parse(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return [] }
        return Array(Set(models.compactMap { entry in
            guard entry["visibility"] as? String != "hide" else { return nil }
            return (entry["slug"] ?? entry["id"]) as? String
        }.filter { !$0.isEmpty })).sorted()
    }
}
