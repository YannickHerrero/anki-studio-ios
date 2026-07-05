import Foundation

/// Minimal ZIP writer using the STORE method (no compression). Enough to
/// produce a valid `.apkg` — Anki reads standard zips and tolerates stored
/// entries — with no third-party dependency. Streams entries to a FileHandle
/// so large media never has to sit fully in memory at once.
final class ZipWriter {
    private struct Entry {
        let name: [UInt8]
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private let handle: FileHandle
    private var entries: [Entry] = []
    private var offset: UInt32 = 0

    init(url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func addFile(name: String, data: Data) throws {
        let nameBytes = Array(name.utf8)
        let crc = CRC32.checksum(data)
        let size = UInt32(data.count)

        var header = Data()
        header.appendLE32(0x0403_4b50)   // local file header signature
        header.appendLE16(20)            // version needed to extract
        header.appendLE16(0)             // general purpose flags
        header.appendLE16(0)             // compression method = store
        header.appendLE16(0)             // last mod time
        header.appendLE16(0)             // last mod date
        header.appendLE32(crc)
        header.appendLE32(size)          // compressed size
        header.appendLE32(size)          // uncompressed size
        header.appendLE16(UInt16(nameBytes.count))
        header.appendLE16(0)             // extra field length
        header.append(contentsOf: nameBytes)

        try handle.write(contentsOf: header)
        try handle.write(contentsOf: data)

        entries.append(Entry(name: nameBytes, crc: crc, size: size, offset: offset))
        offset += UInt32(header.count) + size
    }

    func addFile(name: String, fileURL: URL) throws {
        try addFile(name: name, data: try Data(contentsOf: fileURL))
    }

    /// Write the central directory + end-of-central-directory record and close.
    func finish() throws {
        let cdStart = offset
        var central = Data()
        for e in entries {
            central.appendLE32(0x0201_4b50)  // central directory header signature
            central.appendLE16(20)           // version made by
            central.appendLE16(20)           // version needed
            central.appendLE16(0)            // flags
            central.appendLE16(0)            // method
            central.appendLE16(0)            // time
            central.appendLE16(0)            // date
            central.appendLE32(e.crc)
            central.appendLE32(e.size)       // compressed size
            central.appendLE32(e.size)       // uncompressed size
            central.appendLE16(UInt16(e.name.count))
            central.appendLE16(0)            // extra length
            central.appendLE16(0)            // comment length
            central.appendLE16(0)            // disk number start
            central.appendLE16(0)            // internal attributes
            central.appendLE32(0)            // external attributes
            central.appendLE32(e.offset)     // relative offset of local header
            central.append(contentsOf: e.name)
        }
        try handle.write(contentsOf: central)

        var eocd = Data()
        eocd.appendLE32(0x0605_4b50)         // EOCD signature
        eocd.appendLE16(0)                   // disk number
        eocd.appendLE16(0)                   // disk with central directory
        eocd.appendLE16(UInt16(entries.count))
        eocd.appendLE16(UInt16(entries.count))
        eocd.appendLE32(UInt32(central.count))
        eocd.appendLE32(cdStart)
        eocd.appendLE16(0)                   // comment length
        try handle.write(contentsOf: eocd)

        try handle.close()
    }
}

private extension Data {
    mutating func appendLE16(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
    }

    mutating func appendLE32(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
}
