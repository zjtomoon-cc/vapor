import XCTVapor
import XCTest
import Vapor
import NIOCore
import AsyncHTTPClient

fileprivate extension String {
    static func randomDigits(length: Int = 999) -> String {
        var string = ""
        for _ in 0...999 {
            string += String(Int.random(in: 0...9))
        }
        return string
    }
}

final class AsyncRequestTests: XCTestCase {
    
    var app: Application!
    
    override func setUp() async throws {
        app = Application(.testing)
    }
    
    override func tearDown() async throws {
        app.shutdown()
    }
    
    func testStreamingRequest() throws {
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = 0
        
        let testValue = String.randomDigits()
        
        app.on(.POST, "stream", body: .stream) { req in
            var recievedBuffer = ByteBuffer()
            for try await part in req.body {
                XCTAssertNotNil(part)
                var part = part
                recievedBuffer.writeBuffer(&part)
            }
            let string = String(buffer: recievedBuffer)
            return string
        }
        
        app.environment.arguments = ["serve"]
        XCTAssertNoThrow(try app.start())
        
        XCTAssertNotNil(app.http.server.shared.localAddress)
        guard let localAddress = app.http.server.shared.localAddress,
              let ip = localAddress.ipAddress,
              let port = localAddress.port else {
            XCTFail("couldn't get ip/port from \(app.http.server.shared.localAddress.debugDescription)")
            return
        }
        
        var request = HTTPClientRequest(url: "http://\(ip):\(port)/stream")
        request.method = .POST
        request.body = .stream(testValue.utf8.async, length: .unknown)
        
        let response: HTTPClientResponse = try await app.http.client.shared.execute(request, timeout: .seconds(5))
        XCTAssertEqual(response.status, .ok)
        let body = try await response.body.collect(upTo: 1024 * 1024)
        XCTAssertEqual(body.string, testValue)
    }
}

@usableFromInline
struct AsyncLazySequence<Base: Sequence>: AsyncSequence {
    @usableFromInline typealias Element = Base.Element
    @usableFromInline struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline var iterator: Base.Iterator
        @inlinable init(iterator: Base.Iterator) {
            self.iterator = iterator
        }

        @inlinable mutating func next() async throws -> Base.Element? {
            self.iterator.next()
        }
    }

    @usableFromInline var base: Base

    @inlinable init(base: Base) {
        self.base = base
    }

    @inlinable func makeAsyncIterator() -> AsyncIterator {
        .init(iterator: self.base.makeIterator())
    }
}

extension AsyncLazySequence: Sendable where Base: Sendable {}
extension AsyncLazySequence.AsyncIterator: Sendable where Base.Iterator: Sendable {}

extension Sequence {
    /// Turns `self` into an `AsyncSequence` by vending each element of `self` asynchronously.
    @inlinable var async: AsyncLazySequence<Self> {
        .init(base: self)
    }
}
