import Foundation
import CryptoKit

enum Curve25519Keys {
    static func makePrivateKey() -> String {
        let key = Curve25519.Signing.PrivateKey()
        return key.rawRepresentation.base64EncodedString()
    }
}
