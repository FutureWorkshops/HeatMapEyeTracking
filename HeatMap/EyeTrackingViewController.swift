//
//  ViewController.swift
//  HeatMap
//
//  Created by Andrew Zimmer on 6/11/18.
//  Copyright © 2018 AndrewZimmer. All rights reserved.
//

import UIKit
import SceneKit
import ARKit

struct PositionFrame: Codable {
    let position: CGPoint
    let timestamp: TimeInterval
}


/// Object that is able to use ARKit face detection to estimate the points to where the user is
/// looking into the screen. This data is estimated given the user's face mash, not direct pupil estimation.
protocol EyeTracker: class {
    
    /// This method will create an EyeTracker and replace the Root View Controller
    /// of the window, so the tracker can act over the full content.
    ///
    /// - Parameter window: Window where the EyeTracker will be applied
    /// - Returns: The instance of the EyeTracker, so the lifecycle can be controlled. It will be nil if faced error on loading
    static func buildTracker(tracking window: UIWindow) -> EyeTracker?
    
    
    /// This restores the state of the UIWindow to before the EyeTracker was activated
    ///
    /// - Parameter window: Window where the EyeTracker was be applied
    func restore(_ window: UIWindow)
    
    
    /// A simple control to enable/disable the tracker indicator
    /// useful for debug sessions
    var isShowingTarget: Bool { get set }
    
    
    /// Enable/disable the posibility to export the data tracked by the session.
    /// The data can be exported by tapping 3 times with 2 fingers in the screen.
    var isExportEnabled: Bool { get set }
}

protocol EmbedContent: class {
    var innerController: UIViewController? { get set }
}

extension EyeTracker where Self: UIViewController, Self: EmbedContent {
    static func buildTracker(tracking window: UIWindow) -> EyeTracker? {
        
        let bundle = Bundle(for: Self.self)
        let nib = UINib(nibName: String(describing: Self.self), bundle: bundle)
        
        guard let overlay = nib.instantiate(withOwner: nil, options: nil).first as? Self else {
            return nil
        }
        
        weak var controller = window.rootViewController
        window.rootViewController = overlay
        overlay.innerController = controller
        return overlay
    }
    
    func restore(_ window: UIWindow) {
        guard let innerController = self.innerController else {
            return
        }
        self.innerController = nil
        window.rootViewController = innerController
    }
}

extension EyeTrackingViewController: ARSCNViewDelegate {
    // Override to create and configure nodes for anchors added to the view's session.
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        return SCNNode()
    }
}

class EyeTrackingViewController: UIViewController, EyeTracker, EmbedContent {

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var contentView: UIView!
    
    let widthScale: Float = 0.0623908297 / 375.0
    let heightScale: Float = 0.135096943231532 / 812.0
    
    var phoneWidth = 0
    var phoneHeight = 0
    
    var m_data : [UInt8] = []
    var buffer: [PositionFrame] = []
    
    
    var positions: Array<simd_float2> = Array()
    let numPositions = 10;
    
    var eyeLasers : EyeLasers?
    var eyeRaycastData : RaycastData?
    var virtualPhoneNode: SCNNode = SCNNode()
    
    var screenWidth: Float = 0.0
    var screenHeigth: Float = 0.0
    
    weak var innerController: UIViewController? = nil {
        willSet {
            if let controller = self.innerController {
                controller.willMove(toParent: nil)
                controller.removeFromParent()
                controller.view?.removeFromSuperview()
            }
        }
        didSet {
            guard let viewController = self.innerController else {
                return
            }
            viewController.willMove(toParent: self)
            self.addChild(viewController)
            if self.isViewLoaded, let view = viewController.view {
                self.putContent(view)
            }
        }
    }
    
    var virtualScreenNode: SCNNode = {
        let screenGeometry = SCNPlane(width: 1, height: 1)
        screenGeometry.firstMaterial?.isDoubleSided = true
        screenGeometry.firstMaterial?.diffuse.contents = UIColor.green
        return SCNNode(geometry: screenGeometry)
    }()
    
//    lazy var heatMapNode:SCNNode = {
//        let node = SCNNode(geometry:SCNPlane(width: 2, height: 2))  // -1 to 1
//
//        let program = SCNProgram()
//        program.vertexFunctionName = "heatMapVert"
//        program.fragmentFunctionName = "heatMapFrag"
//
//        node.geometry?.firstMaterial?.program = program;
//        node.geometry?.firstMaterial?.blendMode = SCNBlendMode.add;
//
//        return node;
//    } ()
    
    var target : UIView = UIView()
    
