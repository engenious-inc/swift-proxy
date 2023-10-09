import NIOCore
import NIOHTTP1
import Foundation

class ProxySubstitutionHandler: ChannelOutboundHandler, RemovableChannelHandler {
    public typealias OutboundIn = HTTPClientRequestPart
    public typealias OutboundOut = HTTPClientRequestPart
    private let host: String
    
    init(host: String) {
        self.host = host
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let request = self.unwrapOutboundIn(data)
        switch request {
        case .head(var head):
			head.headers.replaceOrAdd(name: "Host", value: host)
            head.headers.replaceOrAdd(name: "Accept-Encoding", value: "deflate, gzip")
            context.write(self.wrapOutboundOut(.head(head)), promise: promise)
        default:
            context.write(data, promise: promise)
        }
    }
}
