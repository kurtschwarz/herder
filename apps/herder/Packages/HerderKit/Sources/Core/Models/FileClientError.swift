public enum FileClientError: Error, Equatable {
    case notFound(path: String)
    case notUTF8(path: String)
    case tooLarge(path: String)
    case unreadable(path: String)
    case alreadyExists(path: String)
}
