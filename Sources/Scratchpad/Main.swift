import Combine
import Foundation
import AsyncCombineAdapters

@main
struct Main {
    static func main() {
        testAsyncThrowsPublisher()
    }
    
    static func testAsyncThrowsPublisher() {
        var ticket: AnyCancellable? = nil
        ticket = AsyncThrowsPublisher<Int> { send in
            var count = 0
            while !Task.isCancelled {
                try await send(count)
                count += 1
                await Task.fakeSleep(.milliseconds(200))
            }
        }
        .sink(receiveCompletion: {
            print("completion: \($0)")
        }, receiveValue: {
            print("value: \($0)")
            if $0 >= 3 {
                ticket?.cancel()
            }
        })
        RunLoop.main.run()
        ticket?.cancel()
    }
}
