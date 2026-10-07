import Foundation

/// Lightweight fuzzy matcher for app titles and menu paths.
enum FuzzySearch {
    struct Match {
        let score: Int
        let indices: [Int]
    }

    /// Returns a match score (higher is better) or `nil` if no match.
    static func match(query: String, in text: String) -> Match? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return Match(score: 0, indices: [])
        }

        let queryChars = Array(q.lowercased())
        let textChars = Array(text.lowercased())
        guard !textChars.isEmpty else { return nil }

        var indices: [Int] = []
        indices.reserveCapacity(queryChars.count)

        var ti = 0
        for qc in queryChars {
            var found = false
            while ti < textChars.count {
                if textChars[ti] == qc {
                    indices.append(ti)
                    ti += 1
                    found = true
                    break
                }
                ti += 1
            }
            if !found { return nil }
        }

        // Prefer earlier, denser, prefix-ish matches.
        var score = 1000 - (indices.first ?? 0) * 2
        if let first = indices.first, first == 0 { score += 200 }

        for i in 1..<indices.count {
            let gap = indices[i] - indices[i - 1] - 1
            score += max(0, 40 - gap * 4)
        }

        // Bonus when query is a contiguous substring.
        if text.lowercased().contains(q.lowercased()) {
            score += 150
            if text.lowercased().hasPrefix(q.lowercased()) {
                score += 100
            }
        }

        // Shorter labels win ties.
        score -= text.count

        return Match(score: score, indices: indices)
    }

    static func ranked<T>(
        query: String,
        items: [T],
        key: (T) -> String,
        limit: Int = 50
    ) -> [T] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return Array(items.prefix(limit))
        }

        return items
            .compactMap { item -> (T, Int)? in
                guard let match = match(query: q, in: key(item)) else { return nil }
                return (item, match.score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
