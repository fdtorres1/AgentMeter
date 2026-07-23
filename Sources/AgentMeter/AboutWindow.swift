import SwiftUI

struct AboutView: View {
    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
            }
            Text("AgentMeter")
                .font(.title2.bold())
            Text(L("Version \(version)"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(L("Menu bar monitor for AI coding usage limits."))
                .font(.callout)
                .multilineTextAlignment(.center)

            Divider().padding(.horizontal, 24)

            VStack(spacing: 4) {
                Link(L("Website & source code"), destination: URL(string: "https://github.com/fdtorres1/AgentMeter")!)
                Link(L("Report an issue"), destination: URL(string: "https://github.com/fdtorres1/AgentMeter/issues")!)
                Link("Support ♥", destination: URL(string: "https://www.buymeacoffee.com/fdtorres")!)
            }
            .font(.callout)

            Divider().padding(.horizontal, 24)

            VStack(spacing: 2) {
                Text(L("Auto-updates powered by Sparkle (MIT License)."))
                Text(L("Provider endpoint research credits CodexBar by Peter Steinberger."))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Text("© 2026 Felix Torres · MIT License")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 340)
    }
}
