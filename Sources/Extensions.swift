import Foundation

extension String {
    var localized: String {
        let language = UserDefaults.standard.string(forKey: "app_language") ?? "en"
        
        // Try to find the language bundle in the main app bundle first (MAS structure)
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: self, value: nil, table: nil)
        }
        
        // Fallback to Bundle.module if it exists (for SPM/Xcode/Unit tests)
        // We use a safe accessor if possible, but for now we'll just check Bundle.module
        // Note: Bundle.module can fatalError if not found, so we'll be careful.
        // Actually, let's just use Bundle.main as primary and self for static strings.
        
        return NSLocalizedString(self, bundle: Bundle.main, comment: "")
    }
}
