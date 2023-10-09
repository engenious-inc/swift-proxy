import Foundation
import NIOHTTP1

public struct HTTPRequestData {
    public var headers: HTTPRequestHeaders
    public var body: Data
    
    public init(headers: HTTPRequestHeaders, body: Data) {
        self.headers = headers
        self.body = body
    }
}


public struct HTTPResponseData {
    public var headers: HTTPResponseHeaders
    public var body: Data
    
    public init(headers: HTTPResponseHeaders, body: Data) {
        self.headers = headers
        self.body = body
    }
}

public class HTTPRequestHeaders {
    
    internal let head: HTTPRequestHead
    internal init(head: HTTPRequestHead) {
        self.head = head
    }
    
    public init(version: HTTPVersion, method: String, uri: String, headers: [(String, String)]) {
        self.head = HTTPRequestHead(version: version.create, method: HTTPMethod(rawValue: method), uri: uri, headers: HTTPHeaders(headers))
    }
    
    public enum HTTPVersion {
        case http2
        case http1_1
        case http1_0
        
        fileprivate var create: NIOHTTP1.HTTPVersion {
            switch self {
            case .http2:
                return .http2
            case .http1_1:
                return .http1_1
            case .http1_0:
                return .http1_0
            }
        }
    }
    
    public var version: HTTPVersion {
        if head.version.major == 1 {
            return head.version.minor == 1 ? .http1_1 : .http1_0
        } else if head.version.major == 2 {
            return .http2
        }
        return .http1_1
    }
    
    public var uri: String {
        head.uri
    }
    
    public var method: String {
        head.method.rawValue
    }
    
    public var headers: [String: String] {
        Dictionary(uniqueKeysWithValues: head.head)
    }
}

public class HTTPResponseHeaders {
    
    internal let head: HTTPResponseHead
    internal init(head: HTTPResponseHead) {
        self.head = head
    }
    
    public init(version: HTTPVersion, status: Int, headers: [(String, String)]) {
        self.head = HTTPResponseHead(version: version.create,
                         status: HTTPResponseStatus(statusCode: status),
                         headers: HTTPHeaders(headers))
    }
    
    public enum HTTPVersion {
        case http2
        case http1_1
        case http1_0
        
        fileprivate var create: NIOHTTP1.HTTPVersion {
            switch self {
            case .http2:
                return .http2
            case .http1_1:
                return .http1_1
            case .http1_0:
                return .http1_0
            }
        }
    }
    
    public var version: HTTPVersion {
        if head.version.major == 1 {
            return head.version.minor == 1 ? .http1_1 : .http1_0
        } else if head.version.major == 2 {
            return .http2
        }
        return .http1_1
    }
    
    public var status: UInt {
        head.status.code
    }
    
    public var headers: [String: String] {
        Dictionary(head.head, uniquingKeysWith: { (first, _) in first })
    }
}
