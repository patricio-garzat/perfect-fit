import SceneKit
import UIKit
import PerfectFitCore

/// SCNView that reports size changes (the camera is fitted to the view's size).
final class FitView: SCNView {
    var onLayout: (() -> Void)?
    private var lastSize = CGSize.zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize { lastSize = bounds.size; onLayout?() }
    }
}

/// Owns the SceneKit view of one level: camera, lights, furniture nodes, overlays and touch handling.
/// Logic lives in GameSession; this class turns touches into placements and placements into nodes.
final class SceneController: NSObject, UIGestureRecognizerDelegate {
    let view = FitView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
    let scene = SCNScene()
    private(set) var session: GameSession
    private(set) var builder: RoomBuilder
    let style: RoomStyle

    private var pieceNodes: [SCNNode] = []
    private var plateNodes: [SCNNode] = []       // footprint plate under each piece (selection / problems)
    private let ghost = SCNNode()                 // footprint while dragging
    private let zones = SCNNode()                 // use zones of the selected piece
    private let orbit = SCNNode()
    private let cameraNode = SCNNode()
    private let sun = SCNNode()
    private let fill = SCNNode()
    private var yawStep = 0
    private var zoom: CGFloat = 1
    private var pan = CGPoint.zero               // camera offset in world units (only while zoomed in)
    private var fitScale: CGFloat = 4
    private var centerShift: CGFloat = 0
    var insets = UIEdgeInsets.zero { didSet { if insets != oldValue && !suppressRefit { refit(animated: false) } } }
    /// Screen y (in the view) above which a dragged piece is over the tray.
    var trayTop: CGFloat = .greatestFiniteMagnitude
    var dark = false { didSet { if dark != oldValue { applyMood(animated: true) } } }
    var onTrayHover: ((Bool) -> Void)?
    var interactive = true

    let elevation: Float = 0.62   // ~35.5°

    init(session: GameSession) {
        self.session = session
        style = RoomStyle.named(session.level.style)
        builder = RoomBuilder(room: session.room, style: style)
        super.init()
        setupView()
        setupScene()
        buildPieces()
        session.onChange = { [weak self] change in self?.sync(change) }
        sync(.all)
    }

    // MARK: - setup

    private func setupView() {
        view.onLayout = { [weak self] in self?.refit(animated: false) }
        view.scene = scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isJitteringEnabled = false
        view.rendersContinuously = false
        view.isPlaying = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        let dbl = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        tap.require(toFail: dbl)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        pinch.delegate = self
        [pan, tap, dbl, pinch].forEach(view.addGestureRecognizer)
    }

    private func setupScene() {
        scene.rootNode.addChildNode(builder.root)
        scene.lightingEnvironment.contents = Bundle.main.url(forResource: "studio", withExtension: "hdr", subdirectory: "Textures")
        scene.lightingEnvironment.intensity = 1.3

        let key = SCNLight()
        key.type = .directional
        key.intensity = 1050
        key.temperature = 5600
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowSampleCount = 12
        key.shadowRadius = 5
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0, alpha: 0.42)
        key.automaticallyAdjustsShadowProjection = false
        let (w, d) = builder.size
        key.orthographicScale = max(w, d) * 0.85 + 1.2
        key.zNear = 1; key.zFar = 40
        key.shadowBias = 1.5
        sun.light = key
        sun.position = SCNVector3(-6, 12, 7)
        sun.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(sun)

        let amb = SCNLight(); amb.type = .ambient; amb.intensity = 260; amb.temperature = 4800
        fill.light = amb
        scene.rootNode.addChildNode(fill)

        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.zNear = 0.1; cam.zFar = 120
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0.15
        cam.bloomIntensity = 0.18
        cam.bloomThreshold = 0.92
        cam.bloomBlurRadius = 8
        cam.vignettingIntensity = 0.25
        cam.vignettingPower = 1.2
        cam.screenSpaceAmbientOcclusionIntensity = 0.9
        cam.screenSpaceAmbientOcclusionRadius = 0.12
        cam.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        cam.screenSpaceAmbientOcclusionDepthThreshold = 0.25
        cameraNode.camera = cam
        orbit.addChildNode(cameraNode)
        scene.rootNode.addChildNode(orbit)
        view.pointOfView = cameraNode

