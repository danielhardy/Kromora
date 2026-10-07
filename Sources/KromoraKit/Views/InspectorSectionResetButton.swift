import SwiftUI

struct InspectorSectionResetButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            ResetIconButton(title, disabled: disabled, action: action)
        }
    }
}
