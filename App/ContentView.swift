import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(uiColor: Theme.background).ignoresSafeArea()
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image("Poppy")
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityIdentifier("poppy")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PoppyTerminal")
                            .font(.custom(Theme.fontRegular, size: 22))
                            .foregroundStyle(Color(uiColor: Theme.accent))
                            .accessibilityIdentifier("title")
                        Text("F0 - pipeline")
                            .font(.custom(Theme.fontRegular, size: 13))
                            .foregroundStyle(Color(uiColor: Theme.subtext0))
                    }
                    Spacer()
                }
                .padding(.horizontal)
                DemoTerminalView()
                    .accessibilityIdentifier("terminal")
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: Theme.surface1), lineWidth: 1))
                    .padding(.horizontal)
            }
            .padding(.top, 8)
        }
    }
}
