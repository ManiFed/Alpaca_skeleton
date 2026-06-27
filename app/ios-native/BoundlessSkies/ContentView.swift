import SwiftUI

struct ContentView: View {
    @State private var viewModel = SpeechHapticsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    SpeakingStatusView(
                        isSpeaking: viewModel.isSpeaking,
                        isPaused: viewModel.isPaused,
                        statusMessage: viewModel.statusMessage,
                        progressDescription: viewModel.progressDescription
                    )

                    SpeechControlsSection(viewModel: viewModel)

                    Divider()

                    HapticTestSection(
                        supportsHaptics: viewModel.supportsHaptics,
                        onStyleTapped: { viewModel.testHaptic(style: $0) },
                        onPatternTapped: { viewModel.playComplexHapticPattern() }
                    )
                }
                .padding()
            }
            .navigationTitle("Speech & Haptics")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    ContentView()
}