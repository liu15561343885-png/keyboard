import Foundation
import PrivateKeyboardCore

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage: ngram-builder <ngram.tsv> <output-directory>\n", stderr)
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var bigrams: [BigramBuildEntry] = []
var trigrams: [TrigramBuildEntry] = []
let text = try String(contentsOf: input, encoding: .utf8)
for line in text.split(separator: "\n") {
    if line.isEmpty || line.hasPrefix("#") { continue }
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    if fields.count >= 4, fields[0] == "bi", let count = UInt32(fields[3]) {
        bigrams.append(BigramBuildEntry(context: fields[1], token: fields[2], count: count))
    } else if fields.count >= 5, fields[0] == "tri", let count = UInt32(fields[4]) {
        trigrams.append(TrigramBuildEntry(first: fields[1], second: fields[2], token: fields[3], count: count))
    }
}
try NGramBinaryWriter.writeBigrams(bigrams, to: output.appendingPathComponent("lm.bigram.bin"))
try NGramBinaryWriter.writeTrigrams(trigrams, to: output.appendingPathComponent("lm.trigram.bin"))
print("bigrams: \(bigrams.count), trigrams: \(trigrams.count)")
