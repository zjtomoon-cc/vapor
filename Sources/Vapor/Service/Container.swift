public protocol Container {
    var application: Application { get }
    var eventLoop: EventLoop { get }
    var logger: Logger { get }
    // TODO: Tracing
}

extension Request: Container { }
