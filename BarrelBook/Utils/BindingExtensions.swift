import SwiftUI

extension Binding {
    /// Adds a side effect to be performed when the value changes.
    /// - Parameter onChange: Closure to execute when the value changes
    /// - Returns: A binding that triggers the side effect on change
    func onChange(_ onChange: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { newValue in
                self.wrappedValue = newValue
                onChange(newValue)
            }
        )
    }
} 