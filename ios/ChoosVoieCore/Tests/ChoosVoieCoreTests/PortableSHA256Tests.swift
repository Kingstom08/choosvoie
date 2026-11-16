import XCTest
import ChoosVoieCore

/// SPEC §7 H1–H5: FIPS 180-2 / well-known SHA-256 vectors; extra block-boundary vectors
/// were computed independently with Python hashlib.
final class PortableSHA256Tests: XCTestCase {

    func test_H1_emptyString() {
        let d = PortableSHA256.hash("")
        XCTAssertEqual(d.hexString, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(d.bytes.count, 32)
        XCTAssertEqual(PortableSHA256.hash([UInt8]()), d)
    }

    func test_H2_abc() {
        XCTAssertEqual(PortableSHA256.hash("abc").hexString,
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(PortableSHA256.hash([0x61, 0x62, 0x63]).hexString,
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func test_H3_twoBlockMessage448Bits() {
        XCTAssertEqual(PortableSHA256.hash("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq").hexString,
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func test_H4_oneMillionA() {
        let s = String(repeating: "a", count: 1_000_000)
        XCTAssertEqual(PortableSHA256.hash(s).hexString,
                       "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    func test_H5_quickBrownFox() {
        XCTAssertEqual(PortableSHA256.hash("The quick brown fox jumps over the lazy dog").hexString,
                       "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")
    }

    /// Padding edge cases: 55/56 bytes (length field fits / spills), 63/64/65 (block boundary), 119/120.
    func test_extra_blockBoundaryLengths() {
        let vectors: [(Int, String)] = [
            (55, "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
            (56, "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
            (63, "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"),
            (64, "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"),
            (65, "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"),
            (119, "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb"),
            (120, "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c"),
        ]
        for (n, hex) in vectors {
            XCTAssertEqual(PortableSHA256.hash([UInt8](repeating: 0x61, count: n)).hexString, hex, "length \(n)")
        }
    }

    func test_extra_stringIsHashedAsUTF8() {
        let s = "çğİ\u{1F399}"
        XCTAssertEqual(PortableSHA256.hash(s), PortableSHA256.hash(Array(s.utf8)))
        XCTAssertEqual(PortableSHA256.hash(s).hexString,
                       "ae30f48726f657773c4985b742953d118402f0fdef7e0da5e76bc2efac31dfc8")
    }

    func test_extra_hexStringIsLowercase64Chars() {
        let hex = PortableSHA256.hash("abc").hexString
        XCTAssertEqual(hex.count, 64)
        XCTAssertEqual(hex, hex.lowercased())
    }
}
