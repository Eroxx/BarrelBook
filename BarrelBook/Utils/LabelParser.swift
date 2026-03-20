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

// MARK: - Internal block type (text + visual prominence)

private struct LabelBlock {
    let text: String
    let area: CGFloat   // normalized bounding-box area — larger = more prominent on label
    let confidence: Float
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
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
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

    // MARK: - Core parsing

    private static func parseObservations(_ observations: [VNRecognizedTextObservation]) -> ScannedBottleData {
        // Build blocks that retain bounding-box area so we can rank by visual size
        let blocks: [LabelBlock] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first, candidate.confidence > 0.3 else { return nil }
            let bb = obs.boundingBox
            let area = bb.width * bb.height
            return LabelBlock(text: candidate.string.trimmingCharacters(in: .whitespaces),
                              area: area,
                              confidence: candidate.confidence)
        }

        guard !blocks.isEmpty else { return ScannedBottleData() }

        let fullText = blocks.map { $0.text }.joined(separator: " ")

        var data = ScannedBottleData()
        data.proof      = extractProof(from: fullText)
        data.age        = extractAge(from: fullText)
        data.type       = extractType(from: fullText)
        data.distillery = extractDistillery(from: fullText, blocks: blocks)

        // Name uses bounding-box size to find the most visually prominent text
        data.name = extractName(from: blocks,
                                knownDistillery: data.distillery,
                                knownType: data.type)

        // If name matches the distillery exactly, try for a more specific bottle name
        if let n = data.name, let d = data.distillery,
           n.lowercased() == d.lowercased() {
            data.name = extractName(from: blocks,
                                    knownDistillery: data.distillery,
                                    knownType: data.type,
                                    skipFirst: true)
        }

