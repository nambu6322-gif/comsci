import Foundation
struct TextModel {
    enum LoadError: Error { case missingResource, invalidModel }
    let vocabulary: [String: Int]; let idf: [Double]; let weights: [Double]; let bias: Double; let threshold: Double
    init(filename: String) throws {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else { throw LoadError.missingResource }
        try self.init(data: Data(contentsOf: url))
    }
    init(data: Data) throws {
        guard let m = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let words = m["vocab"] as? [String], let idf = m["idf"] as? [Double], let weights = m["weights"] as? [Double],
              let bias = m["bias"] as? Double, let threshold = m["threshold"] as? Double,
              !words.isEmpty, Set(words).count == words.count, idf.count == words.count, weights.count == words.count,
              idf.allSatisfy({ $0.isFinite && $0 > 0 }), weights.allSatisfy({ $0.isFinite }), bias.isFinite,
              threshold.isFinite, threshold > 0, threshold < 1 else { throw LoadError.invalidModel }
        vocabulary = Dictionary(uniqueKeysWithValues: words.enumerated().map { ($1, $0) })
        self.idf = idf; self.weights = weights; self.bias = bias; self.threshold = threshold
    }
    func selectedClaims(in text: String) -> [String] {
        // Match the server's sentence boundaries. Score claims, not the full
        // screen mixed with likes, comments, sharing controls and account text.
        let expression = try! NSRegularExpression(pattern: "\\n+|(?<=[.!?。！？])\\s+")
        let ns = text as NSString
        let separated = expression.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "\n")
        let lines = separated.components(separatedBy: "\n").prefix(60).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var candidates: [String] = []
        let controls: Set<String> = ["좋아요", "공유", "팔로우", "댓글", "원본 오디오", "구독", "Subscribe", "Share"]
        // Article lines and video captions can wrap one sentence across rows.
        for i in lines.indices where !lines[i].isEmpty && !controls.contains(lines[i]) {
            var combined = lines[i]
            guard combined.range(of: "[.!?。！？]$", options: .regularExpression) == nil else { continue }
            for j in (i + 1)..<min(i + 3, lines.endIndex) {
                guard !lines[j].isEmpty, !controls.contains(lines[j]), combined.count + lines[j].count < 600 else { break }
                combined += " " + lines[j]
                if combined.range(of: "[.!?。！？]$", options: .regularExpression) != nil { candidates.append(combined); break }
            }
        }
        candidates.append(contentsOf: lines)
        var seen = Set<String>()
        return candidates.compactMap { claim -> String? in
            guard claim.count >= 5, seen.insert(claim).inserted, score(claim) >= threshold else { return nil }
            return claim
        }.prefix(3).map { $0 }
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
