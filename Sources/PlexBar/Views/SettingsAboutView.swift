import AppKit
import SwiftUI

struct SettingsAboutView: View {
    @Environment(\.openURL) private var openURL

    private let sourceURL = URL(string: "https://github.com/austin-smith/PlexBar")!
    private let plexURL = URL(string: "https://www.plex.tv/")!

    private var versionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? AppConstants.productVersion
    }

    private var copyrightYear: String {
        String(Calendar.current.component(.year, from: .now))
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

                VStack(spacing: 4) {
                    Text(AppConstants.appName)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)

                    Text("Telemetry for Plex")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 16) {
                Text("A lightweight macOS menu bar app for Plex server telemetry.")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Version")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(versionString)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    Text("© \(copyrightYear) Austin Smith")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 12)
                }
            }

            VStack(spacing: 8) {
                Button("GitHub") {
                    openURL(sourceURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            VStack(spacing: 8) {
                Divider()
                    .padding(.horizontal, 24)

                HStack(spacing: 4) {
                    Text("Powered by")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Button("Plex") {
                        openURL(plexURL)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
    }

}
