import Foundation
import NIOHTTPCompression
import NIOSSL
import NIO
import NIOHTTP1
import NIOFoundationCompat

class InitHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    private let delegate: ProxyDelegate?
    private let proxyEndpoint: URL?
    private let sslProxyFilter: [String]
    private let sslCertFilePath: String
    private let sslPrivateKeyPath: String
    
	private lazy var proxySetup: ((_ context: ChannelHandlerContext, _ data: Data) -> Void)? = { [self] context, data in
		guard let proxyEndpoint = proxyEndpoint else {
			logger.error("❌ Proxy Endpoint was not set")
			return
		}
		
		let stringData = String(data: data, encoding: .utf8)
		let useTLS = stringData == nil
		let proxyServerHandler = ProxyServerHandler(proxyEndpoint: proxyEndpoint, delegate: delegate)
		var pipelineFuture: EventLoopFuture<Void> = context.eventLoop.makeSucceededFuture(())
		
		if useTLS {
			let certFile = try! NIOSSLCertificate.fromPEMFile(sslCertFilePath)
			let cert: [NIOSSLCertificateSource] = certFile.map { .certificate($0) }
			var configuration = TLSConfiguration.makeServerConfiguration(certificateChain: cert, privateKey: .file(sslPrivateKeyPath))
			configuration.certificateVerification = .none
			let sslContext = try! NIOSSLContext(configuration: configuration)
			let tlsServerHandler = NIOSSLServerHandler(context: sslContext)
			
			pipelineFuture = context.channel.pipeline.addHandler(tlsServerHandler, name: "NIOSSLServerHandler",
																 position: .after(self))
		}
		
		pipelineFuture
			.flatMap { context.channel.pipeline.addHandler(HTTPResponseCompressor()) }
			.flatMap { context.channel.pipeline.addHandler(proxyServerHandler) }
			.whenComplete { _ in context.pipeline.removeHandler(name: "InitHandler", promise: nil) }
	}
    
    init(sslProxyFilter: [String], proxyEndpoint: URL?, delegate: ProxyDelegate?, sslCertFilePath: String, sslPrivateKeyPath: String) {
        self.sslProxyFilter = sslProxyFilter
        self.proxyEndpoint = proxyEndpoint
        self.delegate = delegate
        self.sslCertFilePath = sslCertFilePath
        self.sslPrivateKeyPath = sslPrivateKeyPath
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		if let proxySetup = proxySetup {
			let unwrappedData = self.unwrapInboundIn(data)
			let binaryData = Data(buffer: unwrappedData)
			proxySetup(context, binaryData)
			self.proxySetup = nil // use one time only
		}
        context.fireChannelRead(data)
    }
    
    func channelReadComplete(context: ChannelHandlerContext) {
        context.fireChannelReadComplete()
    }
}
