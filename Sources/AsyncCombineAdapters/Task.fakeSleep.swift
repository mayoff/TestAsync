import Dispatch

extension Task {
    public static func fakeSleep(_ duration: DispatchTimeInterval) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + duration) {
                continuation.resume()
            }
        }
    }
}
