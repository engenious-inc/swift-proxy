import NIO
import NIOHTTP1
import NIOSSL
import NIOHTTPCompression
import SwiftProxy

class MockHTTPServer {
	private let group: EventLoopGroup
	private let response: HTTPResponseData
	private let sslCertFilePath: String?
	private let sslPrivateKeyPath: String?

	enum Sheme {
		case http
		case https
	}
	
	init(response: HTTPResponseData, sslCertFilePath: String? = nil, sslPrivateKeyPath: String? = nil) {
		self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
		self.response = response
		self.sslCertFilePath = sslCertFilePath
		self.sslPrivateKeyPath = sslPrivateKeyPath
	}

	func start(scheme: Sheme, host: String, port: Int) {
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
			.childChannelInitializer { channel in
				if scheme == .https {
					guard let sslCertFilePath = self.sslCertFilePath,
						  let sslPrivateKeyPath = self.sslPrivateKeyPath else {
						fatalError("SSL certificate and private key file paths must be provided for HTTPS.")
					}
					
					let certFile = try! NIOSSLCertificate.fromPEMFile(sslCertFilePath)
					let cert: [NIOSSLCertificateSource] = certFile.map { .certificate($0) }
					var configuration = TLSConfiguration.makeServerConfiguration(certificateChain: cert, privateKey: .file(sslPrivateKeyPath))
					configuration.certificateVerification = .none
					let sslContext = try! NIOSSLContext(configuration: configuration)
					let tlsServerHandler = NIOSSLServerHandler(context: sslContext)
					return channel.pipeline.addHandler(tlsServerHandler)
						.flatMap { channel.pipeline.configureHTTPServerPipeline() }
						.flatMap { channel.pipeline.addHandler(MockHTTPHandler(response: self.response)) }
				} else {
					return channel.pipeline.configureHTTPServerPipeline().flatMap {
						channel.pipeline.addHandler(MockHTTPHandler(response: self.response))
					}
				}
			}

		
		do {
			let address = try SocketAddress(ipAddress: host, port: port)
			let future = bootstrap.bind(to: address)
			let channel = try future.wait()
			print("Listening on \(channel.localAddress?.description ?? "")")
		} catch {
			print("Server failed to start:", error)
			try? stop()
		}
	}

	func stop() throws {
		try group.syncShutdownGracefully()
	}
}

class MockHTTPHandler: ChannelInboundHandler {
	typealias InboundIn = HTTPServerRequestPart
	typealias OutboundOut = HTTPServerResponsePart

	private let response: HTTPResponseData

	init(response: HTTPResponseData) {
		self.response = response
	}

	func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		let reqPart = self.unwrapInboundIn(data)

		switch reqPart {
		case .head:
			()
		case .body:
			()
		case .end:
			print("SEND RESPONSE")
			let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .ok)
			context.write(self.wrapOutboundOut(.head(head)), promise: nil)

			let buffer = context.channel.allocator.buffer(data: response.body)
			context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

			context.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { _ in
				context.close(promise: nil)
			}
		}
	}
}
