public protocol ApplicationRoot {
    static func configure(_ app: Application) throws
    
    static func routes(_ app: Application) throws
}

public extension ApplicationRoot {
    static func routes(_ app: Application) throws { }
    
    static func main() throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        let app = Application(env)
        defer { app.shutdown() }
        
        try self.configure(app)
        try self.routes(app)
        
        try app.run()
    }
}
