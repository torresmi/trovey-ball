import Foundation
import Each

class Model {
    
    private static let initialPower: Float = 1.0
    private static let initialBallCount = 3
    
    private let timer = Each(0.05).seconds
    
    private(set) var basketAdded = false
    private(set) var power = initialPower
    private(set) var remainingBalls = initialBallCount
    private(set) var didScore = false
    
    func resetPower() {
        timer.stop()
        power = Model.initialPower
    }
    
    func buildPower() {
        guard basketAdded else { return }
        
        timer.perform { () -> NextStep in
            self.power = self.power + 1
            return .continue
        }
    }
    
    func score() {
        remainingBalls = 0
        didScore = true
    }
    
    func removeAvailableBall() {
        remainingBalls -= 1
    }
    
    func hasRemainingBalls() -> Bool {
        return remainingBalls > 0
    }
    
    func addBasket() {
        basketAdded = true
    }
}
