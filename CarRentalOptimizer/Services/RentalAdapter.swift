import Foundation

protocol RentalAdapter {
    var platform: PlatformId { get }
    func search(request: SearchRequest) async -> [RentalListing]
}
