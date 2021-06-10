import Combine

public struct AsyncThrowsPublisher<Output>: Publisher {
    public typealias Failure = Error
    
    let generate: @Sendable ((Output) async throws -> Void) async throws -> Void
    
    public init(
        generate: @escaping @Sendable ((Output) async throws -> Void) async throws -> Void
    ) {
        self.generate = generate
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Error == S.Failure, Output == S.Input {
        let scrip = Subscription(downstream: subscriber, generate: generate)
        subscriber.receive(subscription: scrip)
    }
    
    actor Subscription<Downstream: Subscriber>: Combine.Subscription where
    Downstream.Input == Output,
    Downstream.Failure == Failure
    {
        var task: Task.Handle<Void, Never>? = nil
        var continuation: CheckedContinuation<Subscribers.Demand, Error>? = nil
        var demand: Subscribers.Demand = .none
        
        init(
            downstream: Downstream,
            generate: @Sendable @escaping ((Output) async throws -> Void) async throws -> Void
        ) {
            task = async {
                await self.run(generate, for: downstream)
            }
        }
        
        deinit {
            Swift.print("\(self) \(#function)")
        }
        
        nonisolated func request(_ demand: Subscribers.Demand) {
            Swift.print("\(self) \(#function) \(demand)")
            asyncDetached {
                await _request(demand)
            }
        }
        
        nonisolated func cancel() {
            Swift.print("\(self) \(#function)")
            asyncDetached {
                await _cancel()
            }
        }
        
        private func _request(_ more: Subscribers.Demand) async {
            Swift.print("\(self) \(#function) \(more) \(String(describing: continuation))")
            if let continuation = continuation {
                self.continuation = nil
                continuation.resume(returning: more)
            } else {
                demand += more
            }
        }
        
        private func _cancel() {
            Swift.print("\(self) \(#function) \(String(describing: continuation))")
            task?.cancel()
            task = nil
            continuation?.resume(throwing: Task.CancellationError())
            continuation = nil
        }
        
        private func run(
            _ generate: @escaping @Sendable ((Output) async throws -> Void
            ) async throws -> Void, for downstream: Downstream) async {
            Swift.print("\(self) \(#function)")
            do {
                try await waitForDemand()
                Swift.print("\(self) \(#function) got initial demand")
                try await generate { value in
                    Swift.print("\(self) send \(value)")
                    demand = demand - 1 + downstream.receive(value)
                    try await waitForDemand()
                }
            }
            catch is Task.CancellationError {
                return
            }
            catch let error {
                downstream.receive(completion: .failure(error))
            }
        }
        
        private func waitForDemand() async throws {
            Swift.print("\(self) \(#function) \(demand)")
            guard demand == 0 else { return }
            demand += try await withCheckedThrowingContinuation {
                continuation = $0
            }
            Swift.print("\(self) \(#function) now \(demand)")
        }
    }
}
