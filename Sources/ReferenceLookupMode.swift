
public enum ReferenceLookupMode: String, CaseIterable, Identifiable {
    case offline = "Offline"
    case online = "Online Only"
    case hybrid = "Hybrid"

    public var id: String { rawValue }
    
    public var description: String {
        switch self {
        case .offline: return "Local extraction only (no internet)"
        case .online: return "Fetch from CrossRef/arXiv only (requires DOI)"
        case .hybrid: return "Try online first, fallback to local"
        }
    }
}
