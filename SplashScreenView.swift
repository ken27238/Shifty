import SwiftUI

struct SplashScreenView: View {
    @State private var isAnimating = false
    let gradientColors = [Color.blue, Color.purple]
    
    var body: some View {
        ZStack {
            RadialGradient(gradient: Gradient(colors: gradientColors),
                           center: .center,
                           startRadius: 100,
                           endRadius: 300)
                .ignoresSafeArea()
            
            VStack {
                Image(systemName: "clock.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.white)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isAnimating)
                
                Text("Shifty")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
