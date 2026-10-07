import Foundation
import SwiftData

@Model
final class FavouriteStation {
    var code: String
    var name: String
    var addedAt: Date

    init(code: String, name: String) {
        self.code = code
        self.name = name
        self.addedAt = .now
    }
}
