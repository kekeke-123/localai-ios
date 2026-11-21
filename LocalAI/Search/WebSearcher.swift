import Foundation

struct WebResult: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var url: String
    var snippet: String
}

enum SearchError: LocalizedError {
    case badResponse(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "搜索服务返回了 \(code)"
        case .empty: return "没有搜到结果"
        }
    }
}

enum WebSearcher {

    static func search(_ query: String, provider: SearchProvider) async throws -> [WebResult] {
        switch provider {
        case .bing:
            return try await bing(query)
        case .duckduckgo:
            return try await duckduckgo(query)
        }
    }

    // MARK: - 必应

    private static func bing(_ query: String) async throws -> [WebResult] {
        var components = URLComponents(string: "https://cn.bing.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "setlang", value: "zh-Hans")
        ]
        guard let url = components?.url else { throw SearchError.empty }
        let html = try await fetchHTML(url)

        let blocks = matches(in: html, pattern: "<li class=\"b_algo\".*?</li>")
        var results: [WebResult] = []
        for block in blocks {
            guard let titleMatch = firstMatch(in: block,
                                              pattern: "<h2[^>]*>.*?<a[^>]*href=\"(https?://[^\"]+)\"[^>]*>(.*?)</a>"),
                  titleMatch.count >= 3 else { continue }
            let url = titleMatch[1]
            let title = clean(titleMatch[2])
            guard !title.isEmpty else { continue }

            var snippet = ""
            if let p = firstMatch(in: block, pattern: "<p[^>]*>(.*?)</p>"), p.count >= 2 {
                snippet = clean(p[1])
            }
            results.append(WebResult(title: title, url: url, snippet: String(snippet.prefix(200))))
        }
        if results.isEmpty { throw SearchError.empty }
        return Array(results.prefix(6))
    }

    // MARK: - DuckDuckGo

    private static func duckduckgo(_ query: String) async throws -> [WebResult] {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { throw SearchError.empty }
        let html = try await fetchHTML(url)

        let list = allMatches(in: html,
                              pattern: "<a[^>]*class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>")
        let snippets = allMatches(in: html,
                                  pattern: "<a[^>]*class=\"result__snippet\"[^>]*>(.*?)</a>")

        var results: [WebResult] = []
        for (i, item) in list.enumerated() {
            guard item.count >= 3 else { continue }
            let url = decodeDuckURL(item[1])
            let title = clean(item[2])
            guard !title.isEmpty, url.hasPrefix("http") else { continue }
            var snippet = ""
            if i < snippets.count, snippets[i].count >= 2 {
                snippet = clean(snippets[i][1])
            }
            results.append(WebResult(title: title, url: url, snippet: String(snippet.prefix(200))))
        }
        if results.isEmpty { throw SearchError.empty }
        return Array(results.prefix(6))
    }

    private static func decodeDuckURL(_ raw: String) -> String {
        guard let components = URLComponents(string: raw.hasPrefix("//") ? "https:" + raw : raw),
              let value = components.queryItems?.first(where: { $0.name == "uddg" })?.value
        else { return raw }
        return value
    }

    // MARK: - 网络

    private static func fetchHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw SearchError.badResponse(http.statusCode)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - 文本处理

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    /// 返回每条匹配里的所有捕获组
    private static func allMatches(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).map { match in
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                if let range = Range(r, in: text) {
                    groups.append(String(text[range]))
                } else {
                    groups.append("")
                }
            }
            return groups
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        allMatches(in: text, pattern: pattern).first
    }

    private static func clean(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&#x27;": "'", "&nbsp;": " ", "&middot;": "·",
            "&hellip;": "…", "&mdash;": "—", "&ndash;": "–"
        ]
        for (key, value) in entities {
            text = text.replacingOccurrences(of: key, with: value)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
