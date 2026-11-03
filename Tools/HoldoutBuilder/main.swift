import Foundation
import PrivateKeyboardCore

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage: holdout-builder <dictionary.zh-en.bin> <out.tsv>\n", stderr)
    exit(2)
}
let dictionary = try ZhEnDictionary(url: URL(fileURLWithPath: args[1]))
var rows: [(UInt32, String, String)] = []
rows.reserveCapacity(dictionary.count)
for id in 0..<UInt32(dictionary.count) {
    let entry = try dictionary.entry(id: id)
    let word = entry.simplified
    guard (1...4).contains(word.count),
          !entry.pinyinKey.isEmpty,
          word.unicodeScalars.allSatisfy({ (0x3400...0x9FFF).contains($0.value) })
    else { continue }
    rows.append((entry.frequency, word, entry.pinyinKey))
}
rows.sort { $0.0 > $1.0 }
// Deterministic spaced sample, not the top-frequency block used during
// development. This is a lexical holdout, not a human-authored blind set.
var picked: [(String, String)] = []
var seen = Set<String>()
var index = 0
while picked.count < 500, index < rows.count {
    let row = rows[index]
    if seen.insert(row.1).inserted { picked.append((row.1, row.2)) }
    index += max(1, rows.count / 5000)
}
let out = picked.map { "\($0.1)\t\($0.0)" }.joined(separator: "\n") + "\n"
try out.write(toFile: args[2], atomically: true, encoding: .utf8)
print("holdout: \(picked.count) entries, dictionary rows: \(rows.count)")
