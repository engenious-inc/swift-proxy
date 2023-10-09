import Foundation

public protocol ProxyDelegate: AnyObject {
    func request(_ request: HTTPRequestData, uuid: String) -> (request: HTTPRequestData, response: HTTPResponseData?)
    func response(_ response: HTTPResponseData, uuid: String) -> HTTPResponseData
}
