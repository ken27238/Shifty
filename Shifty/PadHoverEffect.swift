//
//  PadHoverEffect.swift
//  Shifty
//

import SwiftUI

extension View {
    /// Pointer hover highlight on iPad; no-op on platforms without it.
    @ViewBuilder
    func padHoverEffect() -> some View {
        #if os(iOS)
        hoverEffect(.highlight)
        #else
        self
        #endif
    }
}
