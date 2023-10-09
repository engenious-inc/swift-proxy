import NIOSSL

class TLS {
    static func client(host: String) throws -> NIOSSLClientHandler {
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .noHostnameVerification
        tlsConfig.applicationProtocols = []
        let sslContext = try! NIOSSLContext(configuration: tlsConfig)
        return try NIOSSLClientHandler(context: sslContext, serverHostname: host)
    }
    
    static func server(certPath: String, privateKeyPath: String) throws -> NIOSSLServerHandler {
        let certFile = try NIOSSLCertificate.fromPEMFile(certPath)
        let cert: [NIOSSLCertificateSource] = certFile.map {.certificate($0)}
        var configuration = TLSConfiguration.makeServerConfiguration(certificateChain: cert, privateKey: .file(privateKeyPath))
        configuration.certificateVerification = .none
        configuration.trustRoots = .default
        let sslContext = try NIOSSLContext(configuration: configuration)
        return NIOSSLServerHandler(context: sslContext)
    }
}
