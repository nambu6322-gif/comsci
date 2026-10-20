import Foundation
struct TextModel {
    let vocabulary: [String: Int]; let idf: [Double]; let weights: [Double]; let bias: Double; let threshold: Double
    init(filename: String) throws {
        let url = Bundle.main.url(forResource: filename, withExtension: "json")!
        let m = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let words = m["vocab"] as! [String]
        vocabulary = Dictionary(uniqueKeysWithValues: words.enumerated().map { ($1, $0) })
        idf = m["idf"] as! [Double]; weights = m["weights"] as! [Double]; bias = m["bias"] as! Double; threshold = m["threshold"] as! Double
    }
    func score(_ text: String) -> Double {
        let stop = Set("그리고 그러나 그래서 하지만 또한 또는 저는 나는 우리가 여러분 정말 그냥 조금 너무 매우 이것 그것 저것 있는 것은 하는 위해 에서 으로 입니다 합니다 the a an and or but of to in is are was were this that it".split(separator: " ").map(String.init))
        let normalized = text.precomposedStringWithCompatibilityMapping.lowercased()
        let expression = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+")
        let ns = normalized as NSString
        let words = expression.matches(in: normalized, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }.filter { $0.count > 1 && !stop.contains($0) }
        var counts: [Int: Int] = [:]
        for word in words {
            if let i = vocabulary[word] { counts[i, default: 0] += 1 }
            if word.range(of: "[가-힣]", options: .regularExpression) != nil {
                let letters = Array(word)
                for i in 0..<(letters.count - 1) { if let k = vocabulary["#" + String(letters[i...i+1])] { counts[k, default: 0] += 1 } }
            }
        }
        var norm = 0.0; var sum = 0.0
        for (i, n) in counts { let value = (1 + log(Double(n))) * idf[i]; norm += value * value; sum += value * weights[i] }
        return 1 / (1 + exp(-max(-35, min(35, bias + sum / (sqrt(norm) == 0 ? 1 : sqrt(norm))))))
    }
}
