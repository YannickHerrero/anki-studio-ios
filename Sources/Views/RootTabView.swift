import SwiftUI

/// Top-level tab bar: add a source, browse the library of sessions (the main
/// navigation between videos), and settings.
struct RootTabView: View {
    @State private var selection = 0
    @ObservedObject private var reviewNav = ReviewNav.shared

    var body: some View {
        tabs
            // The card template's green drives the whole app.
            .tint(Theme.accent)
            .onAppear {
                // UI-test / screenshot hook: seed a demo session when empty.
                if ProcessInfo.processInfo.environment["SEED_DEMO"] == "1",
                   SessionStore.shared.sessions.isEmpty {
                    DemoSession.create(into: .shared)
                }
            }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.1, *) {
            baseTabs
                // Liquid Glass companion: while a review session is on screen,
                // its line navigation floats in a glass capsule by the tab bar.
                .tabViewBottomAccessory(isEnabled: reviewNav.active != nil) {
                    if let vm = reviewNav.active {
                        ReviewAccessory(vm: vm)
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            baseTabs
        }
    }

    // A single-tab TabView with the bar hidden: the Library owns the screen
    // (Settings lives behind its gear button), while the TabView shell keeps
    // the Liquid Glass bottom accessory available for review.
    private var baseTabs: some View {
        TabView(selection: $selection) {
            LibraryTab()
                .toolbar(.hidden, for: .tabBar)
                .tag(0)
        }
    }
}

/// Prev / next line controls rendered inside the tab bar's glass accessory.
private struct ReviewAccessory: View {
    @ObservedObject var vm: ReviewViewModel

    var body: some View {
        HStack {
            Button {
                Haptics.tap()
                vm.prev()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!vm.canPrev)

            Text("Line \(vm.index + 1) / \(vm.session.cues.count)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 110)

            Button {
                Haptics.tap()
                vm.next()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!vm.canNext)
        }
        .font(.title3)
        .padding(.horizontal, 8)
    }
}

/// Library wrapper that supports the REVIEW_INDEX screenshot hook: when set,
/// it pushes straight into review for the newest session on launch.
private struct LibraryTab: View {
    @State private var autoOpened = false

    var body: some View {
        if ProcessInfo.processInfo.environment["REVIEW_INDEX"] != nil,
           !autoOpened, let first = SessionStore.shared.sessions.first {
            NavigationStack {
                ReviewView(session: first)
                    .id(first.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Library") { autoOpened = true }
                        }
                    }
            }
        } else {
            LibraryView()
        }
    }
}

#Preview {
    RootTabView()
}
