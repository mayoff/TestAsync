import AsyncCombineAdapters
import XCTest

class AsyncThrowsPublisherTests: XCTestCase {

    func testAsyncThrowsPublisher() {
        let ex = expectation(description: "subscription completed")

        let ticket = AsyncThrowsPublisher<String> { send in
            try await send("hello")
            await Task.fakeSleep(.milliseconds(100))
            try await send("world")
        }.sink(receiveCompletion: { completion in
            print("completion: \(completion)")
            ex.fulfill()
        }, receiveValue: { value in
            print("value: \(value)")
        })

        waitForExpectations(timeout: 1)

        ticket.cancel()
    }

}
