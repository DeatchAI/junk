import Foundation

struct RuntimeEndpoint: Equatable {
  let host: String
  let port: Int
  let token: String
  let machineID: UUID?

  static var local: RuntimeEndpoint {
    RuntimeEndpoint(host: "127.0.0.1", port: ServerConfig.port, token: ServerConfig.runtimeToken, machineID: nil)
  }

  var webSocketURL: URL {
    var components = URLComponents()
    components.scheme = "ws"
    components.host = host
    components.port = port
    components.path = "/"
    components.queryItems = [URLQueryItem(name: "token", value: token)]
    return components.url!
  }

  var authorizationHeaderValue: String { "Bearer \(token)" }
}
