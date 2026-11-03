import Foundation
import PrivateKeyboardCore

let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("usage: nextwords-builder <dictionary.zh-en.bin> <ngram.tsv> <out.json>\n", stderr)
    exit(2)
}
let dictionary = try ZhEnDictionary(url: URL(fileURLWithPath: args[1]))
var traditionalToSimplified: [String: String] = [:]
traditionalToSimplified.reserveCapacity(dictionary.count)
for id in 0..<UInt32(dictionary.count) {
    let entry = try dictionary.entry(id: id)
    if entry.traditional != entry.simplified {
        traditionalToSimplified[entry.traditional] = entry.simplified
    }
}
func normalize(_ word: String) -> String {
    traditionalToSimplified[word] ?? word
}

var nexts: [String: [String: UInt32]] = [:]
let text = try String(contentsOfFile: args[2], encoding: .utf8)
for line in text.split(separator: "\n") {
    if line.isEmpty || line.hasPrefix("#") { continue }
    let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 4, f[0] == "bi", let count = UInt32(f[3]) else { continue }
    let context = normalize(f[1])
    let token = normalize(f[2])
    guard !context.isEmpty, !token.isEmpty else { continue }
    nexts[context, default: [:]][token, default: 0] &+= count
}
var output: [String: [String]] = [:]
for (context, tokens) in nexts {
    let top = tokens.sorted {
        $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }.prefix(8).map(\.key)
    if !top.isEmpty { output[context] = top }
}
let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .withoutEscapingSlashes])
try data.write(to: URL(fileURLWithPath: args[3]))
print("contexts: \(output.count)")
