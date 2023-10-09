import Foundation
import NIOHTTPCompression
import NIOSSL
import Logging
import NIO
import NIOHTTP1
import NIOFoundationCompat


class ProxyHandlerBase: NSObject {
    
    weak var partner: PartnerHandlerProtocol?
    fileprivate var context: ChannelHandlerContext?
    fileprivate var receivedData = Data()
    fileprivate let delegate: ProxyDelegate?
    fileprivate let proxyEndpoint: URL
    var uuid: String = ""
    init(proxyEndpoint: URL, delegate: ProxyDelegate?) {
        self.proxyEndpoint = proxyEndpoint
        self.delegate = delegate
    }
}

extension ProxyHandlerBase: PartnerHandlerProtocol {
    func partnerWrite(_ data: NIOAny) {
        self.context?.write(data, promise: nil)
    }

    func partnerFlush() {
        self.context?.flush()
    }

    func partnerWriteEOF() {
        self.context?.close(mode: .output, promise: nil)
    }

    func partnerCloseFull() {
        self.context?.close(promise: nil)
    }

    func partnerBecameWritable() {
        self.context?.read()
    }

    var partnerWritable: Bool {
        self.context?.channel.isWritable ?? false
    }
}

extension ProxyHandlerBase {
    
    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        self.partner?.partnerFlush()
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.context?.pipeline.close(mode: .all, promise: nil)
        context.fireChannelInactive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event {
            // We have read EOF.
            self.partner?.partnerWriteEOF()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
		if error.localizedDescription.contains("uncleanShutdown") {
			logger.debug("⚠️ \(String(describing: self)) \(error)")
		} else {
			logger.error("❌ \(String(describing: self)) \(error)")
		}
        self.partner?.partnerCloseFull()
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable {
            self.partner?.partnerBecameWritable()
        }
    }

    func read(context: ChannelHandlerContext) {
        context.read()
    }
    
    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        self.partner = nil
    }
}

// MARK: - Server Handler

final class ProxyServerHandler: ProxyHandlerBase {

    private var receivedHeaders: HTTPRequestHeaders?
    private func sslClientHandler(host: String) throws -> NIOSSLClientHandler {
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .noHostnameVerification
        tlsConfig.applicationProtocols = []
        let sslContext = try NIOSSLContext(configuration: tlsConfig)
        return try NIOSSLClientHandler(context: sslContext, serverHostname: host)
    }
    
	private func createClientBootstrap(eventLoop: EventLoop, scheme: String, host: String, request: HTTPRequestData) throws -> ClientBootstrap {
		let proxySubstitution = ProxySubstitutionHandler(host: host)
		let nioHTTPResponseDecompressor = NIOHTTPResponseDecompressor(limit: .none)
		var handlers: [ChannelHandler] = []
		
		if scheme == "https" {
			handlers.append(try self.sslClientHandler(host: host))
		}
		handlers.append(nioHTTPResponseDecompressor)
		handlers.append(proxySubstitution)
		if (request.headers.head.headers["Content-Encoding"].first?.contains("gzip")) ?? false {
			handlers.append(NIOHTTPRequestCompressor(encoding: .gzip))
		} else if (request.headers.head.headers["Content-Encoding"].first?.contains("deflate")) ?? false {
			handlers.append(NIOHTTPRequestCompressor(encoding: .deflate))
		}
		
		return ClientBootstrap(group: eventLoop)
			.channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
			.channelInitializer { channel in
				channel.pipeline.addHandlers(handlers)
					.flatMap { channel.pipeline.addHTTPClientHandlers(position: .before(nioHTTPResponseDecompressor)) }
			}
	}
	
    private func connectTo(request: HTTPRequestData, scheme: String?, host: String?, port: Int?, context: ChannelHandlerContext, _ callback: @escaping (Channel) -> Void) throws {
		guard let host = host else {
			logger.error("Can't resolve Proxy Destination Host")
			return
		}
		let scheme = scheme ?? "https"
		let defaultPort = scheme == "http" ? 80 : 443
		let port = port ?? defaultPort
		
		logger.debug("Connecting to \(scheme)://\(host)/\(request.headers.uri):\(port)")
		
		let clientBootstrap = try createClientBootstrap(eventLoop: context.eventLoop, scheme: scheme, host: host, request: request)
		let channelFuture = clientBootstrap.connect(host: String(host), port: port)
        channelFuture.whenSuccess { channel in
            logger.debug("Connected to \(String(describing: channel.remoteAddress))")
            callback(channel)
        }
        channelFuture.whenFailure { error in
            logger.error("❌ Connect failed: \(error)")
            context.close(promise: nil)
            context.fireErrorCaught(error)
        }
    }
}

