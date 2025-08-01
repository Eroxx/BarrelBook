import SwiftUI

struct ThreeWayToggle: View {
    @Binding var state: ToggleState
    let label: String
    let explanation: String?
    let onChanged: ((ToggleState) -> Void)?
    @State private var showingExplanation = false
    
    init(label: String, state: Binding<ToggleState>, explanation: String? = nil, onChanged: ((ToggleState) -> Void)? = nil) {
        self.label = label
        self._state = state
        self.explanation = explanation
        self.onChanged = onChanged
    }
    
    var body: some View {
        HStack {
            // The main toggle button
            Button {
                // Cycle to the next state
                state = state.nextState
                
                // Trigger haptic feedback
                HapticManager.shared.selectionFeedback()
                
                // Notify of state change if callback provided
                onChanged?(state)
            } label: {
                HStack {
                    Text(label)
                    
                    Spacer()
                    
                    // The toggle indicator
                    switch state {
                    case .all:
                        Text("All")
                            .foregroundColor(.secondary)
                            .frame(width: 50)
                    case .yes:
                        Text("Yes")
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                            .frame(width: 50)
                    case .no:
                        Text("No")
                            .foregroundColor(.red)
                            .fontWeight(.medium)
                            .frame(width: 50)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Only show info button if explanation is provided
            if let _ = explanation {
                Button {
                    showingExplanation = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
                .alert(label, isPresented: $showingExplanation) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(explanation ?? "")
                }
            }
        }
    }
}

// Preview
struct ThreeWayToggle_Previews: PreviewProvider {
    @State static var allState: ToggleState = .all
    @State static var yesState: ToggleState = .yes
    @State static var noState: ToggleState = .no
    
    static var previews: some View {
        List {
            ThreeWayToggle(
                label: "All State", 
                state: $allState,
                explanation: "This is an explanation of the All State toggle"
            )
            ThreeWayToggle(
                label: "Yes State", 
                state: $yesState, 
                explanation: "This is an explanation of the Yes State toggle"
            )
            ThreeWayToggle(
                label: "No State", 
                state: $noState
            )
        }
    }
} 