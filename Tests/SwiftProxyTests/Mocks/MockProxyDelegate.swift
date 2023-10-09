import Foundation
import SwiftProxy

class MockProxyDelegate: ProxyDelegate {
	var requestsCount = 0
	var responsesCount = 0
	var onRequest: ((HTTPRequestData, String) -> (HTTPRequestData, HTTPResponseData?))?
	var onResponse: ((HTTPResponseData, String) -> HTTPResponseData)?

	func request(_ request: HTTPRequestData, uuid: String) -> (request: HTTPRequestData, response: HTTPResponseData?) {
		requestsCount += 1
		return onRequest?(request, uuid) ?? (request, nil)
	}

	func response(_ response: HTTPResponseData, uuid: String) -> HTTPResponseData {
		responsesCount += 1
		return onResponse?(response, uuid) ?? response
	}
}
