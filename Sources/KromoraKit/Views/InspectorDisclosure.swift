import SwiftUI

/// Shared type and spacing scale for the inspector's tab content. Custom layouts can still differ,
/// while headings, controls, and supporting copy keep the same visual rhythm.
enum InspectorStyle {
    static let panelTitle = Font.headline
    static let sectionTitle = Font.body.weight(.semibold)
    static let nestedSectionTitle = Font.subheadline.weight(.semibold)
    static let fieldLabel = Font.caption
    static let fieldValue = Font.callout
    static let helperText = Font.caption
    static let secondaryHelperText = Font.caption2

    static let contentSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 12
    static let contentInset: CGFloat = 16
    static let sectionContentInset: CGFloat = 10
}

struct InspectorPanelHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(InspectorStyle.panelTitle)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A full-width inspector disclosure row.
///
/// The row is one keyboard-operable toggle, rather than a native disclosure whose hit target can
/// be limited to its chevron. Keeping the content outside the button also means nested sections
/// receive their own independent toggle action.
struct InspectorDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    var titleFont: Font
    var trailingActionTitle: String?
    var trailingActionEnabled: Bool
    var trailingAction: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        _ title: String,
        isExpanded: Binding<Bool>,
        titleFont: Font = InspectorStyle.sectionTitle,
        trailingActionTitle: String? = nil,
        trailingActionEnabled: Bool = true,
        trailingAction: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.titleFont = titleFont
        self.trailingActionTitle = trailingActionTitle
        self.trailingActionEnabled = trailingActionEnabled
        self.trailingAction = trailingAction
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: toggle) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .accessibilityHidden(true)
                        Text(title).font(titleFont)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Double-tap to \(isExpanded ? "collapse" : "expand")")
                .accessibilityAddTraits(.isToggle)
                .accessibilityRemoveTraits(.isButton)

                if let trailingActionTitle, let trailingAction {
                    Button(action: trailingAction) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!trailingActionEnabled)
                    .help(trailingActionTitle)
                    .accessibilityLabel(trailingActionTitle)
                }
            }

            if isExpanded {
                content()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }
}

/// Vertical inspector scrolling that stays inside the column.
///
/// A wide row otherwise becomes the scroll document's width. The column then
/// clips the leading edge, so labels slide out of the sidebar they belong to.
struct InspectorScrollingContent<Content: View>: View {
    @ViewBuilder private var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView(.vertical) {
            FitsProposedWidth {
                content()
            }
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }
}

/// Reports the width the parent offered, even when a child would rather be wider.
struct FitsProposedWidth: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = proposal.width ?? child.sizeThatFits(.unspecified).width
        let childSize = child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
        return CGSize(width: width, height: proposal.height ?? childSize.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        subviews.first?.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}
