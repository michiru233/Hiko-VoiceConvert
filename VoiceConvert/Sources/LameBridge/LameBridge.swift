import Foundation

public enum LameBridge {
    public static func version() -> String {
        String(cString: get_lame_version())
    }
}
