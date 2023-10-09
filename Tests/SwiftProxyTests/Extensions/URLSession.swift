import Foundation

extension URLSession {
	public func sendSynchronous(request: URLRequest) -> (data: Data?, response: HTTPURLResponse?, error: Error?) {
		var result: (data: Data?, response: HTTPURLResponse?, error: Error?)
		
		//Semaphore for synchronous call
		let semaphore = DispatchSemaphore(value: 0)
		
		let task: URLSessionDataTask = dataTask(with: request) { (data, response, error) in
			result = (data, response as? HTTPURLResponse, error)
			semaphore.signal()
		}
		
		task.resume()
		
		_ = semaphore.wait(timeout: .distantFuture)
		
		return result
	}
	
	public func sendSynchronous(url: URL) -> (data: Data?, response: HTTPURLResponse?, error: Error?) {
		var result: (data: Data?, response: HTTPURLResponse?, error: Error?)
		
		//Semaphore for synchronous call
		let semaphore = DispatchSemaphore(value: 0)
		
		let task: URLSessionDataTask = dataTask(with: url) { (data, response, error) in
			result = (data, response as? HTTPURLResponse, error)
			semaphore.signal()
		}
		
		task.resume()
		
		_ = semaphore.wait(timeout: .distantFuture)
		
		return result
	}
}