    var isShowingTarget: Bool = true {
        didSet {
            guard isViewLoaded else {
                return
            }
            
            if self.isShowingTarget && self.target.superview == nil {
                self.view.addSubview(self.target)
            }
            
            if !self.isShowingTarget {
                self.target.removeFromSuperview()
            }
        }
    }
    var isExportEnabled: Bool = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.screenHeigth = Float(UIScreen.main.bounds.height)
        self.screenWidth = Float(UIScreen.main.bounds.width)
        self.phoneWidth = Int(self.screenWidth * 3.0);
        self.phoneHeight = Int(self.screenHeigth * 3.0);
        self.m_data = [UInt8](repeating: 0, count: self.phoneWidth * self.phoneHeight)
        
        self.target.backgroundColor = UIColor.red
        self.target.frame = CGRect.init(x: 0,y:0 ,width:25 ,height:25)
        self.target.layer.cornerRadius = 12.5
        if self.isShowingTarget {
            self.view.addSubview(target)
        }
        
        // Set the view's delegate
        self.sceneView.delegate = self
        self.sceneView.automaticallyUpdatesLighting = true
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(EyeTrackingViewController.exportBuffer))
        tapGesture.cancelsTouchesInView = false
        tapGesture.numberOfTapsRequired = 3
        tapGesture.numberOfTouchesRequired = 2
        self.view.addGestureRecognizer(tapGesture)
        
        // Show statistics such as fps and timing information
        self.sceneView.showsStatistics = true
        
        let device = self.sceneView.device!
        let eyeGeometry = ARSCNFaceGeometry(device: device)!
        self.eyeLasers = EyeLasers(geometry: eyeGeometry)
        self.eyeRaycastData = RaycastData(geometry: eyeGeometry)
        self.sceneView.scene.rootNode.addChildNode(self.eyeLasers!)
        self.sceneView.scene.rootNode.addChildNode(self.eyeRaycastData!)
        
        self.virtualPhoneNode.geometry?.firstMaterial?.isDoubleSided = true
        self.virtualPhoneNode.addChildNode(self.virtualScreenNode)

