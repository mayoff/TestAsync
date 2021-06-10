import Combine

extension Publisher {
    public func asyncSequence() -> PublisherAsyncSequence<Self> {
        return .init(pub: self)
    }
}

public struct PublisherAsyncSequence<Pub: Publisher>: AsyncSequence {
    let pub: Pub

    public func makeAsyncIterator() -> AsyncIterator {
        return .init(pub: pub)
    }
    
    public typealias Element = Pub.Output
    
    public actor AsyncIterator: AsyncIteratorProtocol {
        private var state: State = .initializing
        
        private enum State {
            case initializing
            case awaitingSubscription(CheckedContinuation<Subscription, Error>)
            case subscribedIdle(Subscription)
            case subscribedWaiting(Subscription, CheckedContinuation<Signal, Error>)
            case completed(Subscribers.Completion<Pub.Failure>)
        }
        
        private enum Signal {
            case completion(Subscribers.Completion<Pub.Failure>)
            case element(Element)
        }
        
        fileprivate init(pub: Pub) {
            pub.receive(subscriber: self)
        }
        
        deinit {
            print("\(self) deinit")
            switch state {
            case .subscribedIdle(let subscription), .subscribedWaiting(let subscription, _):
                subscription.cancel()
                
            default:
                break
            }
        }
        
        public func next() async throws -> Pub.Output? {
            return try await withTaskCancellationHandler {
                asyncDetached {
                    await self.cancel()
                }
            } operation: {
                return try await _next()
            }
        }
        
        private func cancel() {
            switch state {
            case .initializing:
                state = .completed(.finished)
                
            case .awaitingSubscription(let continuation):
                state = .completed(.finished)
                continuation.resume(throwing: Task.CancellationError())
                
            case .subscribedIdle(let subscription):
                state = .completed(.finished)
                subscription.cancel()
                
            case .subscribedWaiting(let subscription, let continuation):
                state = .completed(.finished)
                subscription.cancel()
                continuation.resume(throwing: Task.CancellationError())
                
            case .completed(_):
                break
            }
        }
        
        private func _next() async throws -> Pub.Output? {
            switch state {
            case .initializing:
                let subscription = try await withCheckedThrowingContinuation {
                    state = .awaitingSubscription($0)
                }
                state = .subscribedIdle(subscription)
                return try await next()
                
            case .awaitingSubscription(_):
                preconditionFailure("re-entered next() while awaiting subscription")
                
            case .subscribedIdle(let subscription):
                subscription.request(.max(1))
                let signal = try await withCheckedThrowingContinuation {
                    state = .subscribedWaiting(subscription, $0)
                }
                
                switch signal {
                case .element(let element):
                    state = .subscribedIdle(subscription)
                    return element
                    
                case .completion(.finished):
                    state = .completed(.finished)
                    return nil
                    
                case .completion(.failure(let error)):
                    state = .completed(.failure(error))
                    throw error
                }
                
            case .subscribedWaiting(_, _):
                preconditionFailure("re-entered next() while awaiting signal")
                
            case .completed(.finished):
                return nil
                
            case .completed(.failure(let error)):
                throw error
            }
        }
    }
}

extension PublisherAsyncSequence.AsyncIterator: Subscriber {
    nonisolated public func receive(subscription: Subscription) {
        asyncDetached {
            await _receive(subscription: subscription)
        }
    }
    
    nonisolated public func receive(_ input: Element) -> Subscribers.Demand {
        asyncDetached {
            await _receive(input)
        }
        return .none
    }
    
    nonisolated public func receive(completion: Subscribers.Completion<Pub.Failure>) {
        // Using detach instead of asyncDetached requires self._receive.
        asyncDetached {
            await _receive(completion: completion)
        }
    }
    
    private func _receive(subscription: Subscription) {
        switch state {
        case .initializing:
            state = .subscribedIdle(subscription)
        case .awaitingSubscription(let continuation):
            continuation.resume(returning: subscription)
        default:
            // Inappropriate Subscription - maybe it's already been cancelled.
            subscription.cancel()
        }
    }
    
    private func _receive(_ input: Element) {
        switch state {
        case .initializing:
            preconditionFailure("received input before Subscription")
        case .awaitingSubscription(_):
            preconditionFailure("received input before Subscription")
        case .subscribedIdle(_):
            preconditionFailure("received input without outstanding demand")
        case .subscribedWaiting(_, let continuation):
            continuation.resume(returning: .element(input))
        case .completed(_):
            // Maybe I've been cancelled.
            break
        }
    }
    
    private func _receive(completion: Subscribers.Completion<Pub.Failure>) {
        switch state {
        case .initializing:
            preconditionFailure("received Completion before Subscription")
        case .awaitingSubscription(_):
            preconditionFailure("received Completion before Subscription")
        case .subscribedIdle(_):
            state = .completed(completion)
        case .subscribedWaiting(_, let continuation):
            continuation.resume(returning: .completion(completion))
        case .completed(_):
            preconditionFailure("received Completion after Completion")
        }
    }
}
