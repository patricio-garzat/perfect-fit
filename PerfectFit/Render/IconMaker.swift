#if DEBUG
import SceneKit
import UIKit
import PerfectFitCore

/// Renders the app icon from the game itself: the "Snug" bedroom, furnished (3 stars), as a miniature on linen.
/// Run the app with `-pfIcon`; it writes icon-1024.png and icon-dev-1024.png to the app's Documents folder
/// (tools/make-icons.sh copies them into the asset catalog).
enum IconMaker {
    static func run(level: Level, turns: Int = Int(ProcessInfo.processInfo.environment["PF_ICON_TURNS"] ?? "0") ?? 0,
                    scale: Double = Double(ProcessInfo.processInfo.environment["PF_ICON_SCALE"] ?? "3.0") ?? 3.0) {
        let session = GameSession(level: level)
        guard let layout = Solver(level: level).find(stars: 3, deadline: Date().addingTimeInterval(5)) else { return }
        let c = SceneController(session: session)
        session.setLayout(layout)
        c.sync(.all)
        c.dark = false
        c.hide(kind: "wardrobe")   // it would hide the bed from this angle
        for _ in 0..<turns { c.turnCamera() }
        let scene = c.scene
        // linen backdrop, a touch warmer at the top
        let bg = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 512)).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(hex: 0xF2EBE1).cgColor, UIColor(hex: 0xD8CAB7).cgColor] as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
        }
        scene.background.contents = bg
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera!.usesOrthographicProjection = true
        cam.camera!.orthographicScale = scale
        cam.camera!.zNear = 0.1; cam.camera!.zFar = 100
        cam.camera!.wantsHDR = true
        cam.camera!.exposureOffset = 0.25
        cam.camera!.screenSpaceAmbientOcclusionIntensity = 0.9
        cam.camera!.bloomIntensity = 0.15
        let yaw: Float = .pi / 4 + Float(turns) * .pi / 2, el: Float = 0.62, d: Float = 30
        cam.position = SCNVector3(d * cos(el) * sin(yaw), d * sin(el) + 0.6, d * cos(el) * cos(yaw))
        cam.eulerAngles = SCNVector3(-el, yaw, 0)
        scene.rootNode.addChildNode(cam)
        // let the wall-cut animation of turnCamera() finish
        Thread.sleep(forTimeInterval: 0.05)
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = scene
        r.pointOfView = cam
        let img = r.snapshot(atTime: 0, with: CGSize(width: 1024, height: 1024), antialiasingMode: .multisampling4X)
        let opaque = flatten(img)
        let dev = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: fmt()).image { ctx in
            opaque.draw(at: .zero)
            UIColor(hex: 0x2F2B27, alpha: 0.88).setFill()
            ctx.fill(CGRect(x: 0, y: 830, width: 1024, height: 150))
            let t = NSAttributedString(string: "DEV", attributes: [.font: UIFont.systemFont(ofSize: 96, weight: .semibold), .foregroundColor: UIColor(hex: 0xF3EEE7), .kern: 18])
            let sz = t.size()
            t.draw(at: CGPoint(x: (1024 - sz.width) / 2, y: 830 + (150 - sz.height) / 2))
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? opaque.pngData()?.write(to: docs.appendingPathComponent("icon-1024.png"))
        try? dev.pngData()?.write(to: docs.appendingPathComponent("icon-dev-1024.png"))
        print("ICON_DONE", docs.path)
    }

    private static func fmt() -> UIGraphicsImageRendererFormat { let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true; return f }
    /// App icons must be opaque, no alpha.
    private static func flatten(_ i: UIImage) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: fmt()).image { _ in
            UIColor(hex: 0xEDE6DC).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            i.draw(in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
    }
}
#endif
