import Foundation
import ActivityKit

public struct SiriActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var phase: String
        public var detail: String
        public var progress: Double

        public init(phase: String, detail: String, progress: Double = 0) {
            self.phase = phase
            self.detail = detail
            self.progress = progress
        }
    }

    public var title: String

    public init(title: String) {
        self.title = title
    }
}