        return data
    }

    // MARK: - Proof

    private static func extractProof(from text: String) -> String? {
        // Matches: "90 Proof", "90-Proof", "45% ABV", "45% alc/vol", "45%alc"
        let patterns = [
            #"(\d{2,3}(?:\.\d{1,2})?)\s*proof"#,
            #"(\d{2,3}(?:\.\d{1,2})?)\s*%\s*(?:alc|abv)"#,
            #"(\d{2,3}(?:\.\d{1,2})?)%"#,  // bare % with no label nearby — lower priority
        ]
        for (i, pattern) in patterns.enumerated() {
            guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            let matchStr = String(text[match])
            guard let numRange = matchStr.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { continue }
            let raw = String(matchStr[numRange])
            guard let num = Double(raw) else { continue }

            // Bare % pattern: ignore values that look like percentages out of context (e.g. "5%")
            if i == 2 && num < 30 { continue }

            // ABV → proof conversion
            if i >= 1 {
                let proof = num * 2
                return proof.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(proof)) : String(format: "%.1f", proof)
            }
            return raw
        }
        return nil
    }

    // MARK: - Age

    private static func extractAge(from text: String) -> String? {
        // "Aged 12 Years", "12 Year Old", "12YO", "12-Year"
        let patterns = [
            #"aged\s+(\d{1,2})\s*year"#,
            #"(\d{1,2})\s*[-–]?\s*(?:year|yr|y\.o\.?)\w*"#,
        ]
        for pattern in patterns {
            guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            let matchStr = String(text[match])
            guard let numRange = matchStr.range(of: #"\d+"#, options: .regularExpression) else { continue }
            let num = Int(String(matchStr[numRange])) ?? 0
            guard num >= 2 && num <= 50 else { continue }   // sanity check
            return "\(num) Year"
        }
        return nil
    }

    // MARK: - Type

    private static func extractType(from text: String) -> String? {
        // Ordered most-specific → least-specific
        let types: [(keywords: [String], label: String)] = [
            (["kentucky straight bourbon"],          "Kentucky Straight Bourbon"),
            (["straight bourbon whiskey",
              "straight bourbon"],                   "Straight Bourbon"),
            (["tennessee whiskey"],                  "Tennessee Whiskey"),
            (["straight rye whiskey",
              "straight rye"],                       "Straight Rye"),
            (["rye whiskey"],                        "Rye"),
            (["american single malt"],               "American Single Malt"),
            (["single malt scotch whisky",
              "single malt scotch",
              "single malt"],                        "Single Malt Scotch"),
            (["scotch whisky", "scotch"],            "Scotch"),
            (["irish whiskey"],                      "Irish Whiskey"),
            (["japanese whisky"],                    "Japanese Whisky"),
            (["canadian whisky"],                    "Canadian Whisky"),
            (["wheat whiskey", "wheat whisky"],      "Wheat Whiskey"),
            (["bourbon whiskey", "bourbon"],         "Bourbon"),
            (["blended whiskey", "blended whisky",
              "blended malt"],                       "Blended"),
        ]
        let lower = text.lowercased()
        for entry in types {
            if entry.keywords.contains(where: { lower.contains($0) }) {
                return entry.label
            }
        }
        return nil
    }

    // MARK: - Distillery

    private static func extractDistillery(from text: String, blocks: [LabelBlock]) -> String? {
        // Try individual blocks first (more precise than full-text substring)
        for block in blocks.sorted(by: { $0.area > $1.area }) {
            if let match = knownDistillery(matching: block.text) { return match }
        }
        // Fall back to full-text scan
        return knownDistillery(matching: text)
    }

    private static func knownDistillery(matching text: String) -> String? {
        let known: [String] = [
            // Kentucky / American
            "Buffalo Trace", "Heaven Hill", "Wild Turkey", "Four Roses",
            "Maker's Mark", "Jim Beam", "Woodford Reserve", "Knob Creek",
            "Bulleit", "Angel's Envy", "Old Forester", "George Dickel",
            "Barton", "Sazerac", "MGP", "Brown-Forman", "Michter's",
            "Bardstown Bourbon", "Castle & Key", "Wilderness Trail",
            "New Riff", "Rabbit Hole", "Peerless", "Stoli",
            "Jack Daniel", "Jack Daniel's",
            "Evan Williams", "Elijah Craig", "Larceny",
            "W.L. Weller", "Weller", "E.H. Taylor", "Blanton's",
            "Eagle Rare", "Colonel E.H. Taylor",
            "Booker's", "Baker's", "Basil Hayden",
            "Old Granddad", "Old Crow", "Old Fitzgerald",
            "Henry McKenna", "Very Old Barton",
            "1792", "Rowan's Creek", "Noah's Mill",
            "Jefferson's", "Redemption", "High West",
            "Whistlepig", "WhistlePig", "Smooth Ambler",
            "Breckenridge", "Stranahan's", "Laws Whiskey",
            "Westland", "Balcones", "TX Whiskey",
            "FEW Spirits", "Koval", "Garrison Brothers",
            // Scotch
            "Laphroaig", "Glenfiddich", "Macallan", "Glenlivet",
            "Ardbeg", "Balvenie", "Oban", "Dalmore", "Highland Park",
            "Glenfarclas", "GlenDronach", "Bruichladdich", "Springbank",
            "Bowmore", "Lagavulin", "Talisker", "Glenmorangie",
            "Aberlour", "Craigellachie", "BenRiach", "Glen Grant",
            "Tobermory", "Bunnahabhain", "Caol Ila", "Kilchoman",
            "Isle of Jura", "Deanston", "Tomatin", "Aberfeldy",
            "Edradour", "Glayva", "Compass Box",
            // Irish
            "Jameson", "Bushmills", "Redbreast", "Green Spot",
            "Yellow Spot", "Midleton", "Teeling", "Tullamore",
            "Connemara", "Writers' Tears",
            // Japanese
            "Nikka", "Suntory", "Hibiki", "Yamazaki", "Hakushu",
            "Yoichi", "Miyagikyo", "Chichibu",
            // Canadian
            "Crown Royal", "Canadian Club", "Forty Creek",
        ]
        let lower = text.lowercased()
        // Prefer exact / close matches over substring matches
        return known.first { lower.contains($0.lowercased()) }
    }

    // MARK: - Name (bounding-box ranked)

    private static let nameSkipWords = [
        "distillery", "distilled", "bottled by", "bottled in", "product of",
        "government warning", "according to", "contains", "sulfites",
        "750ml", "700ml", "750 ml", "1 liter", "1l", "1.75",
        "www.", ".com", ".net", "established", "copyright", "©", "℃", "℉",
        "alc/vol", "alc.", "proof", "% alc", "% abv",
        "aged in", "aged at", "matured", "hand crafted", "hand selected",
        "batch", "barrel no", "barrel #", "bottle no", "bottle #",
        "rick house", "rickhouse", "non-chill", "non chill",
        "natural color", "naturally",
    ]

    private static func extractName(
        from blocks: [LabelBlock],
        knownDistillery: String?,
        knownType: String?,
        skipFirst: Bool = false
    ) -> String? {
        // Sort by bounding-box area descending — the name is almost always the largest text
        let sorted = blocks.sorted { $0.area > $1.area }

        let candidates = sorted.filter { block in
            let lower = block.text.lowercased()
            guard block.text.count >= 3, block.text.count <= 60 else { return false }
            guard !nameSkipWords.contains(where: { lower.contains($0) }) else { return false }
            // Skip pure numbers or percentages
            guard block.text.range(of: #"^\d+[\s%]?"#, options: .regularExpression) == nil else { return false }
            // Skip if it IS the distillery or type
            if let d = knownDistillery, lower == d.lowercased() { return false }
            if let t = knownType, lower == t.lowercased() { return false }
            // Skip very generic single words that appear on every bottle
            let genericWords: Set<String> = ["whiskey", "whisky", "bourbon", "scotch",
                                              "distillery", "distilleries", "spirits", "aged"]
            if genericWords.contains(lower) { return false }
            return true
        }

        let result = skipFirst ? candidates.dropFirst().first : candidates.first
        return result.map { capitalize($0.text) }
    }

    // MARK: - Helpers

    /// Capitalizes each word, preserving all-caps abbreviations like "E.H." or "WL"
    private static func capitalize(_ text: String) -> String {
        // If all-caps and short, leave as-is (e.g. "BLANTON'S")
        if text == text.uppercased() && text.count <= 20 {
            return text.capitalized
        }
        return text
    }
}
