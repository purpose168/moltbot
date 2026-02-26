import Foundation

public enum BonjourEscapes {
    /// mDNS / DNS-SD 通常会将实例名称中的字节转义为 `\DDD`（十进制编码），
    /// 例如空格会被编码为 `\032`。
    public static func decode(_ input: String) -> String {
        var out = ""
        var i = input.startIndex
        while i < input.endIndex {
            if input[i] == "\\",
               let d0 = input.index(i, offsetBy: 1, limitedBy: input.index(before: input.endIndex)),
               let d1 = input.index(i, offsetBy: 2, limitedBy: input.index(before: input.endIndex)),
               let d2 = input.index(i, offsetBy: 3, limitedBy: input.index(before: input.endIndex)),
               input[d0].isNumber,
               input[d1].isNumber,
               input[d2].isNumber
            {
                let digits = String(input[d0...d2])
                if let value = Int(digits),
                   let scalar = UnicodeScalar(value)
                {
                    out.append(Character(scalar))
                    i = input.index(i, offsetBy: 4)
                    continue
                }
            }

            out.append(input[i])
            i = input.index(after: i)
        }
        return out
    }
}
