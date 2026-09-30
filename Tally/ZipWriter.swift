import Foundation

/// Minimal zip writer (stored, uncompressed). Enough to package an .xlsx without a dependency.
struct ZipWriter {
    private var body = Data()
    private var directory = Data()
    private var count: UInt16 = 0
    private let dosTime: UInt16
    private let dosDate: UInt16

    init(date now: Date = Date()) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        dosTime = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        dosDate = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
    }

    mutating func add(_ name: String, _ content: Data) {
        let nameBytes = Data(name.utf8)
        let crc = CRC32.checksum(content)
        let size = UInt32(content.count)
        let offset = UInt32(body.count)

        // Local file header
        body.le32(0x04034b50)
        body.le16(20)           // version needed
        body.le16(0)            // flags
        body.le16(0)            // method: stored
        body.le16(dosTime)
        body.le16(dosDate)
        body.le32(crc)
        body.le32(size)
        body.le32(size)
        body.le16(UInt16(nameBytes.count))
        body.le16(0)            // extra length
        body.append(nameBytes)
        body.append(content)

        // Central directory entry
        directory.le32(0x02014b50)
        directory.le16(20)      // version made by
        directory.le16(20)      // version needed
        directory.le16(0)
        directory.le16(0)
        directory.le16(dosTime)
        directory.le16(dosDate)
        directory.le32(crc)
        directory.le32(size)
        directory.le32(size)
        directory.le16(UInt16(nameBytes.count))
        directory.le16(0)       // extra
        directory.le16(0)       // comment
        directory.le16(0)       // disk
        directory.le16(0)       // internal attributes
        directory.le32(0)       // external attributes
        directory.le32(offset)
        directory.append(nameBytes)
        count += 1
    }

    func finish() -> Data {
        var out = body
        out.append(directory)
        out.le32(0x06054b50)
        out.le16(0)
        out.le16(0)
        out.le16(count)
        out.le16(count)
        out.le32(UInt32(directory.count))
        out.le32(UInt32(body.count))
        out.le16(0)
        return out
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data {
            c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFFFFFF
    }
}

extension Data {
    mutating func le16(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8(v >> 8))
    }

    mutating func le32(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
}
