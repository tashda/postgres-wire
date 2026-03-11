import Foundation

/// Internal CSV parser for bulk copy operations.
internal struct CSVParser {
    let delimiter: Character
    let nullString: String?
    let quote: Character

    init(delimiter: Character, nullString: String?, quote: Character) {
        self.delimiter = delimiter
        self.nullString = nullString
        self.quote = quote
    }

    func parseLine(_ line: String) -> [String?] {
        var result: [String?] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let ch = iterator.next() {
            if ch == quote {
                if inQuotes {
                    if let next = iterator.next() {
                        if next == quote { current.append(quote) }
                        else {
                            inQuotes = false
                            if next == delimiter { result.append(tokenToField(current)); current = "" }
                            else { current.append(next) }
                        }
                    } else { inQuotes = false }
                } else { inQuotes = true }
            } else if ch == delimiter && !inQuotes {
                result.append(tokenToField(current))
                current = ""
            } else { current.append(ch) }
        }
        result.append(tokenToField(current))
        return result
    }

    private func tokenToField(_ token: String) -> String? {
        if let nullString, token == nullString { return nil }
        return token
    }
}