extension ProxyServerHandler: ChannelDuplexHandler {
	typealias InboundIn = HTTPServerRequestPart
	typealias InboundOut = HTTPClientRequestPart
	typealias OutboundIn = HTTPServerResponsePart
	typealias OutboundOut = HTTPServerResponsePart

	private func processRequest(_ request: HTTPRequestData, context: ChannelHandlerContext) throws {
		let uuid = UUID().uuidString
		let dataResult = (self.delegate?.request(request, uuid: uuid)) ?? (request: request, response: nil)

		if let httpResponseData = dataResult.response {
			sendResponse(context, httpResponseData)
		} else {
			try connectToProxyDestination(context, dataResult.request, uuid: uuid)
		}
	}

	private func sendResponse(_ context: ChannelHandlerContext, _ httpResponseData: HTTPResponseData) {
		context.channel.write(self.wrapOutboundOut(.head(httpResponseData.headers.head)), promise: nil)
		context.channel.write(self.wrapOutboundOut(.body(.byteBuffer(ByteBuffer(data: httpResponseData.body)))), promise: nil)
		context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
	}

	private func connectToProxyDestination(_ context: ChannelHandlerContext, _ request: HTTPRequestData, uuid: String) throws {
		logger.debug("Proxy Mode Activated")
		try self.connectTo(request: request, scheme: proxyEndpoint.scheme, host: proxyEndpoint.host, port: self.proxyEndpoint.port, context: context) { channel in

			let client = ProxyClientHandler(proxyEndpoint: self.proxyEndpoint, delegate: self.delegate)
			self.partner = client
			client.partner = self
			self.partner?.uuid = uuid

			channel.pipeline.addHandler(client, name: "ProxyClientHandler")
				.and(context.channel.pipeline.addHandler(self))
				.whenComplete { [self] result in
					switch result {
					case .success(_):
						sendRequestToPartner(request, trailers: nil)
					case .failure(_):
						channel.close(mode: .all, promise: nil)
						context.close(promise: nil)
					}
				}
		}
	}

	private func sendRequestToPartner(_ request: HTTPRequestData, trailers: HTTPHeaders?) {
		let headNioAny = self.wrapInboundOut(.head(request.headers.head))
		self.partner?.partnerWrite(headNioAny)
		self.partner?.partnerWrite(self.wrapInboundOut(.body(.byteBuffer(ByteBuffer(data: request.body)))))
		self.partner?.partnerWrite(self.wrapInboundOut(.end(trailers)))
		self.partner?.partnerFlush()
	}

	func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		switch self.unwrapInboundIn(data) {
		case .head(let head):
			receivedHeaders = .init(head: head)
		case .body(let body):
			receivedData.append(contentsOf: body.readableBytesView)
		case .end(let trailers):
			guard let receivedHeaders = receivedHeaders else {
				logger.error("❌ Error No Headers")
				partnerWrite(self.wrapInboundOut(.end(trailers)))
				return
			}

			let httpRequestData = HTTPRequestData(headers: receivedHeaders, body: receivedData)
			do {
				try processRequest(httpRequestData, context: context)
			} catch {
				logger.error("❌ Failed to process request: \(error)")
			}
			receivedData = Data()
		}
	}
}

// MARK: - Client Handler

final class ProxyClientHandler: ProxyHandlerBase {

    private var receivedHeaders: HTTPResponseHeaders?
}

extension ProxyClientHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias InboundOut = HTTPServerResponsePart
    typealias OutboundIn = HTTPClientRequestPart
    typealias OutboundOut = HTTPClientRequestPart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch self.unwrapInboundIn(data) {
        case .head(let head):
            receivedHeaders = .init(head: head)
            
        case .body(let body):
            receivedData.append(contentsOf: body.readableBytesView)
        case .end(let trailers):
            
            guard let receivedHeaders = receivedHeaders else {
				logger.error("❌ Error No Headers")
                partnerWrite(self.wrapInboundOut(.end(trailers)))
                return
            }
            
            let dataResult = delegate?.response(HTTPResponseData(headers: receivedHeaders, body: receivedData), uuid: uuid) ?? HTTPResponseData(headers: receivedHeaders, body: receivedData)
            let headNioAny = self.wrapInboundOut(.head(dataResult.headers.head))
            self.partner?.partnerWrite(headNioAny)
            self.partner?.partnerWrite(self.wrapInboundOut(.body(.byteBuffer(ByteBuffer(data: dataResult.body)))))
            self.partner?.partnerWrite(self.wrapInboundOut(.end(trailers)))
            self.partner?.partnerFlush()
            receivedData = Data()
        }
    }
}
