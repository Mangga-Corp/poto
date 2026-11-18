//
//  StyleTraceView.swift
//  gophoto
//
//  TEMPORARY (16 Nov): the grouping history of one preference, step by step. See StyleTrace.swift
//  for how to remove it.
//

import SwiftUI
import UIKit

struct StyleTraceView: View {
    let preferenceID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var trace: StyleTraceData?
    @State private var loaded = false

    private var preference: Preference? { PreferencesViewModel.shared.preference(id: preferenceID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GoPhotoDesign.background)
        .navigationTitle("How it was grouped")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task {
            guard !loaded else { return }
            trace = StyleTraceStore.load(for: preferenceID)
            loaded = true
        }
    }

    @ViewBuilder private var content: some View {
        if let trace {
            VStack(alignment: .leading, spacing: 4) {
                Text(trace.mode == ReferencePhotoMode.allOfMe.rawValue ? "Mode 2 · All photos of me" : "Mode 1 · Photos I love")
                    .font(GoPhotoDesign.cardTitle)
                Text("Analysed \(trace.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(GoPhotoDesign.caption).foregroundStyle(GoPhotoDesign.secondaryText)
            }
            if let review = trace.review { reviewSection(review) }
            ForEach(trace.shots, id: \.key) { shot in shotSection(shot, mode: trace.mode) }
        } else if loaded {
            Text("No grouping saved for this preference yet. Analyse it again to record one.")
                .font(GoPhotoDesign.body).foregroundStyle(GoPhotoDesign.secondaryText)
        }
    }

    // MARK: Review (Mode 2)

    private func reviewSection(_ r: StyleTraceData.Review) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("0 · Review (Find my photos for me)")
            line("\(r.candidates) photos of you found")
            line("\(r.junk) dropped as junk (utility / very low aesthetics)")
            line("\(r.bursts.reduce(0) { $0 + $1.count - 1 }) merged into \(r.bursts.count) bursts (one kept each)")
            line("\(r.overLimit) over the 100-photo limit")
            line("\(r.selected) selected")
        }
    }

    // MARK: One shot size

    private func shotSection(_ shot: StyleTraceData.Shot, mode: String) -> some View {
        let byID = Dictionary(shot.photos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let choice = preference?.analysis?.styleVariant(forKey: shot.key)?.styleChoice
        return VStack(alignment: .leading, spacing: 16) {
            Text(title(shot.key)).font(GoPhotoDesign.sectionTitle)
            Text("\(shot.photos.count) photos").font(GoPhotoDesign.caption).foregroundStyle(GoPhotoDesign.secondaryText)

            // 1. Scenes
            VStack(alignment: .leading, spacing: 8) {
                heading("1 · Scenes (same day + place/time + look alike)")
                let scenes = Dictionary(grouping: shot.photos) { $0.scene ?? -1 }
                ForEach(scenes.keys.sorted(), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 4) {
                        line("Scene \(key + 1) · \(scenes[key]!.count) photos")
                        thumbRow(scenes[key]!.map(\.id))
                    }
                }
            }

            // 2. Styles
            VStack(alignment: .leading, spacing: 8) {
                heading("2 · Styles (no opposing pair inside one style)")
                ForEach(Array(shot.styles.enumerated()), id: \.offset) { s, style in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Style \(letter(s))").font(GoPhotoDesign.cardTitle)
                            if shot.candidateStyles.contains(s) {
                                Text("candidate").font(GoPhotoDesign.smallLabel)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(GoPhotoDesign.tagBackground, in: Capsule())
                                    .foregroundStyle(GoPhotoDesign.tagText)
                            }
                        }
                        line("\(style.photoIDs.count) photos · \(style.scenes) scenes · votes \(String(format: "%.2f", style.votes))")
                        thumbRow(style.photoIDs, target: style.targetID, representatives: style.representativeIDs,
                                 shared: Set(shot.photos.filter { $0.styles.count > 1 }.map(\.id)))
                        if let target = style.targetID.flatMap({ byID[$0] }) {
                            line("Target: " + values(target))
                        }
                    }
                    .padding(12)
                    .background(GoPhotoDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                Text("Border = target (medoid) · dot = scene representative · S = fits more than one style (vote split)")
                    .font(GoPhotoDesign.caption).foregroundStyle(GoPhotoDesign.secondaryText)
            }

            // 3. Decision
            VStack(alignment: .leading, spacing: 6) {
                heading("3 · Decision")
                if mode == ReferencePhotoMode.allOfMe.rawValue {
                    line("No votes in Mode 2. Knockout between: " + shot.candidateStyles.map(letter).joined(separator: ", "))
                    line("(Mode 1 rule would say: \(shot.rule))")
                } else {
                    line("Rule: \(shot.rule) (clear = ≥ 5 votes and top ≥ 1.75 × the rest)")
                }
            }

            // 4. Answers + result
            VStack(alignment: .leading, spacing: 6) {
                heading("4 · Answers")
                if let choice {
                    if choice.answers.isEmpty {
                        line(choice.status == "chosen" ? "Picked style \(styleLetter(choice.chosen, shot))" : "Status: \(choice.status)")
                    }
                    ForEach(Array(choice.answers.enumerated()), id: \.offset) { i, answer in
                        line("Q\(i + 1): shown \(answer.shown.map { styleLetter($0, shot) }.joined(separator: ", ")) → picked \(styleLetter(answer.chosen, shot))")
                    }
                    if choice.status == "ask" { line("Not answered yet: the most-voted / first style is used for now.") }
                } else {
                    line("No style choice stored.")
                }
                let usedStyle = choice.flatMap { c in shot.candidateStyles.indices.contains(c.chosen) ? shot.candidateStyles[c.chosen] : nil }
                    ?? (shot.styles.count == 1 ? 0 : nil)
                if let usedStyle, shot.styles.indices.contains(usedStyle),
                   let target = shot.styles[usedStyle].targetID {
                    heading("Result: style \(letter(usedStyle))")
                    HStack(alignment: .top, spacing: 12) {
                        thumb(target, size: 110, highlight: true)
                        if let photo = byID[target] { Text(values(photo)).font(GoPhotoDesign.caption) }
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func heading(_ text: String) -> some View {
        Text(text).font(GoPhotoDesign.smallLabel).foregroundStyle(GoPhotoDesign.primary)
    }

    private func line(_ text: String) -> some View {
        Text(text).font(GoPhotoDesign.secondaryBody).foregroundStyle(GoPhotoDesign.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func thumbRow(_ ids: [String], target: String? = nil, representatives: [String] = [],
                          shared: Set<String> = []) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    thumb(id, highlight: id == target, dot: representatives.contains(id), shared: shared.contains(id))
                }
            }
        }
    }

    private func thumb(_ id: String, size: CGFloat = 56, highlight: Bool = false, dot: Bool = false,
                       shared: Bool = false) -> some View {
        let image = preference?.photos.first { $0.id.uuidString == id }?.image
        return ZStack(alignment: .topTrailing) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() } else { GoPhotoDesign.secondaryBackground }
            }
            .frame(width: size, height: size * 4 / 3)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(highlight ? GoPhotoDesign.primary : .clear, lineWidth: 3))
            if dot { Circle().fill(GoPhotoDesign.primary).frame(width: 10, height: 10).padding(4) }
            if shared {
                Text("S").font(.caption2.bold()).foregroundStyle(.white).padding(3)
                    .background(GoPhotoDesign.warning, in: Circle()).padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(width: size, height: size * 4 / 3)
    }

    private func values(_ p: StyleTraceData.Photo) -> String {
        func f(_ v: Double?, _ unit: String = "") -> String { v.map { String(format: "%.2f", $0) + unit } ?? "–" }
        return "height \(f(p.vantageFaces, " faces")) · tilt \(f(p.pitchDegrees, "°")) · centre \(f(p.centreX)) · size \(f(p.size))"
            + (p.isScreenshot ? " · screenshot" : "")
    }

    private func title(_ key: String) -> String {
        key == BodyPosture.sitting.rawValue ? "Sitting" : (PresetAnalysis.ShotSize(rawValue: key)?.title ?? key)
    }

    private func letter(_ i: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return letters.indices.contains(i) ? String(letters[i]) : "\(i + 1)"
    }

    /// Candidate index (as stored in the preset) → the style's letter.
    private func styleLetter(_ candidate: Int, _ shot: StyleTraceData.Shot) -> String {
        shot.candidateStyles.indices.contains(candidate) ? letter(shot.candidateStyles[candidate]) : "#\(candidate)"
    }
}
