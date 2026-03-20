// LabelParser.swift
// BarrelBook
//
// Parses whiskey label text (from Vision OCR) into structured bottle data.
// Self-contained — no UI dependencies. Safe to remove alongside BottleScannerView.swift.

import Vision
import UIKit

// MARK: - Result type

struct ScannedBottleData {
    var name: String?
    var distillery: String?
    var type: String?
    var proof: String?
    var age: String?

    var isEmpty: Bool {
        [name, distillery, type, proof, age].allSatisfy { $0 == nil }
    }
}

// MARK: - Parser

enum LabelParser {

    /// Runs Vision OCR on the given image (off main thread) and returns parsed data on the main thread.
    static func parse(from image: UIImage, completion: @escaping (ScannedBottleData) -> Void) {
        guard let cgImage = image.cgImage else {
            DispatchQueue.main.async { completion(ScannedBottleData()) }
            return
        }

        let request = VNRecognizeTextRequest { request, _ in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let result = parseObservations(observations)
            DispatchQueue.main.async { completion(result) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Internal parsing

    private static func parseObservations(_ observations: [VNRecognizedTextObservation]) -> ScannedBottleData {
        let blocks = observations
            .compactMap { $0.topCandidates(1).first }
            .filter { $0.confidence > 0.4 }
            .map { $0.string }

        let fullText = blocks.joined(separator: " ")

        var data = ScannedBottleData()
        data.proof      = extractProof(from: fullText)
        data.age        = extractAge(from: fullText)
        data.type       = extractType(from: fullText)
        data.distillery = extractDistillery(from: fullText)
        data.name       = extractName(from: blocks, knownDistillery: data.distillery, knownType: data.type)
        return data
    }

    // MARK: - Field extractors

    private static func extractProof(from text: String) -> String? {
        // "90 Proof", "45% ABV", "45% alc/vol"
        let patterns = [
            #"(\d{2,3}(?:\.\d)?)\s*proof"#,
            #"(\d{2,3}(?:\.\d{1,2})?)\s*%\s*(?:alc|abv)"#,
        ]
        for pattern in patterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
               let numMatch = String(text[match]).range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) {
                let raw = String(String(text[match])[numMatch])
                // Convert ABV % → proof
                if pattern.contains("alc|abv"), let abv = Double(raw) {
                    let proof = abv * 2
                    return proof.truncatingRemainder(dividingBy: 1) == 0
                        ? String(Int(proof)) : String(format: "%.1f", proof)
                }
                return raw
            }
        }
        return nil
    }

    private static func extractAge(from text: String) -> String? {
        // "12 Year", "18 Years Old", "12YO", "Aged 12 Years"
        let patterns = [
            #"aged\s+(\d{1,2})\s*year"#,
            #"(\d{1,2})\s*(?:year|yr|y\.o\.?)\w*"#,
        ]
        for pattern in patterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
               let numMatch = String(text[match]).range(of: #"\d+"#, options: .regularExpression) {
                return String(String(text[match])[numMatch]) + " Year"
            }
        }
        return nil
    }

    private static func extractType(from text: String) -> String? {
        // Ordered most-specific → least-specific so "Straight Bourbon" beats "Bourbon"
        let types: [(keywords: [String], label: String)] = [
            (["kentucky straight bourbon", "straight bourbon whiskey"], "Straight Bourbon"),
            (["tennessee whiskey"],                                      "Tennessee Whiskey"),
            (["straight rye whiskey"],                                   "Straight Rye"),
            (["rye whiskey"],                                            "Rye"),
            (["american single malt"],                                   "American Single Malt"),
            (["single malt scotch", "scotch whisky", "scotch"],         "Scotch"),
            (["irish whiskey"],                                          "Irish Whiskey"),
            (["japanese whisky"],                                        "Japanese Whisky"),
            (["bourbon whiskey", "bourbon"],                             "Bourbon"),
            (["blended whiskey", "blended whisky"],                      "Blended"),
        ]
        let lower = text.lowercased()
        for entry in types {
            if entry.keywords.contains(where: { lower.contains($0) }) {
                return entry.label
            }
        }
        return nil
    }

    private static func extractDistillery(from text: String) -> String? {
        let known = [
            "Buffalo Trace", "Heaven Hill", "Wild Turkey", "Four Roses", "Maker's Mark",
            "Jim Beam", "Jack Daniel", "Woodford Reserve", "Knob Creek", "Bulleit",
            "Angel's Envy", "Old Forester", "George Dickel", "Barton", "Sazerac",
            "Bardstown", "Castle & Key", "Wilderness Trail", "New Riff", "Rabbit Hole",
            "Peerless", "Michter's", "Brown-Forman", "MGP",
            "Laphroaig", "Glenfiddich", "Macallan", "Glenlivet", "Ardbeg",
            "Balvenie", "Oban", "Dalmore", "Highland Park", "Glenfarclas",
            "GlenDronach", "Bruichladdich", "Springbank",
        ]
        let lower = text.lowercased()
        return known.first { lower.contains($0.lowercased()) }
    }

    private static func extractName(from blocks: [String], knownDistillery: String?, knownType: String?) -> String? {
        let skipPatterns = [
            "distill", "bottled", "product of", "government warning",
            "contains", "750ml", "700ml", "1 liter", "www.", ".com",
            "established", "copyright", "℃", "℉",
        ]
        let candidates = blocks.filter { block in
            let lower = block.lowercased()
            guard block.count >= 3, block.count <= 50 else { return false }
            guard !skipPatterns.contains(where: { lower.contains($0) }) else { return false }
            guard block.range(of: #"^\d+[\s\%]"#, options: .regularExpression) == nil else { return false }
            if let d = knownDistillery, lower == d.lowercased() { return false }
            if let t = knownType, lower == t.lowercased() { return false }
            return true
        }
        return candidates.first
    }
}
