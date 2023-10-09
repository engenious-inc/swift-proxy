import NIOHTTP1

public extension HTTPResponseHead {
    var head: [(String, String)] {
        Mirror(reflecting: self.headers)
            .children.first { $0.label == "headers" }?.value as? [(String, String)] ?? []
    }
}

public extension HTTPRequestHead {
    var head: [(String, String)] {
        Mirror(reflecting: self.headers)
            .children.first { $0.label == "headers" }?.value as? [(String, String)] ?? []
    }
}
