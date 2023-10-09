import NIO
import NIOSSL
import NIOHTTP1
import Logging
import Foundation
import NIOHTTPCompression

let logger: Logger = Logger(label: "")

public class SwiftProxy {
	
	enum Error: Swift.Error, CustomStringConvertible {
		case failedToBind(host: String, port: Int, error: Swift.Error)
		
		var description: String {
			switch self {
			case let .failedToBind(host, port, error):
				return """
				Failed to bind \(host):\(port), \(error)
				"""
			}
		}
	}
    
	public private(set) var proxyEndpoint: URL?
    private let sslProxyFilter: [String]
    private weak var proxyDelegate: ProxyDelegate?
    private let sslCertFilePath: String
    private let sslPrivateKeyPath: String
    private lazy var group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    private var channel: Channel?
    private lazy var bootstrap = ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
        .childChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
        .childChannelInitializer { [self] channel in
            
            let initHandler = InitHandler(sslProxyFilter: sslProxyFilter, proxyEndpoint: proxyEndpoint, delegate: proxyDelegate, sslCertFilePath: sslCertFilePath, sslPrivateKeyPath: sslPrivateKeyPath)
            let httpRequestDecoder = ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
            let httpResponseEncoder = HTTPResponseEncoder()
            
            return channel.pipeline.addHandler(initHandler, name: "InitHandler")
                .flatMap { channel.pipeline.addHandler(httpRequestDecoder) }
                .flatMap { channel.pipeline.addHandler(NIOHTTPRequestDecompressor(limit: .none)) }
                .flatMap { channel.pipeline.addHandler(httpResponseEncoder) }
        }
    
    public init(sslProxyFilter: [String] = [], proxyEndpoint: URL?, delegate: ProxyDelegate, sslCertFilePath: String, sslPrivateKeyPath: String) {
        self.sslProxyFilter = sslProxyFilter
        self.proxyEndpoint = proxyEndpoint
        self.proxyDelegate = delegate
        self.sslCertFilePath = sslCertFilePath
        self.sslPrivateKeyPath = sslPrivateKeyPath
    }
    
	public func start(host: String, port: Int) throws {
		do {
			let address = try SocketAddress(ipAddress: host, port: port)
			let future = bootstrap.bind(to: address)
			let channel = try future.wait()
			self.channel = channel
			logger.info("Listening on \(channel.localAddress?.description ?? "")")
		} catch {
			try? self.stop()
			logger.critical("Failed to bind \(host):\(port), \(error)")
			throw Error.failedToBind(host: host, port: port, error: error)
		}
	}
    
    public func stop() throws {
        try group.syncShutdownGracefully()
    }
}
