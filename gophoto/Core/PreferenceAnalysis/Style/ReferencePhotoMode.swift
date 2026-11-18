//
//  ReferencePhotoMode.swift
//  gophoto
//
//  Which taste rules a preference's photos get (15–16 Nov):
//  - favorites ("Photos I love", Mode 1): every photo is liked; scenes vote, one question per
//    shot size only when the votes are not clear.
//  - allOfMe ("All photos of me", Mode 2): every photo of the user alone, good and bad; no votes,
//    the user picks in a short knockout (`StyleBracket`).
//  The mode is kept per preference in `ReferencePhotoModeStore` (outside the preference file,
//  so its saved format does not change).
//

import Foundation

nonisolated enum ReferencePhotoMode: String, Codable, Sendable, CaseIterable {
    case favorites
    case allOfMe

    var title: String {
        switch self {
        case .favorites: "Photos I love"
        case .allOfMe: "All photos of me"
        }
    }

    /// Most reference photos a preference of this mode can hold (17 Nov). Mode 2 gathers every
    /// photo of the user, so it gets more room; each loaded photo costs ~3 MB of memory (1024 px).
    var maxPhotos: Int {
        switch self {
        case .favorites: 100
        case .allOfMe: 200
        }
    }
}

/// Which mode a preference was made with, by preference id (UserDefaults). Missing = favorites
/// (every preference made before 16 Nov).
nonisolated enum ReferencePhotoModeStore {
    private static func key(_ id: UUID) -> String { "referencePhotoMode." + id.uuidString }

    static func mode(for id: UUID) -> ReferencePhotoMode {
        UserDefaults.standard.string(forKey: key(id)).flatMap(ReferencePhotoMode.init(rawValue:)) ?? .favorites
    }

    static func set(_ mode: ReferencePhotoMode, for id: UUID) {
        UserDefaults.standard.set(mode.rawValue, forKey: key(id))
    }
}
