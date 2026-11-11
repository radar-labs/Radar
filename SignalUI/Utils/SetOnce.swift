final class SetOnce<Value> {
    private var _value: Value?
    private let lock = NSLock()

    var value: Value? {
        lock.withLock { _value }
    }

    @discardableResult
    func setOnce(_ newValue: Value) -> Bool {
        lock.withLock {
            guard _value == nil else { return false }
            _value = newValue
            return true
        }
    }
}
