import SceneKit
import UIKit
import PerfectFitCore

/// Little renders of each piece for the tray (same models and light as the room).
enum Thumbnails {
    private static var cache: [String: UIImage] = [:]
    private static let renderer: SCNRenderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)

    static func image(_ kind: FurnitureKind, style: String, rotation: Rotation = Rotation(0)) -> UIImage {
        let key = "\(kind.id)|\(style)|\(rotation.turns)"
        if let i = cache[key] { return i }
        let scene = SCNScene()
        scene.lightingEnvironment.contents = Bundle.main.url(forResource: "studio", withExtension: "hdr", subdirectory: "Textures")
        scene.lightingEnvironment.intensity = 1.3
        let node = FurnitureModels.node(for: kind, style: RoomStyle.named(style))
        node.eulerAngles.y = Float(rotation.turns) * .pi / 2
        scene.rootNode.addChildNode(node)
        let (mn, mx) = node.boundingBox
        let ext = max(mx.x - mn.x, mx.z - mn.z, mx.y - mn.y)
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera!.usesOrthographicProjection = true
        cam.camera!.orthographicScale = Double(ext) * 0.62
        cam.camera!.zNear = 0.01; cam.camera!.zFar = 50
        cam.camera!.wantsHDR = true
        cam.camera!.exposureOffset = 0.2
        let yaw: Float = .pi / 4, el: Float = 0.6, d: Float = 10
        let cy = (mn.y + mx.y) / 2
        cam.position = SCNVector3(d * cos(el) * sin(yaw), cy + d * sin(el), d * cos(el) * cos(yaw))
        cam.look(at: SCNVector3(0, cy * 0.9, 0))
        scene.rootNode.addChildNode(cam)
        let key1 = SCNNode(); key1.light = SCNLight(); key1.light!.type = .directional; key1.light!.intensity = 700
        key1.light!.temperature = 5200
        key1.eulerAngles = SCNVector3(-1.0, -0.6, 0); scene.rootNode.addChildNode(key1)
        renderer.scene = scene
        renderer.pointOfView = cam
        let img = renderer.snapshot(atTime: 0, with: CGSize(width: 220, height: 220), antialiasingMode: .multisampling4X)
        cache[key] = img
        return img
    }
}