        ghost.renderingOrder = 8
        builder.overlays.addChildNode(ghost)
        builder.overlays.addChildNode(zones)
        applyMood(animated: false)
        placeCamera(animated: false)
    }

    private func buildPieces() {
        for (i, k) in session.kinds.enumerated() {
            let holder = SCNNode()
            holder.name = "piece:\(i)"
            let model = FurnitureModels.node(for: k, style: style)
            holder.addChildNode(model)
            holder.isHidden = true
            builder.root.addChildNode(holder)
            pieceNodes.append(holder)
            let plate = SCNNode(geometry: SCNPlane(width: 1, height: 1))
            plate.eulerAngles.x = -.pi / 2
            plate.position.y = 0.005
            plate.renderingOrder = 7
            plate.isHidden = true
            plate.castsShadow = false
            builder.overlays.addChildNode(plate)
            plateNodes.append(plate)
        }
    }

    /// Background, light and exposure for light / dark themes.
    func applyMood(animated: Bool) {
        let top = dark ? UIColor(hex: 0x24211E) : UIColor(hex: 0xF6F2EC)
        let bottom = dark ? UIColor(hex: 0x141210) : UIColor(hex: 0xE4DCD0)
        let img = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 512)).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
        }
        scene.background.contents = img
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.8 : 0
        sun.light?.intensity = dark ? 560 : 1050
        sun.light?.temperature = dark ? 4200 : 5400
        scene.lightingEnvironment.intensity = dark ? 0.65 : 1.3
        fill.light?.intensity = dark ? 110 : 260
        SCNTransaction.commit()
    }

    // MARK: - camera

    private var yaw: Float { .pi / 4 + Float(yawStep) * .pi / 2 }

    private func placeCamera(animated: Bool) {
        let dist: Float = 30
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.7 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        orbit.eulerAngles.y = yaw
        cameraNode.position = SCNVector3(0, dist * sin(elevation), dist * cos(elevation))
        cameraNode.eulerAngles = SCNVector3(-elevation, 0, 0)
        SCNTransaction.commit()
        refit(animated: animated)
        updateWalls(animated: animated)
    }

    /// Fits the room in the free area between the top bar and the tray.
    func refit(animated: Bool) {
        guard view.bounds.height > 0 else { return }
        let (w, d) = builder.size
        let hw = w / 2 + 0.15, hd = d / 2 + 0.15
        // camera basis after yaw (right, up) for an orthographic view
        let cy = cos(yaw), sy = sin(yaw), se = sin(elevation), ce = cos(elevation)
        let right = SIMD3<Float>(cy, 0, -sy)
        let up = SIMD3<Float>(-sy * se, ce, -cy * se)
        var minR: Float = .greatestFiniteMagnitude, maxR: Float = -.greatestFiniteMagnitude, minU = minR, maxU = maxR
        for x in [-hw, hw] { for z in [-hd, hd] { for y in [CGFloat(-0.3), 2.4] {
            let p = SIMD3<Float>(Float(x), Float(y), Float(z))
            let r = simd_dot(p, right), u = simd_dot(p, up)
            minR = min(minR, r); maxR = max(maxR, r); minU = min(minU, u); maxU = max(maxU, u)
        }}}
        let vw = view.bounds.width, vh = view.bounds.height
        let freeH = vh - insets.top - insets.bottom
        let aspect = vw / max(freeH, 1)
        // orthographicScale = half the visible height in world units (of the whole view)
        let needH = CGFloat(maxU - minU) / 2 * 1.06
        let needW = CGFloat(maxR - minR) / 2 / aspect * 1.08
        let freeHalf = max(needH, needW)
        fitScale = freeHalf * vh / max(freeH, 1)
        let unitsPerPoint = 2 * fitScale / vh
        // move the camera so the room sits in the middle of the free area
        centerShift = (insets.bottom - insets.top) / 2 * unitsPerPoint
        let midU = CGFloat(maxU + minU) / 2, midR = CGFloat(maxR + minR) / 2
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.7 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.camera?.orthographicScale = Double(fitScale / zoom)
        let shiftU = Float(midU - centerShift / zoom + pan.y), shiftR = Float(midR + pan.x)
        let dist: Float = 30
        cameraNode.position = SCNVector3(shiftR, dist * se + shiftU * ce, dist * ce - shiftU * se)
        SCNTransaction.commit()
    }

    func turnCamera() {
        yawStep = (yawStep + 1) % 4
        pan = .zero
        Sound.shared.play(.rotate, volume: 0.6)
        Haptics.shared.play(.rotate)
        placeCamera(animated: true)
    }

    /// Walls between the camera and the room drop to a low cut, like a model's section.
    private func updateWalls(animated: Bool, yaw: Float? = nil) {
        let a = yaw ?? self.yaw
        let camDir = SIMD2<Float>(sin(a), cos(a))
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.6 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for w in builder.walls {
            let near = simd_dot(w.normal, camDir) > 0.25
            let total = Float(builder.wallH + builder.base)
            let cut = Float(builder.base + 0.14) / total
            w.node.scale = SCNVector3(1, near ? cut : 1, 1)
            for e in w.extras { e.opacity = near ? 0 : 1 }
        }
        SCNTransaction.commit()
    }

    // MARK: - sync with the session

    func sync(_ change: GameSession.Change) {
        switch change {
        case .all:
            for i in pieceNodes.indices { syncPiece(i, animated: false) }
        case .piece(let i):
            syncPiece(i, animated: true)
        case .hint(let i):
            syncPiece(i, animated: true, fromAbove: true)
        case .selection: break
        }
        refreshOverlays()
    }

    private func syncPiece(_ i: Int, animated: Bool, fromAbove: Bool = false) {
        let node = pieceNodes[i]
        guard let p = session.placement(i) else {
            node.isHidden = true
            return
        }
        let k = session.kinds[i]
        let target = builder.position(k, p)
        let yawTarget = Float(p.rotation.turns) * .pi / 2
        if node.isHidden || !animated {
            node.position = fromAbove ? SCNVector3(target.x, 0.6, target.z) : target
            node.eulerAngles.y = yawTarget
            node.isHidden = false
            if !fromAbove { return }
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = fromAbove ? 0.45 : 0.22
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1)
        node.position = target
        node.eulerAngles.y = shortestYaw(from: node.eulerAngles.y, to: yawTarget)
        SCNTransaction.commit()
    }

    private func shortestYaw(from a: Float, to b: Float) -> Float {
        var d = b - a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return a + d
    }

    /// Plates under pieces (selection and problems), the selected piece's zones, the door swing warning.
    func refreshOverlays() {
        let e = session.eval
        let troubled = Set(e.issues.compactMap(\.piece))
        for (i, plate) in plateNodes.enumerated() {
            guard let p = session.placement(i), drag?.piece != i else { plate.isHidden = true; continue }
            let k = session.kinds[i]
            let (w, h) = k.rotatedSize(p.rotation)
            let g = plate.geometry as! SCNPlane
            g.width = CGFloat(w) * CGFloat(cellSize) - 0.03
            g.height = CGFloat(h) * CGFloat(cellSize) - 0.03
            g.cornerRadius = 0.05
            let pos = builder.position(k, p)
            plate.position = SCNVector3(pos.x, 0.006, pos.z)
            if troubled.contains(i) {
                g.materials = [Mat.overlay(Hue.terracotta, alpha: 0.42)]; plate.isHidden = false
            } else if session.selected == i {
                g.materials = [Mat.overlay(Hue.paper, alpha: 0.5)]; plate.isHidden = false
            } else { plate.isHidden = true }
        }
        // door swing: tint cells with something in them
        let solid = session.layout.solidMap()
        for n in builder.overlays.childNodes where n.name?.hasPrefix("swing:") == true {
            let xy = n.name!.dropFirst(6).split(separator: ",").compactMap { Int($0) }
            let blocked = solid[Cell(xy[0], xy[1])] != nil
            n.geometry?.materials = [Mat.overlay(Hue.terracotta, alpha: blocked ? 0.38 : 0)]
        }
        drawZones()
    }

    private func drawZones() {
        zones.childNodes.forEach { $0.removeFromParentNode() }
        let piece = drag?.piece ?? session.selected
        guard let i = piece, session.level.has(.clearance) else { return }
        let k = session.kinds[i]
        guard let p = drag?.placement ?? session.placement(i), !k.zones.isEmpty else { return }
        let solid = session.layout.solidMap(excluding: i)
        for z in k.zones {
            for c in k.cells(of: z.rect, at: p) where session.room.isFloor(c) {
                let other = solid[c]
                let free = other == nil || (other! >= 0 && z.allows.contains(session.kinds[other!].id))
                let q = SCNNode(geometry: SCNPlane(width: CGFloat(cellSize) - 0.08, height: CGFloat(cellSize) - 0.08))
                (q.geometry as! SCNPlane).cornerRadius = 0.04
                q.geometry!.materials = [Mat.overlay(free ? Hue.sage : Hue.terracotta, alpha: free ? 0.32 : 0.45)]
                q.eulerAngles.x = -.pi / 2
                q.position = builder.center(c); q.position.y = 0.007
                q.renderingOrder = 9
                zones.addChildNode(q)
            }
        }
    }

    // MARK: - picking and projection

    /// Point on the floor (y = 0) under a screen point.
    func floorPoint(_ pt: CGPoint) -> SCNVector3? {
        let a = view.unprojectPoint(SCNVector3(Float(pt.x), Float(pt.y), 0))
        let b = view.unprojectPoint(SCNVector3(Float(pt.x), Float(pt.y), 1))
        let dy = b.y - a.y
        guard abs(dy) > 1e-5 else { return nil }
        let t = -a.y / dy
        return SCNVector3(a.x + (b.x - a.x) * t, 0, a.z + (b.z - a.z) * t)
    }

    func piece(at pt: CGPoint) -> Int? {
        let hits = view.hitTest(pt, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
        for h in hits {
            var n: SCNNode? = h.node
            while let c = n {
                if let name = c.name, name.hasPrefix("piece:"), let i = Int(name.dropFirst(6)) { return i }
                n = c.parent
            }
        }
        // fall back to the footprint under the finger (thin pieces like rugs)
        if let f = floorPoint(pt) {
            let (x, y) = builder.plan(f)
            let c = Cell(Int(x.rounded(.down)), Int(y.rounded(.down)))
            var rugHit: Int?
            for (i, p) in session.layout.placements.enumerated() {
                guard let p, session.kinds[i].cells(at: p).contains(c) else { continue }
                if session.kinds[i].layer == .solid { return i } else { rugHit = i }
            }
            return rugHit
        }
        return nil
    }

    /// Placement whose footprint is centered under a floor point.
    func placement(for i: Int, rotation r: Rotation, at f: SCNVector3) -> Placement {
        let (x, y) = builder.plan(f)
        let (w, h) = session.kinds[i].rotatedSize(r)
        var ox = Int((x - Double(w) / 2).rounded()), oy = Int((y - Double(h) / 2).rounded())
        // keep it on the plan so it never floats far away
        ox = max(-1, min(session.room.width - w + 1, ox)); oy = max(-1, min(session.room.height - h + 1, oy))
        return Placement(origin: Cell(ox, oy), rotation: r)
    }

    // MARK: - dragging (shared by the scene and the tray)

    struct Drag {
        let piece: Int
        let fromTray: Bool
        var rotation: Rotation
        var placement: Placement?
        var valid = false
        var original: Placement?
        var offset: CGPoint          // screen offset between finger and the piece center
        var lastPoint: CGPoint
        var lastTime: CFTimeInterval
        var overTray = false
    }
    private(set) var drag: Drag?
    private let lift: Float = 0.12

    func beginDrag(piece i: Int, fromTray: Bool, at pt: CGPoint) {
        guard drag == nil else { return }
        session.selected = i
        let original = session.placement(i)
        var offset = CGPoint(x: 0, y: -70)  // lifted above the finger so it stays visible
        if let o = original {
            let c = view.projectPoint(builder.position(session.kinds[i], o))
            offset = CGPoint(x: CGFloat(c.x) - pt.x, y: CGFloat(c.y) - pt.y)
            // keep at least a little above the finger
            offset.y = min(offset.y, -30)
        }
        drag = Drag(piece: i, fromTray: fromTray, rotation: session.rotation(i), placement: original, original: original,
                    offset: offset, lastPoint: pt, lastTime: CACurrentMediaTime())
        let node = pieceNodes[i]
        if original == nil {
            node.eulerAngles.y = Float(session.rotation(i).turns) * .pi / 2
        }
        node.isHidden = false
        Sound.shared.play(.pick)
        Haptics.shared.play(.select)
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.25
        builder.grid.opacity = 1
        SCNTransaction.commit()
        moveDrag(to: pt, first: true)
    }

    func moveDrag(to pt: CGPoint, first: Bool = false) {
        guard var d = drag else { return }
        let now = CACurrentMediaTime()
        let speed = hypot(pt.x - d.lastPoint.x, pt.y - d.lastPoint.y) / max(now - d.lastTime, 1 / 120)
        d.lastPoint = pt; d.lastTime = now
        Sound.shared.setSlide(speed: Double(speed))
        let overTray = pt.y > trayTop
        if overTray != d.overTray { onTrayHover?(overTray) }
        d.overTray = overTray
        let node = pieceNodes[d.piece]
        let target = CGPoint(x: pt.x + d.offset.x, y: pt.y + d.offset.y)
        guard !overTray, let f = floorPoint(target) else {
            node.isHidden = d.original == nil   // a new piece hides over the tray; a moved one waits at its spot
            ghost.isHidden = true
            if let o = d.original {
                SCNTransaction.begin(); SCNTransaction.animationDuration = 0.15
                node.position = builder.position(session.kinds[d.piece], o)
                SCNTransaction.commit()
            }
            drag = d
            return
        }
        node.isHidden = false
        let p = placement(for: d.piece, rotation: d.rotation, at: f)
        let changed = p != d.placement
        d.placement = p
        d.valid = session.canPlace(d.piece, p)
        drag = d
        let k = session.kinds[d.piece]
        var pos = builder.position(k, p); pos.y = lift
        SCNTransaction.begin()
        SCNTransaction.animationDuration = first ? 0 : 0.09
        node.position = pos
        node.eulerAngles.y = shortestYaw(from: node.eulerAngles.y, to: Float(d.rotation.turns) * .pi / 2)
        SCNTransaction.commit()
        if changed && !first { Haptics.shared.play(.snap); Sound.shared.play(.tick, volume: 0.5) }
        showGhost(k, p, valid: d.valid)
        refreshOverlays()
    }

    private func showGhost(_ k: FurnitureKind, _ p: Placement, valid: Bool) {
        let (w, h) = k.rotatedSize(p.rotation)
        let g = SCNPlane(width: CGFloat(w) * CGFloat(cellSize) - 0.03, height: CGFloat(h) * CGFloat(cellSize) - 0.03)
        g.cornerRadius = 0.05
        g.materials = [Mat.overlay(valid ? Hue.sage : Hue.terracotta, alpha: valid ? 0.42 : 0.5)]
        ghost.geometry = g
        ghost.eulerAngles.x = -.pi / 2
        let pos = builder.position(k, p)
        ghost.position = SCNVector3(pos.x, 0.008, pos.z)
        ghost.isHidden = false
    }

    /// Rotates the piece being dragged (turn button pressed mid-drag).
    func rotateDrag() {
        guard var d = drag else { return }
        d.rotation = d.rotation.next
        drag = d
        Sound.shared.play(.rotate); Haptics.shared.play(.rotate)
        moveDrag(to: d.lastPoint)
    }

    func endDrag(cancelled: Bool = false) {
        guard let d = drag else { return }
        drag = nil
        Sound.shared.setSlide(speed: 0)
        ghost.isHidden = true
        onTrayHover?(false)
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.3
        builder.grid.opacity = 0
        SCNTransaction.commit()
        let node = pieceNodes[d.piece]
        if d.overTray && !cancelled {
            if d.original != nil { session.remove(d.piece) } else { node.isHidden = true; Sound.shared.play(.toTray, volume: 0.5) }
            refreshOverlays()
            return
        }
        if !cancelled, let p = d.placement, d.valid {
            // settle: from the lifted spot down onto the floor
            session.place(d.piece, p)
            return
        }
        // can't go there: back where it was
        session.feedbackInvalid()
        if let o = d.original {
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.3
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            node.position = builder.position(session.kinds[d.piece], o)
            node.eulerAngles.y = shortestYaw(from: node.eulerAngles.y, to: Float(o.rotation.turns) * .pi / 2)
            SCNTransaction.commit()
        } else {
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.2
            node.opacity = 0
            SCNTransaction.completionBlock = { node.isHidden = true; node.opacity = 1 }
            SCNTransaction.commit()
        }
        refreshOverlays()
    }

    // MARK: - gestures

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard interactive else { return false }
        if g is UIPanGestureRecognizer { return piece(at: g.location(in: view)) != nil }
        return true
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let pt = g.location(in: view)
        switch g.state {
        case .began:
            guard let i = piece(at: pt) else { return }
            beginDrag(piece: i, fromTray: false, at: pt)
        case .changed: moveDrag(to: pt)
        case .ended: endDrag()
        default: endDrag(cancelled: true)
        }
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        guard interactive else { return }
        let i = piece(at: g.location(in: view))
        if session.selected != i {
            session.selected = i
            if i != nil { Haptics.shared.play(.select); Sound.shared.play(.button, volume: 0.6) }
        } else if i != nil {
            session.selected = nil
        }
        refreshOverlays()
    }

    @objc private func onDoubleTap(_ g: UITapGestureRecognizer) {
        guard interactive, let i = piece(at: g.location(in: view)) else { return }
        session.selected = i
        session.rotateSelected()
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        guard drag == nil else { return }
        switch g.state {
        case .changed:
            let old = zoom
            zoom = max(1, min(2.2, zoom * g.scale))
            g.scale = 1
            // zoom toward the fingers
            let pt = g.location(in: view)
            let unitsPerPoint = 2 * fitScale / zoom / view.bounds.height
            if zoom > 1.001 {
                let k = (1 - old / zoom)
                pan.x += (pt.x - view.bounds.midX) * unitsPerPoint * k * zoom / old
                pan.y -= (pt.y - (view.bounds.midY + (insets.top - insets.bottom) / 2)) * unitsPerPoint * k * zoom / old
                let (w, d) = builder.size
                let lim = max(w, d) / 2 * (1 - 1 / zoom) + 0.2
                pan.x = max(-lim, min(lim, pan.x)); pan.y = max(-lim, min(lim, pan.y))
            } else { pan = .zero }
            refit(animated: false)
        case .ended, .cancelled:
            if zoom < 1.05 { zoom = 1; pan = .zero; refit(animated: true) }
        default: break
        }
    }

    // MARK: - showcase (home screen and game intro)

    /// Pieces fall softly into place one after another, each with a thump and a light vibration.
    func dropIn(_ placements: [Placement], start: Double = 0.2, interval: Double = 0.32, feedback: Bool = true) {
        interactive = false
        session.setLayout(placements)
        let order = placements.indices.sorted { a, b in
            let ka = session.kinds[a], kb = session.kinds[b]
            if ka.layer != kb.layer { return ka.layer == .floor }
            return ka.w * ka.d > kb.w * kb.d
        }
        for (n, i) in order.enumerated() {
            let node = pieceNodes[i], k = session.kinds[i], p = placements[i]
            let target = builder.position(k, p)
            node.position = SCNVector3(target.x, 1.2, target.z)
            node.eulerAngles.y = Float(p.rotation.turns) * .pi / 2
            node.opacity = 0
            node.isHidden = false
            DispatchQueue.main.asyncAfter(deadline: .now() + start + Double(n) * interval) {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.5
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.75, 1)
                node.position = target
                node.opacity = 1
                SCNTransaction.completionBlock = {
                    guard feedback else { return }
                    Sound.shared.play(k.w * k.d >= 6 ? .placeHeavy : .place, volume: 0.7)
                    Haptics.shared.play(.introDrop)
                }
                SCNTransaction.commit()
            }
        }
    }

    func hide(kind: String) { for (i, k) in session.kinds.enumerated() where k.id == kind { pieceNodes[i].isHidden = true } }

    /// Slow endless turn of the camera (home screen).
    func drift() {
        let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 140))
        orbit.runAction(spin, forKey: "drift")
        driftTimer?.invalidate()
        driftTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            let m = self.orbit.presentation.worldTransform
            let a = atan2(Float(m.m31), Float(m.m33))   // yaw from the rotated +Z axis
            self.updateWalls(animated: true, yaw: a)
        }
    }
    private var driftTimer: Timer?

    deinit { driftTimer?.invalidate() }

    // MARK: - victory

    /// Warmer light, lamps up, a slow drift of the camera. `room` = where the room should sit on screen now.
    func celebrate(room newInsets: UIEdgeInsets? = nil) {
        interactive = false
        if let newInsets { savedInsets = insets; insetsSilently = newInsets; refit(animated: true) }
        session.selected = nil
        refreshOverlays()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1.6
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sun.light?.temperature = 3900
        sun.light?.intensity = (sun.light?.intensity ?? 900) * 1.12
        scene.lightingEnvironment.intensity *= 1.1
        cameraNode.camera?.exposureOffset = 0.3
        SCNTransaction.commit()
        builder.root.enumerateHierarchy { n, _ in
            if n.name == "lampshade" { n.geometry?.firstMaterial?.emission.intensity = 1.0 }
        }
        let spin = SCNAction.rotateBy(x: 0, y: CGFloat.pi / 12, z: 0, duration: 9)
        spin.timingMode = .easeInEaseOut
        orbit.runAction(spin)
    }
    private var savedInsets: UIEdgeInsets?
    private var insetsSilently: UIEdgeInsets { get { insets } set { suppressRefit = true; insets = newValue; suppressRefit = false } }
    private var suppressRefit = false

    func resetMood() {
        interactive = true
        if let s = savedInsets { insetsSilently = s; savedInsets = nil }
        orbit.removeAllActions()
        cameraNode.camera?.exposureOffset = 0.15
        applyMood(animated: true)
        placeCamera(animated: true)
    }
}
