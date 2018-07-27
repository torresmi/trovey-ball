import UIKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var planeDetectedLabel: UILabel!
    @IBOutlet weak var remainingBallsLabel: UILabel!
    
    private let basketBallName = "basketball"
    private let basketName = "basket"
    private let activePlaneName = "activePlane"
    private let scoreDetectorName = "detector"
    private let logoName = "logo"
    private let ringName = "ring"
    private let ballRadius: Float = 0.2
    private let ballRestitution: Float = 0.2
    private let yCurveMultiplier: Float = 3
    private let remainBallsTextPrefix = "Balls left: "
    private let confettiAnimTime = 4
    private let finishDelayTime = 3
    
    private var model = Model()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .vertical
        
        sceneView.delegate = self
        sceneView.scene.physicsWorld.contactDelegate = self
        sceneView.autoenablesDefaultLighting = true
        sceneView.session.run(configuration)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(sender:)))
        sceneView.addGestureRecognizer(tapGestureRecognizer)
        tapGestureRecognizer.cancelsTouchesInView = false
    }
    
    deinit {
        finish()
    }
    
    @objc func handleTap(sender: UITapGestureRecognizer) {
        guard let sceneView = sender.view as? ARSCNView else { return }
        let touchLocation = sender.location(in: sceneView)
        let hitTestResult = sceneView.hitTest(touchLocation, types: [.existingPlane])
        
        if !hitTestResult.isEmpty {
            addBasket(hitTestResult: hitTestResult.first!)
            remainingBallsLabel.text = formattedRemainingBallsText(remaining: model.remainingBalls)
            remainingBallsLabel.isHidden = false
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARPlaneAnchor else { return }
        node.name = activePlaneName
        DispatchQueue.main.async {
            self.planeDetectedLabel.isHidden = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) {
            self.planeDetectedLabel.isHidden = true
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        model.buildPower()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if model.basketAdded {
            shootBall()
        }
        model.resetPower()
    }
    
    private func finish() {
        model = Model()
        remainingBallsLabel.isHidden = true
        remainingBallsLabel.text = remainBallsTextPrefix
        
        removeFromNode(
            node: worldRootNode(),
            names: [
                basketBallName,
                basketName,
                activePlaneName,
                scoreDetectorName
            ]
        )
    }
    
    private func addBasket(hitTestResult: ARHitTestResult) {
        guard !model.basketAdded else { return }
        
        let basketScene = SCNScene(named: "art.scnassets/Basketball.scn")
        let basketNode = basketScene?.rootNode.childNode(withName: basketName, recursively: false)
        
        let logoNode = basketScene?.rootNode.childNode(withName: logoName, recursively: true)
        logoNode?.geometry?.firstMaterial?.diffuse.contents = #imageLiteral(resourceName: "Logo")
        
        let ringNode = basketScene?.rootNode.childNode(withName: ringName, recursively: true)
        
        if let basketNode = basketNode {
            
            basketNode.position = positionFromTransform(transform: hitTestResult.worldTransform)
            basketNode.physicsBody = SCNPhysicsBody(
                type: .static,
                shape: SCNPhysicsShape(
                    node: basketNode,
                    options: [
                        SCNPhysicsShape.Option.keepAsCompound: true,
                        SCNPhysicsShape.Option.type: SCNPhysicsShape.ShapeType.concavePolyhedron
                    ]
                )
            )
            
            worldRootNode().addChildNode(basketNode)
            
            let ringPosition = ringNode?.worldPosition ?? SCNVector3(0, 0, -30)
            
            let detectorNode = scoreDetectorNode()
            detectorNode.position = SCNVector3(ringPosition.x, ringPosition.y - 2, ringPosition.z)
            worldRootNode().addChildNode(detectorNode)

            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                self.model.addBasket()
            }
        }
    }
    
    private func shootBall() {
        guard model.hasRemainingBalls() else { return }
        removeBalls()
        guard let pointOfView = sceneView.pointOfView else { return }
        
        let transform = pointOfView.transform
        let location = SCNVector3(transform.m41, transform.m42, transform.m43)
        let orientation = SCNVector3(-transform.m31, -transform.m32, -transform.m33)
        let position = location + orientation
        
        let ball = createBall()
        ball.position = position
        
        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(node: ball))
        body.restitution = CGFloat(ballRestitution)
        
        let power = model.power
        let force = SCNVector3(
            orientation.x * power,
            orientation.y * power * yCurveMultiplier,
            orientation.z * power
        )
        body.applyForce(force, asImpulse: true)
        body.categoryBitMask = BitMaskCategory.ball.rawValue
        body.contactTestBitMask = BitMaskCategory.ring.rawValue
        
        ball.physicsBody = body
        worldRootNode().addChildNode(ball)
        
        removeAvailableBall()
    }
    
    private func createBall() -> SCNNode {
        let ball = SCNNode(geometry: SCNSphere(radius: CGFloat(ballRadius)))
        ball.geometry?.firstMaterial?.diffuse.contents = #imageLiteral(resourceName: "Ball")
        ball.name = basketBallName
        return ball
    }
    
    private func removeBalls() {
        removeFromNode(node: worldRootNode(), names: [basketBallName])
    }
    
    private func removeAvailableBall() {
        model.removeAvailableBall()
        remainingBallsLabel.text = formattedRemainingBallsText(remaining: model.remainingBalls)
        
        if !model.hasRemainingBalls() {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(finishDelayTime)) {
                if (!self.model.didScore) {
                    self.showBuyMoreModal()
                }
                self.finish()
            }
        }
    }
    
    private func removeFromNode(node: SCNNode, names: Set<String>) {
        node.enumerateChildNodes { (node, _) in
            if let name = node.name {
                if names.contains(name) {
                    node.removeFromParentNode()
                }
            }
        }
    }
    
    private func formattedRemainingBallsText(remaining: Int) -> String {
        let template = remainBallsTextPrefix + "%d"
        return String(format: template, remaining)
    }
    
    private func showBuyMoreModal() {
        let alertController = UIAlertController(
            title: "Tasty Microtransaction",
            message: "Buy more balls for just $0.99, or buy an introduction for just $9.99",
            preferredStyle: UIAlertControllerStyle.alert
        )
        alertController.addAction(emptyAlertAction(title: "Dismiss"))
        alertController.addAction(emptyAlertAction(title: "Buy Balls"))
        alertController.addAction(emptyAlertAction(title: "Buy Intro"))
        
        present(alertController, animated: true, completion: nil)
    }
    
    private func showConnectedModal() {
        let alertController = UIAlertController(
            title: "Congrats!",
            message: "Ok I will introduce you!",
            preferredStyle: UIAlertControllerStyle.alert
        )
        alertController.addAction(emptyAlertAction(title: "Dismiss"))

        present(alertController, animated: true, completion: nil)
    }
    
    private func scoreDetectorNode() -> SCNNode {
        let detectorSize = CGFloat(0.001)
        let detectorNode = SCNNode(geometry: SCNPlane(width: detectorSize, height: detectorSize))
        detectorNode.name = scoreDetectorName

        detectorNode.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(node: detectorNode))
        detectorNode.physicsBody?.categoryBitMask = BitMaskCategory.ring.rawValue
        
        let blockingNode = SCNNode(geometry: SCNPlane(width: detectorSize, height: detectorSize))
        blockingNode.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(node: blockingNode))
        blockingNode.position = SCNVector3(0, 0, 0.1)
        
        detectorNode.addChildNode(blockingNode)
        
        return detectorNode
    }
    
    private func score() {
        model.score()

        let confetti = SCNParticleSystem(named: "art.scnassets/Confetti.scnp", inDirectory: nil)
        confetti?.loops = false
        confetti?.particleLifeSpan = CGFloat(confettiAnimTime)
        let target = worldRootNode().childNode(withName: ringName, recursively: true)
        if let target = target {
            confetti?.emitterShape = target.geometry
            let confettiNode = SCNNode()
            confettiNode.addParticleSystem(confetti!)
            confettiNode.position = target.worldPosition
            worldRootNode().addChildNode(confettiNode)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(finishDelayTime)) {
                self.finish()
                self.showConnectedModal()
            }
        }
    }
    
    private func emptyAlertAction(title: String) -> UIAlertAction {
        return UIAlertAction(title: title, style: UIAlertActionStyle.default, handler: nil)
    }
    
    private func worldRootNode() -> SCNNode {
        return sceneView.scene.rootNode
    }

    private func positionFromTransform(transform: matrix_float4x4) -> SCNVector3 {
        let position = transform.columns.3
        return SCNVector3(position.x, position.y, position.z)
    }
}

extension ViewController : SCNPhysicsContactDelegate {
    
    enum BitMaskCategory: Int {
        case ball = 1
        case ring = 2
    }
    
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let nodeA = contact.nodeA

        if (nodeA.name == scoreDetectorName) {
            score()
        }
    }
}


func +(left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.x + right.x, left.y + right.x, left.z + right.z)
}
