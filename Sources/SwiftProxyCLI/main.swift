import ArgumentParser
import Foundation
import SwiftProxy

extension Data {
	func string() -> String {
		String(decoding: self, as: UTF8.self)
    }
}

let START_RED = "\u{001B}[0;31m"
let COLOR_END = "\u{001B}[0;0m"

class PrintingStubDelegate: ProxyDelegate {
	let baseEndpoint: URL
	var pendingResponses = [String: HTTPRequestData]()
	
	init(baseEndpoint: String) throws {
		let endpoint = baseEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		guard let url = URL(string: endpoint) else {
			throw SwiftProxyCLIError.baseURLerror("Invalid URL: \(endpoint)")
		}
		self.baseEndpoint = url
	}
	
    func request(_ request: HTTPRequestData, uuid: String) -> (request: HTTPRequestData, response: HTTPResponseData?) {
		pendingResponses[uuid] = request
		
		if request.headers.uri == "/post" {
			let string = request.body.string().replacingOccurrences(of: "Jorge", with: "Leo")
			let data = string.data(using: .utf8)!
			var mutatedRequest = request
			mutatedRequest.body = data
			
			pendingResponses[uuid] = mutatedRequest
			return (mutatedRequest, nil)
		}
		
        return (request, nil)
    }
    
    func response(_ response: HTTPResponseData, uuid: String) -> HTTPResponseData {
        
		guard let request = pendingResponses[uuid] else {
			printToError("\n>>>> Missing request data for uuid '\(uuid)' <<<<\n")
			return response
		}
		pendingResponses.removeValue(forKey: uuid)
		dumpRequest(uuid, request)
		
		let isError = response.headers.status < 200 || response.headers.status >= 299
		print("\n\(isError ? START_RED : "")***** Response *****")
		print("Status: \(response.headers.status)\(isError ? COLOR_END : "")")
        print("Headers:")
        print(response.headers.headers)
		
		let isAttachment = response.headers.headers["Content-Disposition"]?.contains("attachment;") ?? false
		let body = isAttachment ? "<attachment content: \(response.headers.headers["Content-Disposition"]!)>":  response.body.string()
		print("\nBody: \(body.count == 0 ? "<no data>": body)")
        
        return response
    }
	
	func dumpRequest(_ uuid: String, _ request: HTTPRequestData) {
		let isOctetStream = request.headers.headers["Content-Type"]?.contains("octet-stream") ?? false
		
		// Example of decoded request data
		print("\n***** Request \(uuid) *****")
		print("Request: \(request.headers.method) \(baseEndpoint)\(request.headers.uri)")
		print("Headers:")
		print(request.headers.headers)

		let body = isOctetStream ? "<non-text content: \(request.headers.headers["Content-Type"]!)>": request.body.string()
		print("Body: \(body.count == 0 ? "<no data>": body)")
	}

	func dumpPendingResponses() {
		if pendingResponses.isEmpty {
			return
		}
		
		print("\n>>>>                                                    <<<<")
		print(">>>> The following requests did not receive a response: <<<<")
		print(">>>>                                                    <<<<\n")
		
		for (k,v) in pendingResponses {
			dumpRequest(k, v)
		}
	}
}

class CurlPrintingStubDelegate: PrintingStubDelegate {
	override func dumpRequest(_ uuid: String, _ request: HTTPRequestData) {
		var curlCommand = "curl -X \(request.headers.method) \\\n"
		
		let isOctetStream = request.headers.headers["Content-Type"]?.contains("octet-stream") ?? false
		
		for h in request.headers.headers {
			let value = h.key == "Host" ? baseEndpoint.host! : h.value
			curlCommand.append("  -H '\(h.key): \(value)' \\\n")
		}
		
		let body = request.body.string()
		if (!body.isEmpty) {
			curlCommand.append("  -d '\(isOctetStream ? "<non-text content: \(request.headers.headers["Content-Type"]!)>": body)' \\\n")
		}
		curlCommand.append("  --compressed \(baseEndpoint)\(request.headers.uri)")
		
		print("\n***** Request \(uuid) *****")

		print(curlCommand)

	}
}

struct ProxyCLI: ParsableCommand {
	static let SCRIPT_FILE_NAME: String = CommandLine.arguments[0]

	var proxyHost = "127.0.0.1"
	
	static var configuration = CommandConfiguration(
		abstract: "Sets up a logging proxy to a given endpoint base URL.",
		usage: """
			You must provide: <endpoint base url> <localhost port> <trusted.crt path> <trusted.crt.key.pem path> [-curlformat optional], e.g.
			e.g.
			
			\(SCRIPT_FILE_NAME)  'https://rdr-rws-test2.corp.apple.com' 8123 localhost.crt localhost.key.pem --curl-mode true
			
			The provided certificate must belong to a trusted Root CA in your keychain.
			
			Use 'generate-certs.sh to create a Root CA and cert if needed.
			""",
		discussion: """
			Continues running until Ctrl-C is pressed
			""")

	@Argument(help: "The base endpoint where all requests will be sent,\n  e.g. 'https://rdr-rws-test2.corp.apple.com'\n")
	var baseURL: String
	
	@Argument(help: "Local port that the HTTP Proxy will be listening on.\n")
	var proxyPort: Int
	
	@Argument(help: "Path to the certificate that is trusted by a Root CA in your keychain\n  Use 'generate-certs.sh' if you need a root ca and certificate/key pair\n")
	var certificatePath: String
	
	@Argument(help: "Path to the key file for the certificate you are using\n  Use 'generate-certs.sh' if you need a trusted Root CA and certificate/key pair")
	var keyfilePath: String

	@Option(name: .shortAndLong, help: "cUrl formatting mode enabled")
	var curlMode = false
	
	mutating func run() throws {
		if (!FileManager.default.fileExists(atPath: certificatePath)) {
			// printToError("\n\n>>>> Unable to locate certificate file: '\(certificatePath)' <<<<\n")
			throw SwiftProxyCLIError.fileNotFoundError("Unable to locate certificate file: '\(certificatePath)'")
		}
		
		if (!FileManager.default.fileExists(atPath: keyfilePath)) {
			printToError("\n\n>>>> Unable to locate certificate file: '\(keyfilePath)' <<<<\n")
			throw SwiftProxyCLIError.fileNotFoundError("Unable to locate key file: '\(keyfilePath)'")
		}
		
		print("\nStarting proxy for '\(baseURL)' at 'http://\(proxyHost):\(proxyPort)'\n")
		print("Use Ctrl-C to stop the proxy\n")
		
		let delegate = curlMode ? try CurlPrintingStubDelegate(baseEndpoint: baseURL): try PrintingStubDelegate(baseEndpoint: baseURL)
		
		try SwiftProxy(proxyEndpoint: URL(string: baseURL),
			  delegate: delegate,
			  sslCertFilePath: certificatePath,
			  sslPrivateKeyPath: keyfilePath)
			.start(host: proxyHost, port: proxyPort)

		signal(SIGINT, SIG_IGN)
		let sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
		sigintSrc.setEventHandler{
			print("\n\nGot SIGINT")
			delegate.dumpPendingResponses()
			Self.exit(withError: nil)
		}
		sigintSrc.resume()
		dispatchMain()
	}
}

ProxyCLI.main()
