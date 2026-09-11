import Foundation

extension DictationController.Phase {
    var title: String {
        switch self {
        case .preparing(.downloading): "Downloading the speech model"
        case .preparing(.loading): "Loading the speech model"
        case .ready: "Ready"
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .failed: "Needs attention"
        }
    }

    var detail: String? {
        switch self {
        case .preparing(.downloading):
            "Happens once. It's a couple of gigabytes, so give it a few minutes."
        case .preparing(.loading):
            "Reading the weights into memory"
        case .failed(let message):
            message
        case .ready, .listening, .transcribing:
            nil
        }
    }
}
