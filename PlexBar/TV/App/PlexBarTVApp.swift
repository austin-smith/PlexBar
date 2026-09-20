import SwiftUI

@main
struct PlexBarTVApp: App {
    @State private var store = TVAppStore()

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

private struct TVRootView: View {
    @Environment(TVAppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPlayerPresented = false

    var body: some View {
        @Bindable var store = store

        Group {
            if store.isConnected {
                TVMainTabView()
            } else {
                TVConnectionView()
            }
        }
        .task {
            await store.restoreSession()
            if !store.isConnected, !store.hasAuthorizedAccount {
                store.startPlexDeviceAuthorization()
            }
        }
        .onOpenURL(perform: store.openTopShelfURL)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, store.isConnected, !store.isLoadingHome {
                Task { await store.refreshAll() }
            }
        }
        .fullScreenCover(item: $store.playbackRequest, onDismiss: {
            store.dismissPlayer()
            isPlayerPresented = false
        }) { request in
            TVPlayerView(request: request)
                .environment(store)
                .onAppear { isPlayerPresented = true }
        }
        .modifier(TVWatchedStateFailureAlert(
            isActive: store.playbackRequest == nil && !isPlayerPresented && store.errorMessage == nil
        ))
        .alert("PlexBar", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Something went wrong.")
        }
    }
}

private struct TVMainTabView: View {
    @Environment(TVAppStore.self) private var store

    var body: some View {
        @Bindable var store = store

        TabView(selection: $store.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: TVAppStore.Tab.home) {
                TVHomeView()
            }
            Tab("Libraries", systemImage: "rectangle.stack.fill", value: TVAppStore.Tab.libraries) {
                TVLibrariesView()
            }
            Tab(
                "Search",
                systemImage: "magnifyingglass",
                value: TVAppStore.Tab.search,
                role: .search
            ) {
                TVSearchView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: TVAppStore.Tab.settings) {
                TVSettingsView()
            }
        }
    }
}
