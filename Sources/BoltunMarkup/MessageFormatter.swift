import Foundation
import Markdown

public enum MessageFormatter {
    public static func plainText(_ message: String) -> String {
        Document(parsing: message).format()
    }
}
