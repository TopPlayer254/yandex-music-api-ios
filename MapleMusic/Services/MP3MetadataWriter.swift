import Foundation

enum MP3MetadataWriter {
    static func taggedCopy(
        of source: URL,
        title: String,
        artist: String,
        album: String
    ) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("maple-upload-\(UUID().uuidString).mp3")
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw MusicServiceError.offlineUnavailable
        }

        do {
            let input = try FileHandle(forReadingFrom: source)
            let output = try FileHandle(forWritingTo: destination)
            defer {
                try? input.close()
                try? output.close()
            }

            let leadingBytes = try input.read(upToCount: 10) ?? Data()
            let audioOffset = existingTagLength(in: leadingBytes)
            try input.seek(toOffset: UInt64(audioOffset))
            try output.write(contentsOf: tag(title: title, artist: artist, album: album))

            while let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func metadata(in data: Data) -> [String: String] {
        guard data.count >= 10,
              data.prefix(3) == Data("ID3".utf8),
              data[3] == 4
        else { return [:] }
        let tagEnd = min(10 + synchsafeValue(data[6 ... 9]), data.count)
        var cursor = 10
        var result: [String: String] = [:]
        while cursor + 10 <= tagEnd {
            let identifierData = data[cursor ..< cursor + 4]
            guard let identifier = String(data: identifierData, encoding: .ascii),
                  identifier.allSatisfy({ $0.isASCII && !$0.isWhitespace })
            else { break }
            let size = synchsafeValue(data[cursor + 4 ... cursor + 7])
            cursor += 10
            guard size > 1, cursor + size <= tagEnd else { break }
            let payload = data[cursor ..< cursor + size]
            if payload.first == 3,
               let value = String(data: payload.dropFirst(), encoding: .utf8) {
                result[identifier] = value
            }
            cursor += size
        }
        return result
    }

    private static func tag(title: String, artist: String, album: String) -> Data {
        var frames = Data()
        frames.append(frame(identifier: "TIT2", value: title))
        frames.append(frame(identifier: "TPE1", value: artist))
        if !album.isEmpty { frames.append(frame(identifier: "TALB", value: album)) }

        var result = Data("ID3".utf8)
        result.append(contentsOf: [4, 0, 0])
        result.append(contentsOf: synchsafeBytes(frames.count))
        result.append(frames)
        return result
    }

    private static func frame(identifier: String, value: String) -> Data {
        var payload = Data([3])
        payload.append(Data(value.utf8))
        var result = Data(identifier.utf8)
        result.append(contentsOf: synchsafeBytes(payload.count))
        result.append(contentsOf: [0, 0])
        result.append(payload)
        return result
    }

    private static func existingTagLength(in header: Data) -> Int {
        guard header.count == 10, header.prefix(3) == Data("ID3".utf8) else { return 0 }
        let bodyLength = synchsafeValue(header[6 ... 9])
        let hasFooter = header[5] & 0x10 != 0
        return 10 + bodyLength + (hasFooter ? 10 : 0)
    }

    private static func synchsafeBytes(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 21) & 0x7f),
            UInt8((value >> 14) & 0x7f),
            UInt8((value >> 7) & 0x7f),
            UInt8(value & 0x7f)
        ]
    }

    private static func synchsafeValue<Bytes: Collection>(_ bytes: Bytes) -> Int where Bytes.Element == UInt8 {
        bytes.reduce(0) { ($0 << 7) | Int($1 & 0x7f) }
    }
}
