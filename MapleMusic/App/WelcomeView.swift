import SwiftUI

struct WelcomeView: View {
    let continueAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer().frame(height: proxy.size.height * 0.29)

                Image(systemName: "waveform")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 70, height: 70)
                    .background(Color(red: 1, green: 0.8, blue: 0), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)

                Text("Добро пожаловать в Maple Music")
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 48)

                Text("Ваша музыка, плейлисты и Моя волна — в одном месте.")
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)

                Button("Начать", action: continueAction)
                    .buttonStyle(AccentActionButtonStyle())
                    .padding(.top, 88)
                    .padding(.horizontal, 24)

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.black)
        .background(.white)
        .preferredColorScheme(.light)
    }
}
