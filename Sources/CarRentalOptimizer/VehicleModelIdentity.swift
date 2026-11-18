import Foundation

enum VehicleModelIdentity {
    private static let brands: [(String, String)] = [
        ("上汽通用雪佛兰", "雪佛兰"), ("上汽通用别克", "别克"),
        ("一汽奥迪", "奥迪"), ("上汽奥迪", "奥迪"), ("华晨宝马", "宝马"),
        ("北京奔驰", "奔驰"), ("宝马(进口)", "宝马"), ("奔驰(进口)", "奔驰"),
        ("零跑汽车", "零跑"), ("沃尔沃亚太", "沃尔沃"),
        ("小鹏汽车", "小鹏"), ("理想汽车", "理想"), ("深蓝汽车", "深蓝"),
        ("长安深蓝", "深蓝"), ("广汽传祺", "传祺"), ("广汽乘用车", "传祺"),
        ("吉利汽车", "吉利"), ("吉利银河", "吉利"),
        ("方程豹", "方程豹"), ("沃尔沃", "沃尔沃"), ("阿维塔", "阿维塔"),
        ("坦克", "坦克"), ("腾势", "腾势"), ("传祺", "传祺"), ("深蓝", "深蓝"),
        ("享界", "享界"), ("尚界", "尚界"), ("问界", "问界"), ("智界", "智界"),
        ("小米", "小米"), ("岚图", "岚图"), ("零跑", "零跑"),
        ("北京越野", "北京"), ("上汽大众", "大众"), ("一汽大众", "大众"),
        ("广汽丰田", "丰田"), ("一汽丰田", "丰田"), ("东风日产", "日产"),
        ("广汽本田", "本田"), ("东风本田", "本田"),
        ("雪佛兰", "雪佛兰"), ("比亚迪", "比亚迪"), ("大众", "大众"),
        ("日产", "日产"), ("丰田", "丰田"), ("北京", "北京"),
        ("本田", "本田"), ("别克", "别克"), ("奇瑞", "奇瑞"),
        ("哈弗", "哈弗"), ("领克", "领克"), ("吉利", "吉利"),
        ("福特", "福特"), ("现代", "现代"), ("小鹏", "小鹏"),
        ("理想", "理想"), ("蔚来", "蔚来"), ("宝马", "宝马"),
        ("奔驰", "奔驰"), ("奥迪", "奥迪"), ("五菱", "五菱")
    ]

    static func compact(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: #"[\s·_\-]"#, with: "", options: .regularExpression)
    }

    private static func split(_ name: String) -> (brand: String?, model: String) {
        var model = name.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")").trimmingCharacters(in: .whitespacesAndNewlines)
        var brand: String?
        for _ in 0..<2 {
            guard let match = brands.first(where: { model.hasPrefix($0.0) && (brand == nil || brand == $0.1) }) else { break }
            brand = match.1
            model = String(model.dropFirst(match.0.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (brand, model)
    }

    static func cacheKey(_ name: String) -> String {
        let identity = split(name)
        return compact((identity.brand ?? "") + identity.model)
    }

    static func lookupQueries(_ query: String) -> [String] {
        let model = split(query).model
        var seen = Set<String>()
        return [query.replacingOccurrences(of: " ", with: ""), query, model]
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func isEnergyVariant(_ title: String, of query: String) -> Bool {
        let left = split(title), right = split(query)
        if let a = left.brand, let b = right.brand, a != b { return false }
        func base(_ value: String) -> String {
            var key = compact(value)
            for suffix in ["增程版", "纯电版", "新能源", "增程", "纯电", "dmi", "dmp", "ev"] where key.hasSuffix(suffix) {
                key = String(key.dropLast(suffix.count))
                break
            }
            return key
        }
        let titleBase = base(left.model), queryBase = base(right.model)
        return !titleBase.isEmpty && titleBase == queryBase && titleBase != compact(left.model)
    }

    static func matches(_ title: String, query: String) -> Bool {
        let left = split(title), right = split(query)
        if let lhs = left.brand, let rhs = right.brand, lhs != rhs { return false }
        let lhs = compact(left.model), rhs = compact(right.model)
        // Exact model identity preserves L / PLUS / Pro / EV / 新能源 distinctions.
        return !lhs.isEmpty && !rhs.isEmpty && lhs == rhs
    }
}
