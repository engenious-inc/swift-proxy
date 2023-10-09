extension String {
    func matches(_ regex: String) -> Bool {
        return self.range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
    }
    
    func matches(_ regex: [String]) -> Bool {
        regex.first { regex in
            self.range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
        } != nil
    }
}
