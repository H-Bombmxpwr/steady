//
//  PrivacyShieldView.swift
//  75
//
//  Created by Hunter Baisden on 9/4/25.
//

import SwiftUI

/// The app-icon motif — a gradient tile with the signature diagonal line.
/// Reused by the launch screen and the app-switcher privacy cover so both
/// read as "Steady," not "locked."
struct BrandMark: View {
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Theme.gradient
            Capsule()
                .fill(.white)
                .frame(width: size * 0.60, height: size * 0.17)
                .rotationEffect(.degrees(26))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 8)
    }
}

/// The themed brand backdrop: adaptive background with a breath of accent at
/// the top, the app mark, and the wordmark. Optionally shows a progress bar.
struct BrandSplashView: View {
    var showProgress = false
    var progress: Double = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            LinearGradient(colors: [Theme.accent.opacity(0.18), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                BrandMark(size: 92)
                Text("Steady")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gradient)
                if showProgress {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface2)
                        Capsule().fill(Theme.gradient)
                            .frame(width: 190 * max(0, min(1, progress)))
                    }
                    .frame(width: 190, height: 6)
                    .padding(.top, 4)
                }
            }
        }
    }
}

/// Cold-launch loading screen: the brand backdrop plus a progress bar that
/// fills while the store and first queries settle, then fades into the app.
struct LaunchLoadingView: View {
    var onDone: () -> Void
    @State private var progress: Double = 0

    var body: some View {
        BrandSplashView(showProgress: true, progress: progress)
            .task {
                withAnimation(.easeInOut(duration: 0.9)) { progress = 1 }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                onDone()
            }
    }
}

/// Shown over the app in the app switcher / when backgrounded, so nothing
/// private is readable in the multitasking preview. Deliberately NOT a lock
/// screen — it's the same branded cover as launch (the photo lock is the
/// only thing that actually locks).
struct PrivacyShieldView: View {
    var body: some View {
        BrandSplashView()
    }
}
