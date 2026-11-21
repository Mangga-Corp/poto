//
//  AppPatternBackground.swift
//  gophoto
//
// Created by Sebastian Darren on 12/10/26.
//

import SwiftUI

struct AppPatternBackground: View {
    private let surface = PotoDesign.background

    var body: some View {
        surface
            .ignoresSafeArea()
    }
}

extension View {
    /// Applies the standard Poto background (plain surface color)
    func appPatternBackground() -> some View {
        background {
            AppPatternBackground()
        }
    }
}
