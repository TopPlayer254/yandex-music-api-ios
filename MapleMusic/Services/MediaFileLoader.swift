import CommonCrypto
import Foundation

enum MediaFileLoader {
    static func fileExtension(for asset: PlaybackAsset) -> String {
        switch asset.codec.lowercased() {
        case "flac": return "flac"
        // Yandex labels these codecs as AAC, but get-file-info returns them in
        // an ISO Base Media container. The m4a extension avoids AVPlayer -50.
        case "aac", "he-aac", "alac", "flac-mp4", "aac-mp4", "he-aac-mp4": return "m4a"
        case "mp3": return "mp3"
        default: return "wav"
        }
    }

    // encraw is the authorized API's AES-CTR transport. Its key comes from that
    // same account's get-file-info response; no key extraction from another app.
    static func download(_ asset: PlaybackAsset, to destination: URL) async throws {
        guard asset.transport != "hls", asset.url.pathExtension != "m3u8" else {
            throw MusicServiceError.message("Офлайн-загрузка HLS недоступна в этом режиме API. Выберите File info в настройках.")
        }
        let source: URL
        let temporary: Bool
        if asset.url.isFileURL { source = asset.url; temporary = false }
        else {
            guard asset.url.scheme == "https" else { throw MusicServiceError.invalidResponse }
            let (url, response) = try await URLSession.shared.download(from: asset.url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: url)
                throw MusicServiceError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            source = url; temporary = true
        }
        defer { if temporary { try? FileManager.default.removeItem(at: source) } }
        try Task.checkCancellation()
        do {
            if let key = asset.decryptionKey { try decrypt(source: source, destination: destination, hexKey: key) }
            else { try FileManager.default.copyItem(at: source, to: destination) }
            try validatePlayableFile(at: destination, asset: asset)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func validatePlayableFile(at url: URL, asset: PlaybackAsset) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 32), data.count >= 4 else {
            throw MusicServiceError.invalidResponse
        }
        let bytes = [UInt8](data)
        let codec = asset.codec.lowercased()
        let isISOBaseMedia = data.count >= 8 && String(decoding: bytes[4 ..< 8], as: UTF8.self) == "ftyp"
        let isADTS = bytes[0] == 0xFF && (bytes[1] & 0xF6) == 0xF0
        let isMP3 = String(decoding: bytes.prefix(3), as: UTF8.self) == "ID3"
            || (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0)
        let isFLAC = String(decoding: bytes.prefix(4), as: UTF8.self) == "fLaC"
        let isWAV = data.count >= 12
            && String(decoding: bytes.prefix(4), as: UTF8.self) == "RIFF"
            && String(decoding: bytes[8 ..< 12], as: UTF8.self) == "WAVE"

        let valid: Bool
        switch codec {
        case "flac": valid = isFLAC
        case "aac", "he-aac": valid = isADTS || isISOBaseMedia
        case "mp3": valid = isMP3
        case "alac", "flac-mp4", "aac-mp4", "he-aac-mp4": valid = isISOBaseMedia
        case "linear pcm", "wav": valid = isWAV
        default: valid = !data.isEmpty
        }
        guard valid else {
            throw MusicServiceError.message("Сервис вернул аудиофайл в несовместимом формате. Попробуйте автоматический API в настройках.")
        }
    }

    static func decrypt(source: URL, destination: URL, hexKey: String) throws {
        guard [32, 48, 64].contains(hexKey.count), hexKey.allSatisfy(\.isHexDigit) else { throw MusicServiceError.invalidResponse }
        var key: [UInt8] = []
        var index = hexKey.startIndex
        while index < hexKey.endIndex {
            let end = hexKey.index(index, offsetBy: 2)
            guard let byte = UInt8(hexKey[index..<end], radix: 16) else { throw MusicServiceError.invalidResponse }
            key.append(byte); index = end
        }
        var cryptor: CCCryptorRef?
        let iv = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(CCOperation(kCCDecrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding), ivBytes.baseAddress, keyBytes.baseAddress, key.count,
                    nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
            }
        }
        guard status == kCCSuccess, let cryptor else { throw MusicServiceError.invalidResponse }
        defer { CCCryptorRelease(cryptor) }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil,
              attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
            throw MusicServiceError.offlineUnavailable
        }
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        while let data = try input.read(upToCount: 262_144), !data.isEmpty {
            try Task.checkCancellation()
            var buffer = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
            let capacity = buffer.count
            var written = 0
            let result = data.withUnsafeBytes { bytes in
                buffer.withUnsafeMutableBytes { out in
                    CCCryptorUpdate(cryptor, bytes.baseAddress, data.count, out.baseAddress, capacity, &written)
                }
            }
            guard result == kCCSuccess else { throw MusicServiceError.invalidResponse }
            try output.write(contentsOf: Data(buffer.prefix(written)))
        }
    }
}
