//
//  PrivacyShieldView.swift
//  75
//
//  Created by Hunter Baisden on 9/4/25.
//

import SwiftUI

struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            // Full black with a subtle blur look so nothing is readable
            Rectangle().fill(.black).opacity(1).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.white)
                Text("Locked").font(.headline).foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}
