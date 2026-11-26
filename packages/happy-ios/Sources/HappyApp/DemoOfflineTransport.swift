#if canImport(UIKit)
import Foundation
import HappyCore
import UIKit

/// Cuts all general HTTP(S) network traffic so the app never reaches external servers.
struct DemoOfflineHTTPTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}

/// Cuts all WebSocket connections so legacy/relay sockets never connect.
struct DemoOfflineWebSocketConnector: WebSocketConnector {
    func connect(to url: URL) async throws -> WebSocketConnection {
        throw URLError(.notConnectedToInternet)
    }
}

/// Generates crisp PNG icons, avatars, and artifact cover previews locally in memory.
enum DemoImages {
    static func badge(letter: String, red: CGFloat, green: CGFloat, blue: CGFloat, side: CGFloat = 160) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { _ in
            UIColor(red: red, green: green, blue: blue, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
            let font = UIFont.systemFont(ofSize: side * 0.46, weight: .bold)
            let title = NSAttributedString(
                string: letter,
                attributes: [.font: font, .foregroundColor: UIColor.white]
            )
            let size = title.size()
            title.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
        }
    }

    static func chartCover(width: CGFloat = 960, height: CGFloat = 540) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { ctx in
            let cg = ctx.cgContext
            UIColor(red: 0.05, green: 0.12, blue: 0.21, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))

            UIColor(white: 1, alpha: 0.08).setStroke()
            cg.setLineWidth(1)
            for row in 1...4 {
                let y = height * CGFloat(row) / 5
                cg.move(to: CGPoint(x: 48, y: y))
                cg.addLine(to: CGPoint(x: width - 48, y: y))
            }
            cg.strokePath()

            let points: [CGPoint] = [
                CGPoint(x: 64, y: 390),
                CGPoint(x: 200, y: 340),
                CGPoint(x: 340, y: 360),
                CGPoint(x: 480, y: 250),
                CGPoint(x: 620, y: 215),
                CGPoint(x: 760, y: 150),
                CGPoint(x: 896, y: 115),
            ]
            let line = UIBezierPath()
            line.move(to: points[0])
            for point in points.dropFirst() { line.addLine(to: point) }
            UIColor(red: 0.26, green: 0.78, blue: 0.65, alpha: 1).setStroke()
            line.lineWidth = 6
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            line.stroke()

            UIColor(red: 0.26, green: 0.78, blue: 0.65, alpha: 1).setFill()
            for point in points {
                cg.fillEllipse(in: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
            }

            let label = NSAttributedString(
                string: "Q4 Velocity  +28%",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                    .foregroundColor: UIColor.white,
                ]
            )
            label.draw(at: CGPoint(x: 64, y: 46))
        }
    }

    static func pluginMark(_ digest: String) -> Data? {
        switch digest {
        case "github": return badge(letter: "G", red: 0.11, green: 0.13, blue: 0.16, side: 120)
        case "linear": return badge(letter: "L", red: 0.35, green: 0.41, blue: 0.82, side: 120)
        case "sentry": return badge(letter: "S", red: 0.24, green: 0.16, blue: 0.31, side: 120)
        default: return nil
        }
    }
}
#endif
