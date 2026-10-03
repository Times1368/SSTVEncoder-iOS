import CoreGraphics
import Foundation

struct TransmitTextOverlay: Identifiable, Equatable {
    let id: UUID
    var text: String
    var position: CGPoint

    init(id: UUID = UUID(), text: String = "", position: CGPoint = CGPoint(x: 0.5, y: 0.85)) {
        self.id = id
        self.text = text
        self.position = position
    }
}
