extension Application {
    public var process: ProcessUtility {
        .init(
            threadPool: self.threadPool,
            eventLoop: self.eventLoopGroup.next()
        )
    }
}

extension ProcessUtility {
    public struct Swift {
        public let process: ProcessUtility

        func run(_ arguments: String...) -> EventLoopFuture<ProcessResult> {
            self.run(arguments)
        }

        func run(_ arguments: [String]) -> EventLoopFuture<ProcessResult> {
            self.process.run(["swift"] + arguments)
        }
    }

    public var swift: Swift {
        .init(process: self)
    }
}

extension ProcessUtility.Swift {
    public struct Package {
        public let swift: ProcessUtility.Swift
        var directoryPath: String?

        public func at(_ path: String) -> Self {
            var copy = self
            copy.directoryPath = path
            return copy
        }

        func run(_ arguments: String...) -> EventLoopFuture<ProcessResult> {
            self.run(arguments)
        }

        func run(_ arguments: [String]) -> EventLoopFuture<ProcessResult> {
            var prefix = ["package"]
            if let directory = self.directoryPath {
                prefix += ["-C", directory]
            }
            return self.swift.run(prefix + arguments)
        }
    }

    public var package: Package {
        .init(swift: self)
    }
}

extension ProcessUtility.Swift.Package {
    public struct Dump: Codable {
        public struct ToolsVersion: Codable {
            public let _version: String
        }
        public let toolsVersion: ToolsVersion
    }

    public func dump() -> EventLoopFuture<Dump> {
        self.run("dump-package").flatMapThrowing { result in
            try JSONDecoder().decode(Dump.self, from: Data(result.output.utf8))
        }
    }
}

extension ProcessUtility {
    public func whoami() -> EventLoopFuture<String> {
        self.run("whoami").map { $0.output }
    }

    public func cat(_ file: String) -> EventLoopFuture<String> {
        self.run("cat", file).flatMapThrowing { result in
            guard result.status == 0 else {
                throw ProcessError(message: result.error)
            }
            return result.output
        }
    }
}

public struct ProcessError: Error, CustomStringConvertible, LocalizedError {
    public let message: String
    public var description: String {
        self.message
    }
    public var errorDescription: String? {
        self.description
    }
    public init(message: String) {
        self.message = message
    }
}

public struct ProcessResult {
    public var status: Int
    public var output: String
    public var error: String
}

public struct ProcessUtility {
    let threadPool: NIOThreadPool
    let eventLoop: EventLoop
    public func run(
        _ arguments: String...
    ) -> EventLoopFuture<ProcessResult> {
        self.run(arguments)
    }

    public func run(
        _ arguments: [String]
    ) -> EventLoopFuture<ProcessResult> {
        var output = ""
        var error = ""
        return NonBlockingProcess.start(
            executablePath: "/usr/bin/env",
            arguments: arguments,
            output: .handle { output += $0 },
            error: .handle { error += $0 },
            threadPool: self.threadPool,
            eventLoop: self.eventLoop
        ).flatMap {
            $0.terminationFuture
        }.map { status in
            ProcessResult(
                status: status,
                output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                error: error.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}

public struct NonBlockingProcess {
    public enum StandardOutput {
        case ignore
        case forward
        case handle((String) -> ())

        func handle(on eventLoop: EventLoop) -> Any? {
            switch self {
            case .ignore:
                return FileHandle.nullDevice
            case .forward:
                return nil
            case .handle(let handler):
                let pipe = Pipe()
                eventLoop.scheduleRepeatedTask(
                    initialDelay: .seconds(0),
                    delay: .milliseconds(100)
                ) { task in
                    #warning("process needs to wait for this to complete")
                    let string = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self)
                    handler(string)
                }
                return pipe
            }
        }
    }

    public static func start(
        executablePath: String,
        arguments: [String],
        output: StandardOutput,
        error: StandardOutput,
        threadPool: NIOThreadPool,
        eventLoop: EventLoop
    ) -> EventLoopFuture<Self> {
        let process = Process()
        process.launchPath = executablePath
        process.arguments = arguments
        process.standardOutput = output.handle(on: eventLoop)
        process.standardError = error.handle(on: eventLoop)
        return threadPool.runIfActive(eventLoop: eventLoop) {
            process.launch()
            return .init(
                process: process,
                threadPool: threadPool,
                eventLoop: eventLoop
            )
        }
    }

    let process: Process
    let threadPool: NIOThreadPool
    let eventLoop: EventLoop

    public var terminationFuture: EventLoopFuture<Int> {
        self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            self.process.waitUntilExit()
            return numericCast(self.process.terminationStatus)
        }
    }
}
