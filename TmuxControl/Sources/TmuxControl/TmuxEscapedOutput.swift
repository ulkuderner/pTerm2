import Foundation

public enum TmuxEscapedOutput {
    /// Decodes tmux control-mode escaped payload bytes. Matches
    /// `-[TmuxGateway decodeEscapedOutput:]`.
    public static func decode(_ bytes: Data) -> Data {
        var result = Data()
        result.reserveCapacity(bytes.count)
        var i = 0
        let count = bytes.count
        while i < count {
            var c = bytes[i]
            if c < 0x20 {
                i += 1
                continue
            }
            if c == 0x5c {
                c = 0
                var ok = true
                for _ in 0..<3 {
                    i += 1
                    while i < count && bytes[i] == 0x0d {
                        i += 1
                    }
                    guard i < count else {
                        ok = false
                        break
                    }
                    let digit = bytes[i]
                    if digit < 0x30 || digit > 0x37 {
                        c = 0x3f
                        i -= 1
                        ok = false
                        break
                    }
                    c = c &* 8 &+ (digit - 0x30)
                }
                if !ok && c == 0 {
                    c = 0x3f
                }
            }
            result.append(c)
            i += 1
        }
        return result
    }
}
