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
                        Text(title).font(titleFont).lineLimit(1)
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
                // Section content that reports more than the rail offered (a segmented picker's
                // intrinsic width, say) is placed at that wider size and overflows the right
                // edge while previews publish. Clamp every section to the width it is given.
                FitsProposedWidth(reportsProposedHeight: false) {
                    content()
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle() {
        // The sole animation source for expand/collapse. A previous revision also applied
        // `.animation(..., value: isExpanded)` here; every expansion write already funnels
        // through this method, so the modifier only duplicated the transaction. Keeping one
        // explicit source avoids stacking overlapping animated transactions on the scroll
        // view's content size — overlapping size transactions are what widen the window for
        // AppKit's display-cycle constraint re-entrancy (KRMA-687).
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
    /// The scroll root claims a finite proposed height; nested section clamps must report
    /// their content's height so a parent stack's height proposal cannot inflate them.
    var reportsProposedHeight = true

    /// The proposal the child was last measured with. `placeSubviews` reuses it verbatim
    /// so the child is never measured with one proposal and placed with another: a
    /// measure/place mismatch reports a new size after placement, which keeps the
    /// surrounding scroll view's content size churning and schedules extra
    /// ScrollViewHelper transactions — the update class at the center of KRMA-687.
    struct Cache {
        var proposal: ProposedViewSize = .unspecified
        var lastProposedWidth: CGFloat?
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        guard let child = subviews.first else { return .zero }
        // A vertical ScrollView can briefly measure its content with an unspecified width while
        // child state is updating. Reusing the last viewport width keeps ideal child sizes from
        // widening the scroll document during that pass. A concrete proposal still updates the
        // cache immediately, so resizing the inspector remains responsive.
        let width: CGFloat
        // Only a finite width is a real viewport width. A scroll view also probes with
        // `.infinity` (max-size) and `0` (min-size); caching those would make later unspecified
        // passes, and the placement proposal, resolve to an unbounded width.
        if let proposedWidth = proposal.width, proposedWidth.isFinite, proposedWidth > 0 {
            width = proposedWidth
            cache.lastProposedWidth = proposedWidth
        } else if let lastProposedWidth = cache.lastProposedWidth {
            width = lastProposedWidth
        } else {
            width = child.sizeThatFits(.unspecified).width
        }
        let measure = ProposedViewSize(width: width, height: proposal.height)
        cache.proposal = measure
        let childSize = child.sizeThatFits(measure)
        return CGSize(
            width: width,
            height: reportsProposedHeight ? (proposal.height ?? childSize.height) : childSize.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        subviews.first?.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            // Place at the width actually granted, so a probe pass that overwrote the cached
            // proposal cannot widen the child beyond the inspector rail.
            proposal: ProposedViewSize(width: bounds.width, height: cache.proposal.height)
        )
    }
}
