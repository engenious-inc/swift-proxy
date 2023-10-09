//
//  SwiftProxyTests.swift


import Foundation
import XCTest
@testable import SwiftProxy

class SwiftProxyTests: XCTestCase {
	
	private lazy var urlSession: URLSession = {
		let sessionConfig = URLSessionConfiguration.default
		sessionConfig.timeoutIntervalForRequest = 5.0
		sessionConfig.timeoutIntervalForResource = 5.0
		return URLSession(configuration: sessionConfig)
	}()
	
	private lazy var certificate: String? = {
		Bundle.module.path(forResource: "localhost", ofType: "crt")
	}()
	
	private lazy var privateKey: String? = {
		Bundle.module.path(forResource: "localhost.key", ofType: "pem")
	}()
	
	private func addTeardownProxyStop(proxy: SwiftProxy) {
		addTeardownBlock {
			XCTAssertNoThrow(try proxy.stop())
		}
	}
	
	func testSwiftProxyStartStop() {
		let delegate = MockProxyDelegate()
		let proxy = SwiftProxy(proxyEndpoint: URL(string: "https://www.apple.com"),
							 delegate: delegate,
							 sslCertFilePath: "/path/to/your/cert",
							 sslPrivateKeyPath: "/path/to/your/key")
		XCTAssertNoThrow(try proxy.start(host: "127.0.0.1", port: 8080))
		XCTAssertNoThrow(try proxy.stop())
	}

	func testHTTPRequestHandling() {
		// Set up mock server
		let expectedResponseBody = Data("Hello, Proxy!".utf8)
		let mockResponseData = HTTPResponseData(headers: .init(head: .init(version: .init(major: 1, minor: 1), status: .ok)), body: expectedResponseBody)
		let mockServer = MockHTTPServer(response: mockResponseData)
		mockServer.start(scheme: .http, host: "127.0.0.1", port: 8888)
		
		// Set up mock proxy delegate
		let proxyDelegate = MockProxyDelegate()
		proxyDelegate.onRequest = { request, uuid -> (HTTPRequestData, HTTPResponseData?) in
			XCTAssertEqual(request.headers.method, "GET")
			XCTAssertEqual(request.body, Data())
			XCTAssertEqual(request.headers.headers, ["Accept-Encoding": "gzip, deflate",
													 "Connection": "keep-alive",
													 "Host": "localhost:8080",
													 "Accept": "*/*",
													 "Accept-Language": "en-US,en;q=0.9",
													 "User-Agent": "xctest/21501 CFNetwork/1404.0.5 Darwin/22.3.0"])
			return (request, nil)
		}
		proxyDelegate.onResponse = { response, uuid -> HTTPResponseData in
			XCTAssertEqual(response.headers.status, 200)
			XCTAssertEqual(response.body, expectedResponseBody)
			return response
		}
		
		// Set up proxy
		let proxy = SwiftProxy(
			proxyEndpoint: URL(string: "http://127.0.0.1:8888"),
			delegate: proxyDelegate,
			sslCertFilePath: "not required for http",
			sslPrivateKeyPath: "not required for http"
		)
		XCTAssertNoThrow(try proxy.start(host: "127.0.0.1", port: 8080))
		addTeardownProxyStop(proxy: proxy)
		
		// Send request to proxy
		let urlRequest = URLRequest(url: URL(string: "http://localhost:8080")!)
		let result = urlSession.sendSynchronous(request: urlRequest)
		XCTAssertNil(result.error)
		XCTAssertNotNil(result.data)
		XCTAssertNotNil(result.response)
		XCTAssertEqual(result.response?.statusCode, 200)
		XCTAssertNoThrow(try proxy.stop())
	}
}