//        sceneView.scene.rootNode.addChildNode(heatMapNode)
        
        self.sceneView.scene.rootNode.addChildNode(self.virtualPhoneNode)
        self.sceneView.alpha = 0.0
        
        if let content = self.innerController?.view, content.superview == nil {
            self.putContent(content)
        }
    }
    
    func putContent(_ content: UIView) {
        self.contentView.addSubview(content)
        NSLayoutConstraint.activate([self.contentView.topAnchor.constraint(equalTo: content.topAnchor),
                                     self.contentView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                                     self.contentView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                                     self.contentView.trailingAnchor.constraint(equalTo: content.trailingAnchor)])
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Create a session configuration
        let configuration = ARFaceTrackingConfiguration()
        // Run the view's session
        self.sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Pause the view's session
        self.sceneView.session.pause()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        self.eyeLasers?.transform = node.transform;
        self.eyeRaycastData?.transform = node.transform;
        self.eyeLasers?.update(withFaceAnchor: faceAnchor)
        self.eyeRaycastData?.update(withFaceAnchor: faceAnchor)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        self.virtualPhoneNode.transform = (self.sceneView.pointOfView?.transform)!
        
        let options : [String: Any] = [SCNHitTestOption.backFaceCulling.rawValue: false,
                                       SCNHitTestOption.searchMode.rawValue: 1,
                                       SCNHitTestOption.ignoreChildNodes.rawValue : false,
                                       SCNHitTestOption.ignoreHiddenNodes.rawValue : false]
        
        let hitTestLeftEye = self.virtualPhoneNode.hitTestWithSegment(
            from: self.virtualPhoneNode.convertPosition(self.eyeRaycastData!.leftEye.worldPosition, from:nil),
            to:  self.virtualPhoneNode.convertPosition(self.eyeRaycastData!.leftEyeEnd.worldPosition, from:nil),
            //from: self.eyeRaycastData!.leftEye.worldPosition,
            //to:  self.eyeRaycastData!.leftEyeEnd.worldPosition,
            options: options)
        
        let hitTestRightEye = self.virtualPhoneNode.hitTestWithSegment(
            from: self.virtualPhoneNode.convertPosition(self.eyeRaycastData!.rightEye.worldPosition, from:nil),
            to:  self.virtualPhoneNode.convertPosition(self.eyeRaycastData!.rightEyeEnd.worldPosition, from:nil),
            //from: self.eyeRaycastData!.rightEye.worldPosition,
            //to:  self.eyeRaycastData!.rightEyeEnd.worldPosition,
            options: options)
        
        if let leftEye = hitTestLeftEye.first, let rightEye = hitTestRightEye.first {

            var coords = self.screenPositionFromHittest(leftEye, secondResult:rightEye)
            //print("x:\(coords.x) y: \(coords.y)")
            
            let point = CGPoint(x: CGFloat(coords.x), y: CGFloat(coords.y))
            
            //SAVE OPERATION
            self.buffer.append(PositionFrame(position: point, timestamp: Date().timeIntervalSince1970))
            
//            incrementHeatMapAtPosition(x:Int(coords.x * 3), y:Int(coords.y * 3))  // convert from points to pixels here
            
//            let nsdata = NSData.init(bytes: &m_data, length: phoneWidth * phoneHeight)
//            heatMapNode.geometry?.firstMaterial?.setValue(nsdata, forKey: "heatmapTexture")
            
            DispatchQueue.main.async(execute: { [weak self] in
                self?.target.center = point
            })
        }
    }
    
    func screenPositionFromHittest(_ result1: SCNHitTestResult, secondResult result2: SCNHitTestResult) -> simd_float2 {
        let iPhoneXPointSize = simd_float2(self.screenWidth, self.screenHeigth)  // size of iPhoneX in points
        let iPhoneXMeterSize = simd_float2(self.screenWidth * widthScale, self.screenHeigth * heightScale)

        let xLC = ((result1.localCoordinates.x + result2.localCoordinates.x) / 2.0)
        var x = xLC / (iPhoneXMeterSize.x / 2.0) * iPhoneXPointSize.x
        
        let yLC = -((result1.localCoordinates.y + result2.localCoordinates.y) / 2.0);
        var y = yLC / (iPhoneXMeterSize.y / 2.0) * iPhoneXPointSize.y + 312
        
        x = Float.maximum(Float.minimum(x, iPhoneXPointSize.x-1), 0)
        y = Float.maximum(Float.minimum(y, iPhoneXPointSize.y-1), 0)
        
        // Do just a bit of smoothing. Nothing crazy.
        self.positions.append(simd_float2(x,y));
        if self.positions.count > self.numPositions {
            self.positions.removeFirst()
        }

        var total = simd_float2(0,0);
        for pos in self.positions {
            total.x += pos.x
            total.y += pos.y
        }

        total.x /= Float(self.positions.count)
        total.y /= Float(self.positions.count)
        
        return total;
    }

    
    @IBAction func exportBuffer() {
        guard self.isExportEnabled else {
            return
        }
        
        let cleanBuffer = self.buffer.filter({ $0.position.x > 0.0 && $0.position.y > 0.0 })
        
        guard cleanBuffer.count > 0 else {
            return
        }
        
        guard let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        
        guard let content = try? JSONEncoder().encode(cleanBuffer) else {
            return
        }
        
        let fileCacheURL = cacheURL.appendingPathComponent("eyetrackingbuffer_\(Date().timeIntervalSince1970)").appendingPathExtension("json")
        
        guard let _ = try? content.write(to: fileCacheURL) else {
            return
        }
        
        let activityController = UIActivityViewController(activityItems: [fileCacheURL], applicationActivities: nil)
        self.present(activityController, animated: true, completion: nil)
    }
    
    /** Note. I'm not using this because I couldn't figure out how to set an MTLTexture to an SCNProgram because Scenekit has terrible
        documentation. That said you should DEFINITELY fix this if you ever plan to use something like this in production.
        So I left it in for reference. */
//    func metalTextureFromArray(_ array:[UInt8], width:Int, height:Int) -> MTLTexture {
//        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.a8Unorm, width: width, height: height, mipmapped: false)
//
//        let texture = self.sceneView.device?.makeTexture(descriptor: textureDescriptor)
//        let region = MTLRegion(origin: MTLOriginMake(0, 0, 0), size: MTLSizeMake(width, height, 1))
//        texture?.replace(region: region, mipmapLevel: 0, withBytes: array, bytesPerRow: width)
//
//        return texture!
//    }
//
//    func incrementHeatMapAtPosition(x: Int, y: Int) {
//        let radius:Int = 46; // in pixels
//        let maxIncrement:Float = 25;
//
//        for curX in x - radius ... x + radius {
//            for curY in y - radius ... y + radius {
//                let idx = posToIndex(x:curX, y:curY)
//
//                if (idx != -1) {
//                    let offset = simd_float2(Float(curX - x), Float(curY - y));
//                    let len = simd_length(offset)
//
//                    if (len >= Float(radius)) {
//                        continue;
//                    }
//
//                    let incrementValue = Int((1 - (len / Float(radius))) * maxIncrement);
//                    if (255 - m_data[idx] > incrementValue) {
//                        m_data[idx] = UInt8(Int(m_data[idx]) + incrementValue)
//                    } else {
//                        m_data[idx] = 255
//                    }
//                }
//            }
//        }
//    }
//
//    func posToIndex(x:Int, y:Int) -> Int {
//        if (x < 0 || x >= phoneWidth ||
//            y < 0 || y >= phoneHeight) {
//            return -1;
//        }
//
//        return x + y * phoneWidth;
//    }
}
