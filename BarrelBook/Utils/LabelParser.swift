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

    // MARK: - Brand → Distillery map
    //
    // Keys   = the name that appears on the bottle label (used as the bottle NAME)
    // Values = the actual producing distillery (used as DISTILLERY field)
    // This prevents brand names from being misidentified as distilleries.

    private static let brandToDistillery: [(brand: String, distillery: String)] = [
        // Buffalo Trace Distillery brands
        ("Blanton's",               "Buffalo Trace"),
        ("Eagle Rare",              "Buffalo Trace"),
        ("W.L. Weller",            "Buffalo Trace"),
        ("Weller",                  "Buffalo Trace"),
        ("E.H. Taylor",             "Buffalo Trace"),
        ("Colonel E.H. Taylor",     "Buffalo Trace"),
        ("Pappy Van Winkle",        "Buffalo Trace"),
        ("Van Winkle",              "Buffalo Trace"),
        ("Benchmark",               "Buffalo Trace"),
        ("Ancient Age",             "Buffalo Trace"),
        ("Buffalo Trace",           "Buffalo Trace"),

        // Heaven Hill brands
        ("Elijah Craig",            "Heaven Hill"),
        ("Evan Williams",           "Heaven Hill"),
        ("Larceny",                 "Heaven Hill"),
        ("Old Fitzgerald",          "Heaven Hill"),
        ("Henry McKenna",           "Heaven Hill"),
        ("Parker's Heritage",       "Heaven Hill"),
        ("Fighting Cock",           "Heaven Hill"),
        ("Bernheim",                "Heaven Hill"),

        // Jim Beam / Beam Suntory brands
        ("Booker's",                "Jim Beam"),
        ("Baker's",                 "Jim Beam"),
        ("Basil Hayden",            "Jim Beam"),
        ("Knob Creek",              "Jim Beam"),
        ("Old Grand-Dad",           "Jim Beam"),
        ("Old Granddad",            "Jim Beam"),
        ("Old Crow",                "Jim Beam"),
        ("Little Book",             "Jim Beam"),
        ("Jim Beam",                "Jim Beam"),

        // Wild Turkey brands
        ("Russell's Reserve",       "Wild Turkey"),
        ("Rare Breed",              "Wild Turkey"),
        ("Longbranch",              "Wild Turkey"),
        ("Wild Turkey",             "Wild Turkey"),

        // Four Roses
        ("Four Roses",              "Four Roses"),

        // Maker's Mark
        ("Maker's 46",              "Maker's Mark"),
        ("Maker's Mark",            "Maker's Mark"),

        // Woodford Reserve
        ("Woodford Reserve",        "Woodford Reserve"),

        // Brown-Forman / Old Forester
        ("Old Forester",            "Old Forester"),
        ("Early Times",             "Brown-Forman"),

        // Jack Daniel's
        ("Gentleman Jack",          "Jack Daniel's"),
        ("Sinatra Select",          "Jack Daniel's"),
        ("Jack Daniel's",           "Jack Daniel's"),
        ("Jack Daniel",             "Jack Daniel's"),

        // George Dickel
        ("George Dickel",           "George Dickel"),

        // MGP / sourced brands
        ("Bulleit",                 "MGP"),
        ("Jefferson's",             "MGP"),
        ("Redemption",              "MGP"),

        // Angel's Envy
        ("Angel's Envy",            "Louisville Distilling Co."),

        // Barton brands
        ("1792",                    "Barton"),
        ("Very Old Barton",         "Barton"),
        ("Ten High",                "Barton"),

        // Kentucky Bourbon Distillers
        ("Rowan's Creek",           "Kentucky Bourbon Distillers"),
        ("Noah's Mill",             "Kentucky Bourbon Distillers"),

        // Craft / independent American
        ("High West",               "High West"),
        ("WhistlePig",              "WhistlePig"),
        ("Michter's",               "Michter's"),
        ("Stranahan's",             "Stranahan's"),
        ("Westland",                "Westland"),
        ("Balcones",                "Balcones"),
        ("Garrison Brothers",       "Garrison Brothers"),
        ("Laws Whiskey",            "Laws Whiskey House"),
        ("Breckenridge",            "Breckenridge Distillery"),
        ("Koval",                   "Koval"),
        ("FEW Spirits",             "FEW Spirits"),
        ("Smooth Ambler",           "Smooth Ambler"),
        ("Rabbit Hole",             "Rabbit Hole"),
        ("New Riff",                "New Riff"),
        ("Castle & Key",            "Castle & Key"),
        ("Wilderness Trail",        "Wilderness Trail"),
        ("Peerless",                "Peerless"),
        ("Bardstown Bourbon",       "Bardstown Bourbon Company"),
        ("Sazerac",                 "Sazerac"),
        ("MGP",                     "MGP"),

        // Scotch
        ("Laphroaig",               "Laphroaig"),
        ("Glenfiddich",             "Glenfiddich"),
        ("Macallan",                "Macallan"),
        ("Glenlivet",               "Glenlivet"),
        ("Ardbeg",                  "Ardbeg"),
        ("Balvenie",                "Balvenie"),
        ("Oban",                    "Oban"),
        ("Dalmore",                 "Dalmore"),
        ("Highland Park",           "Highland Park"),
        ("Glenfarclas",             "Glenfarclas"),
        ("GlenDronach",             "GlenDronach"),
        ("Bruichladdich",           "Bruichladdich"),
        ("Springbank",              "Springbank"),
        ("Bowmore",                 "Bowmore"),
        ("Lagavulin",               "Lagavulin"),
        ("Talisker",                "Talisker"),
        ("Glenmorangie",            "Glenmorangie"),
        ("Aberlour",                "Aberlour"),
        ("BenRiach",                "BenRiach"),
        ("Glen Grant",              "Glen Grant"),
        ("Tobermory",               "Tobermory"),
        ("Bunnahabhain",            "Bunnahabhain"),
        ("Caol Ila",                "Caol Ila"),
        ("Kilchoman",               "Kilchoman"),
        ("Deanston",                "Deanston"),
        ("Compass Box",             "Compass Box"),
        ("Craigellachie",           "Craigellachie"),

        // Irish
        ("Redbreast",               "Irish Distillers"),
        ("Green Spot",              "Irish Distillers"),
        ("Yellow Spot",             "Irish Distillers"),
        ("Jameson",                 "Irish Distillers"),
        ("Bushmills",               "Bushmills"),
        ("Teeling",                 "Teeling"),
        ("Tullamore",               "Tullamore DEW"),
        ("Connemara",               "Cooley Distillery"),
        ("Writers' Tears",          "Walsh Whiskey"),
        ("Midleton",                "Irish Distillers"),

        // Japanese
        ("Hibiki",                  "Suntory"),
        ("Yamazaki",                "Suntory"),
        ("Hakushu",                 "Suntory"),
        ("Yoichi",                  "Nikka"),
        ("Miyagikyo",               "Nikka"),
        ("Chichibu",                "Chichibu"),
        ("Nikka",                   "Nikka"),

        // Canadian
        ("Crown Royal",             "Crown Royal"),
        ("Canadian Club",           "Canadian Club"),
        ("Forty Creek",             "Forty Creek"),
    ]

    // MARK: - Public entry point

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
        let blocks: [LabelBlock] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first, candidate.confidence > 0.3 else { return nil }
            let bb = obs.boundingBox
            return LabelBlock(text: candidate.string.trimmingCharacters(in: .whitespaces),
                              area: bb.width * bb.height,
                              confidence: candidate.confidence)
        }
        guard !blocks.isEmpty else { return ScannedBottleData() }

        let fullText = blocks.map { $0.text }.joined(separator: " ")

        var data = ScannedBottleData()
        data.proof = extractProof(from: fullText)
        data.age   = extractAge(from: fullText)
        data.type  = extractType(from: fullText)

        // Try brand lookup first — gives us both name AND distillery reliably
        if let (brand, distillery) = matchBrand(in: blocks, fullText: fullText) {
            data.name       = brand
            data.distillery = distillery
        } else {
            // Unknown brand: pick largest text for name, leave distillery blank
            data.name = extractNameFromBlocks(blocks, knownType: data.type)
        }

        return data
    }

    // MARK: - Brand matching
    // Checks each text block against the brand list (largest blocks first).
    // Returns (brandName, distilleryName) on first match.

    private static func matchBrand(in blocks: [LabelBlock], fullText: String) -> (String, String)? {
        let sortedBlocks = blocks.sorted { $0.area > $1.area }

        // 1. Try matching individual blocks (most reliable)
        for block in sortedBlocks {
            if let match = brandEntry(for: block.text) { return match }
        }

        // 2. Fall back to full-text substring scan (catches split text like "Buffalo\nTrace")
        for entry in brandToDistillery {
            if fullText.localizedCaseInsensitiveContains(entry.brand) {
                return (entry.brand, entry.distillery)
            }
        }
        return nil
    }

    private static func brandEntry(for text: String) -> (String, String)? {
        let lower = text.lowercased()
        for entry in brandToDistillery {
            if lower == entry.brand.lowercased() ||
               lower.contains(entry.brand.lowercased()) {
                return (entry.brand, entry.distillery)
            }
        }
        return nil
    }

    // MARK: - Name fallback (unknown brands)

    private static let nameSkipWords = [
        "distillery", "distilled", "bottled by", "bottled in", "product of",
        "government warning", "according to", "contains", "sulfites",
        "750ml", "700ml", "750 ml", "1 liter", "1l", "1.75",
        "www.", ".com", ".net", "established", "copyright", "©",
        "alc/vol", "alc.", "proof", "% alc", "% abv",
        "aged in", "aged at", "matured", "hand crafted", "hand selected",
        "batch", "barrel no", "barrel #", "bottle no", "bottle #",
        "rick house", "rickhouse", "non-chill", "non chill",
        "natural color",
    ]

    private static let genericWords: Set<String> = [
        "whiskey", "whisky", "bourbon", "scotch", "distillery",
        "distilleries", "spirits", "aged", "single", "malt",
    ]

    private static func extractNameFromBlocks(_ blocks: [LabelBlock], knownType: String?) -> String? {
        let sorted = blocks.sorted { $0.area > $1.area }
        let candidate = sorted.first { block in
            let lower = block.text.lowercased()
            guard block.text.count >= 3, block.text.count <= 60 else { return false }
            guard !nameSkipWords.contains(where: { lower.contains($0) }) else { return false }
            guard block.text.range(of: #"^\d+[\s%]?"#, options: .regularExpression) == nil else { return false }
            if let t = knownType, lower == t.lowercased() { return false }
            if genericWords.contains(lower) { return false }
            return true
        }
        return candidate.map { $0.text }
    }

    // MARK: - Proof

    private static func extractProof(from text: String) -> String? {
        let patterns = [
            #"(\d{2,3}(?:\.\d{1,2})?)\s*proof"#,
            #"(\d{2,3}(?:\.\d{1,2})?)\s*%\s*(?:alc|abv)"#,
            #"(\d{2,3}(?:\.\d{1,2})?)%"#,
        ]
        for (i, pattern) in patterns.enumerated() {
            guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            let matchStr = String(text[match])
            guard let numRange = matchStr.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { continue }
            let raw = String(matchStr[numRange])
            guard let num = Double(raw) else { continue }
            if i == 2 && num < 30 { continue }  // bare % — ignore implausible values
            if i >= 1 {  // ABV → proof
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
        let patterns = [
            #"aged\s+(\d{1,2})\s*year"#,
            #"(\d{1,2})\s*[-–]?\s*(?:year|yr|y\.o\.?)\w*"#,
        ]
        for pattern in patterns {
            guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            let matchStr = String(text[match])
            guard let numRange = matchStr.range(of: #"\d+"#, options: .regularExpression) else { continue }
            let num = Int(String(matchStr[numRange])) ?? 0
            guard num >= 2 && num <= 50 else { continue }
            return "\(num) Year"
        }
        return nil
    }

    // MARK: - Type

    private static func extractType(from text: String) -> String? {
        let types: [(keywords: [String], label: String)] = [
            (["kentucky straight bourbon"],         "Kentucky Straight Bourbon"),
            (["straight bourbon whiskey",
              "straight bourbon"],                  "Straight Bourbon"),
            (["tennessee whiskey"],                 "Tennessee Whiskey"),
            (["straight rye whiskey",
              "straight rye"],                      "Straight Rye"),
            (["rye whiskey"],                       "Rye"),
            (["american single malt"],              "American Single Malt"),
            (["single malt scotch whisky",
              "single malt scotch",
              "single malt"],                       "Single Malt Scotch"),
            (["scotch whisky", "scotch"],           "Scotch"),
            (["irish whiskey"],                     "Irish Whiskey"),
            (["japanese whisky"],                   "Japanese Whisky"),
            (["canadian whisky"],                   "Canadian Whisky"),
            (["wheat whiskey", "wheat whisky"],     "Wheat Whiskey"),
            (["bourbon whiskey", "bourbon"],        "Bourbon"),
            (["blended whiskey", "blended whisky",
              "blended malt"],                      "Blended"),
        ]
        let lower = text.lowercased()
        for entry in types {
            if entry.keywords.contains(where: { lower.contains($0) }) {
                return entry.label
            }
        }
        return nil
    }
}
