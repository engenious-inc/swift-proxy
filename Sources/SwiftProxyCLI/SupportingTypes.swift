import Foundation

enum SwiftProxyCLIError: Error {
	case baseURLerror(String)
	case fileNotFoundError(String)
}

/// Add output stream capability to file handle for write to stderr
extension FileHandle : TextOutputStream {
	public func write(_ string: String) {
		guard let data = string.data(using: .utf8) else { return }
		self.write(data)
	}
}

/// File handle and print method to write to stderr
var standardError = FileHandle.standardError
func printToError(_ string: String) {
	print(string, to:&standardError)
}

extension String {
	var expandingTildeInPath: String {
		return NSString(string: self).expandingTildeInPath
	}
}
