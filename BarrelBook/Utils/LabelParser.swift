// LabelParser.swift
// BarrelBook
//
// Parses whiskey label text (from Vision OCR) into structured bottle data.
// Self-contained — no UI dependencies. Safe to remove alongside BottleScannerView.swift.
//
// Strategy (iOS 26+ with Apple Intelligence):
//   Uses FoundationModels (on-device LLM) for intelligent name/type/proof/age extraction.
//   Falls back to regex + NLTagger on older devices or when Apple Intelligence is off.
//
// Fallback strategy:
//   1. Proof, age, type  — reliable regex/keyword matches against full text
//   2. Name              — find known brand block, then find the best expression
//                          block (Single Barrel, Double Oaked, etc.) and combine.
//                          Falls back to largest non-noise block for unknown brands.
//   Distillery is intentionally NOT parsed — it's rarely printed on the label
//   and was causing more confusion than value.

import Vision
import UIKit
import NaturalLanguage
import FoundationModels

// MARK: - Result type

struct ScannedBottleData {
    var nameOptions: [String] = []  // ordered best-first; first is pre-selected
    var type: String?
    var proof: String?
    var age: String?
    var finish: String?             // cask finish, e.g. "Port Wine Cask Finish"
    var isBiB: Bool = false         // Bottled in Bond
    var isSiB: Bool = false         // Single Barrel
    var isCaskStrength: Bool = false

    var primaryName: String? { nameOptions.first }

    var isEmpty: Bool {
        nameOptions.isEmpty && type == nil && proof == nil && age == nil && finish == nil
            && !isBiB && !isSiB && !isCaskStrength
    }
}

// MARK: - Internal block type

private struct LabelBlock {
    let text: String
    let area: CGFloat   // normalized bounding-box area — larger = more prominent
    let confidence: Float
}

// MARK: - Parser

enum LabelParser {

    // MARK: - Known brands
    // These are label-facing brand names only — no distillery inference.
    // Ordered longest-first so "Colonel E.H. Taylor" matches before "E.H. Taylor".

    private static let knownBrands: [String] = [
        // Buffalo Trace
        "Colonel E.H. Taylor", "Pappy Van Winkle", "W.L. Weller",
        "E.H. Taylor", "Eagle Rare", "Blanton's", "Buffalo Trace",
        "Benchmark", "Ancient Age", "Van Winkle", "Weller",
        // Heaven Hill
        "Parker's Heritage", "Elijah Craig", "Evan Williams",
        "Old Fitzgerald", "Henry McKenna", "Fighting Cock",
        "Bernheim", "Larceny",
        // Jim Beam / Beam Suntory
        "Old Grand-Dad", "Old Granddad", "Little Book",
        "Basil Hayden", "Knob Creek", "Booker's", "Baker's",
        "Old Crow", "Jim Beam",
        // Wild Turkey
        "Russell's Reserve", "Wild Turkey",
        // Four Roses
        "Four Roses",
        // Maker's Mark
        "Maker's Mark",
        // Woodford Reserve
        "Woodford Reserve",
        // Old Forester / Brown-Forman
        "Old Forester",
        // Jack Daniel's
        "Gentleman Jack", "Jack Daniel's", "Jack Daniel",
        // George Dickel
        "George Dickel",
        // Craft / independent American
        "Bardstown Bourbon", "Castle & Key", "Wilderness Trail",
        "Garrison Brothers", "Stranahan's", "Breckenridge",
        "Laws Whiskey", "Smooth Ambler", "Rabbit Hole",
        "New Riff", "WhistlePig", "Whistlepig", "Westland",
        "Balcones", "FEW Spirits", "Koval", "Peerless",
        "High West", "Michter's", "Angel's Envy",
        "Jefferson's", "Redemption", "Bulleit",
        "1792", "Very Old Barton", "Sazerac",
        // Scotch
        "Compass Box", "Craigellachie", "Highland Park",
        "Glen Grant", "Caol Ila", "Bunnahabhain", "Kilchoman",
        "GlenDronach", "Glenfarclas", "Bruichladdich", "Springbank",
        "Glenmorangie", "Aberlour", "Tobermory", "Deanston",
        "BenRiach", "Talisker", "Lagavulin", "Bowmore",
        "Glenfiddich", "Balvenie", "Glenlivet", "Macallan",
        "Laphroaig", "Ardbeg", "Oban", "Dalmore",
        // Irish
        "Writers' Tears", "Green Spot", "Yellow Spot",
        "Redbreast", "Connemara", "Tullamore", "Teeling",
        "Bushmills", "Jameson", "Midleton",
        // Japanese
        "Chichibu", "Miyagikyo", "Yamazaki", "Hakushu",
        "Hibiki", "Yoichi", "Nikka", "Suntory",
        // Canadian
        "Forty Creek", "Crown Royal", "Canadian Club",
    ]

    // MARK: - Known expressions
    // These words/phrases commonly appear as sub-labels on bottles.
    // When found alongside a known brand, they're appended to the name.

    private static let knownExpressions: [String] = [
        // Finish / process
        "Distiller's Select", "Distillers Select",
        "Double Oaked", "Double Oak", "Double Malt", "Double Rye",
        "Toasted Oak", "Honey Barrel",
        // Barrel type
        "Single Barrel", "Single Barrel Select",
        "Small Batch", "Small Batch Select",
        "Cask Strength", "Barrel Proof", "Barrel Strength",
        "Bottled in Bond", "Bonded",
        "Batch Proof",
        // Edition / series
        "Master's Keep", "Masters Collection", "Master's Collection",
        "Very Fine Rare Bourbon",
        "Kentucky Spirit", "Rare Breed",
        "Special Reserve", "Select Reserve",
        "Limited Edition", "Limited Release",
        "Anniversary Edition", "Collector's Edition",
        // Rye expressions
        "Straight Rye", "Rye Mash",
        // Other
        "Black Label", "White Label", "Gold Label", "Blue Label",
        "Original", "Signature", "Reserve", "Heritage",
        "10 Year", "12 Year", "15 Year", "18 Year", "21 Year", "25 Year",
    ]

    // MARK: - Public entry points

    /// Primary path: accepts live text items from DataScannerViewController.
    /// Each item carries its bounding-box area so name ranking stays accurate.
    /// On iOS 26+ with Apple Intelligence, uses FoundationModels for smarter extraction.
    static func parse(from textItems: [(text: String, area: CGFloat)],
                      completion: @escaping (ScannedBottleData) -> Void) {
        let blocks = textItems.map {
            LabelBlock(text: $0.text.trimmingCharacters(in: .whitespaces),
                       area: $0.area,
                       confidence: 1.0)
        }

        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            Task {
                do {
                    let result = try await parseWithFoundationModels(blocks: blocks)
                    await MainActor.run { completion(result) }
                } catch {
                    // Apple Intelligence failed — fall back gracefully to regex/NLTagger
                    let result = parseBlocks(blocks)
                    await MainActor.run { completion(result) }
                }
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = parseBlocks(blocks)
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    /// Primary photo path: accepts a UIImage, runs Vision OCR, then Apple Intelligence (iOS 26+) or regex fallback.
    static func parse(from image: UIImage, completion: @escaping (ScannedBottleData) -> Void) {
        guard let cgImage = image.cgImage else {
            DispatchQueue.main.async { completion(ScannedBottleData()) }
            return
        }
        let request = VNRecognizeTextRequest { request, _ in
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let blocks: [LabelBlock] = observations.compactMap { obs in
                guard let top = obs.topCandidates(1).first, top.confidence > 0.3 else { return nil }
                let bb = obs.boundingBox
                return LabelBlock(text: top.string.trimmingCharacters(in: .whitespaces),
                                  area: bb.width * bb.height,
                                  confidence: top.confidence)
            }

            if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
                Task {
                    do {
                        let result = try await parseWithFoundationModels(blocks: blocks)
                        await MainActor.run { completion(result) }
                    } catch {
                        let result = parseBlocks(blocks)
                        await MainActor.run { completion(result) }
                    }
                }
            } else {
                let result = parseBlocks(blocks)
                DispatchQueue.main.async { completion(result) }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Core (shared by both entry points)

    private static func parseBlocks(_ blocks: [LabelBlock]) -> ScannedBottleData {
        guard !blocks.isEmpty else { return ScannedBottleData() }
        let fullText = blocks.map { $0.text }.joined(separator: " ")
        var data = ScannedBottleData()
        data.proof  = extractProof(from: fullText)
        data.age    = extractAge(from: fullText)
        data.type   = extractType(from: fullText)
        data.finish = extractFinish(from: fullText)
        data.nameOptions = extractNameOptions(from: blocks, fullText: fullText, knownType: data.type)
        let attrs = extractSpecialAttributes(from: fullText)
        data.isBiB = attrs.isBiB
        data.isSiB = attrs.isSiB
        data.isCaskStrength = attrs.isCaskStrength
        return data
    }

    // MARK: - FoundationModels path (iOS 26+, Apple Intelligence)

    @available(iOS 26.0, *)
    private static func parseWithFoundationModels(blocks: [LabelBlock]) async throws -> ScannedBottleData {
        // Strip noise before sending to the model — cleaner input = better output
        let rawText = blocks
            .filter { !isNoise($0.text) && $0.text.count >= 2 }
            .sorted { $0.area > $1.area }   // largest blocks first (most prominent)
            .map { $0.text }
            .joined(separator: "\n")

        // Run regex parsing alongside — used as fallback and to generate extra name chips
        let regexResult = parseBlocks(blocks)

        let session = LanguageModelSession {
            "You are a whiskey expert. Identify whiskey bottles from OCR label text."
        }

        let prompt = """
        OCR text from a whiskey bottle label (largest text block first, noise removed):

        \(rawText)

        Identify the whiskey and extract what is printed on the label.
        """

        let response = try await session.respond(to: prompt, generating: WhiskeyLabelExtraction.self)
        let extraction = response.content

        var data = ScannedBottleData()

        // Build name chips: AI identification first, then regex alternatives
        var nameOptions: [String] = []

        func appendIfNew(_ candidate: String) {
            let t = candidate.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return }
            let duplicate = nameOptions.contains {
                $0.localizedCaseInsensitiveCompare(t) == .orderedSame ||
                $0.localizedCaseInsensitiveContains(t) ||
                t.localizedCaseInsensitiveContains($0)
            }
            if !duplicate { nameOptions.append(t) }
        }

        appendIfNew(extraction.name)
        regexResult.nameOptions.forEach { appendIfNew($0) }

        data.nameOptions = nameOptions

        // AI is trusted for name and type — it genuinely knows these products.
        // Proof: AI knows canonical values (e.g. 90.4 for Woodford) so use it with regex fallback.
        // Age and finish: regex ONLY — these must be physically printed on the label.
        //   AI will hallucinate ages for NAS bottles and finishes it "knows about" but can't see.
        let aiType  = extraction.type.trimmingCharacters(in: .whitespaces)
        let aiProof = extraction.proof.trimmingCharacters(in: .whitespaces)
        data.type   = aiType.isEmpty  ? regexResult.type  : aiType
        data.proof  = aiProof.isEmpty ? regexResult.proof : aiProof
        data.age    = regexResult.age     // never infer — must be on the label
        data.finish = regexResult.finish  // never infer — must be on the label
        // Special attributes: regex only — must be printed on the label
        data.isBiB = regexResult.isBiB
        data.isSiB = regexResult.isSiB
        data.isCaskStrength = regexResult.isCaskStrength

        return data
    }

    // MARK: - Name options (ordered best-first)

    private static func extractNameOptions(from blocks: [LabelBlock], fullText: String, knownType: String?) -> [String] {
        var options: [String] = []

        // Check full text for a known brand
        let matchedBrand = knownBrands.first {
            fullText.localizedCaseInsensitiveContains($0)
        }

        if let brand = matchedBrand {
            let expression = findExpression(in: blocks, excluding: brand, fullText: fullText)
            if let expr = expression, !brand.localizedCaseInsensitiveContains(expr) {
                options.append("\(brand) \(expr)")   // combined — best guess
                options.append(brand)                // brand alone as fallback option
                // Expression alone only if it's meaningful by itself
                if expr.split(separator: " ").count >= 2 {
                    options.append(expr)
                }
            } else {
                options.append(brand)
            }
        }

        // Add the best NL-scored block if it's different from what we have so far
        if let raw = bestScoredBlock(from: blocks, knownType: knownType) {
            let alreadyCovered = options.contains {
                $0.localizedCaseInsensitiveCompare(raw) == .orderedSame ||
                $0.localizedCaseInsensitiveContains(raw)
            }
            if !alreadyCovered {
                options.append(raw)
            }
        }

        return options.filter { !$0.isEmpty }
    }

    private static func findExpression(in blocks: [LabelBlock], excluding brand: String, fullText: String) -> String? {
        // Check known expression list against full text first (most reliable)
        for expr in knownExpressions {
            if fullText.localizedCaseInsensitiveContains(expr) {
                // Make sure it's not already part of the brand name
                if !brand.localizedCaseInsensitiveContains(expr) {
                    return expr
                }
            }
        }

        // No known expression found — look for a block that might be an unknown expression:
        // title-case or all-caps, 2–5 words, not noise, not the brand itself
        let sorted = blocks.sorted { $0.area > $1.area }
        for block in sorted {
            let t = block.text
            guard t.count >= 4, t.count <= 40 else { continue }
            guard !brand.localizedCaseInsensitiveContains(t),
                  !t.localizedCaseInsensitiveContains(brand) else { continue }
            guard !isNoise(t) else { continue }
            let wordCount = t.split(separator: " ").count
            guard wordCount >= 2, wordCount <= 5 else { continue }
            // Must look like a proper title (starts with capital, no digits leading)
            guard t.first?.isUppercase == true else { continue }
            guard t.range(of: #"^\d"#, options: .regularExpression) == nil else { continue }
            return t
        }
        return nil
    }

    // MARK: - Intelligent block scoring (NLTagger + heuristics)

    /// Scores each block on multiple signals and returns the highest-scoring candidate.
    /// Used when no known brand is found — catches unknown/craft brands intelligently.
    private static func bestScoredBlock(from blocks: [LabelBlock], knownType: String?) -> String? {
        let genericWords: Set<String> = ["whiskey", "whisky", "bourbon", "scotch",
                                         "distillery", "distilleries", "spirits", "aged",
                                         "reserve", "select", "original", "heritage", "signature"]

        // Normalize areas to 0–1 range for fair weighting
        let maxArea = blocks.map { $0.area }.max() ?? 1

        let scored: [(text: String, score: Double)] = blocks.compactMap { block in
            let text = block.text
            let lower = text.lowercased()

            // Hard disqualifiers
            guard text.count >= 3, text.count <= 60 else { return nil }
            guard !isNoise(text) else { return nil }
            guard text.range(of: #"^\d+[\s%]?"#, options: .regularExpression) == nil else { return nil }
            if let t = knownType, lower == t.lowercased() { return nil }
            if genericWords.contains(lower) { return nil }

            var score = 0.0

            // 1. Visual prominence — largest text on the label is likely the name
            let normalizedArea = Double(block.area / maxArea)
            score += normalizedArea * 4.0

            // 2. NLTagger: organization names score highest (brand = org),
            //    place names and personal names score moderately (some distilleries)
            score += nlNameScore(for: text) * 3.0

            // 3. Word count — 1–4 words ideal for a whiskey name
            let wordCount = text.split(separator: " ").count
            if wordCount >= 1 && wordCount <= 4 { score += 1.0 }
            if wordCount > 6 { score -= 2.0 }

            // 4. Title case or all-caps — common for whiskey brands
            if text == text.uppercased() && wordCount <= 4 { score += 0.8 }
            else if text.first?.isUppercase == true { score += 0.3 }

            // 5. Penalize if it looks like an address or sentence
            if text.contains(",") || text.hasSuffix(".") { score -= 1.5 }

            return (text, score)
        }

        return scored
            .sorted { $0.score > $1.score }
            .first?
            .text
    }

    /// Uses NLTagger to detect how "name-like" a string is.
    /// Returns a score: higher = more likely to be a proper name / brand.
    private static func nlNameScore(for text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var score = 0.0
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, _ in
            switch tag {
            case .organizationName: score += 1.0   // brands, distilleries
            case .placeName:        score += 0.4   // some distillery names are places
            case .personalName:     score += 0.2   // e.g. "George Dickel"
            default: break
            }
            return true
        }
        return score
    }

    // MARK: - Noise detection (shared)

    private static let noiseTerms = [
        "distillery", "distilled", "bottled by", "bottled in", "product of",
        "government warning", "according to", "contains", "sulfites",
        "750ml", "700ml", "750 ml", "1 liter", "1.75l",
        "www.", ".com", ".net", "established", "copyright", "©",
        "alc/vol", "alc.", "% alc", "% abv",
        "aged in", "aged at", "hand crafted", "hand selected",
        "barrel no", "barrel #", "bottle no", "bottle #",
        "rick house", "rickhouse", "non-chill", "natural color",
    ]

    private static func isNoise(_ text: String) -> Bool {
        let lower = text.lowercased()
        return noiseTerms.contains { lower.contains($0) }
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
            if i == 2 && num < 30 { continue }
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
        let patterns = [
            #"aged\s+(\d{1,2})\s*year"#,
            #"(\d{1,2})\s*[-–]?\s*(?:year|yr|y\.o\.?)\w*"#,
        ]
        for pattern in patterns {
            guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            let matchStr = String(text[match])
            guard let numRange = matchStr.range(of: #"\d+"#, options: .regularExpression) else { continue }
            let num = Int(String(matchStr[numRange])) ?? 0
            guard num >= 2, num <= 50 else { continue }
            return "\(num) Year"
        }
        return nil
    }

    // MARK: - Special attributes (BiB / SiB / Cask Strength)

    /// Detects Bottled-in-Bond, Single Barrel, and Cask Strength phrases from OCR text.
    /// Case-insensitive; requires label wording (does not infer from brand knowledge).
    private static func extractSpecialAttributes(from text: String) -> (isBiB: Bool, isSiB: Bool, isCaskStrength: Bool) {
        let isBiB = text.range(
            of: #"\b(?:bottled\s+in\s+bond|bonded)\b|\bBiB\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let isSiB = text.range(
            of: #"\b(?:single\s+barrel|single\s+cask)\b|\bSiB\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let isCaskStrength = text.range(
            of: #"\b(?:cask\s+strength|barrel\s+proof|barrel\s+strength)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        return (isBiB, isSiB, isCaskStrength)
    }

    // MARK: - FoundationModels structured output schema

    // Defined inside LabelParser so it's clearly scoped to parsing.
    // @Generable tells FoundationModels how to produce structured JSON output.
    @available(iOS 26.0, *)
    @Generable
    struct WhiskeyLabelExtraction {
        @Guide(description: "The whiskey brand and expression, e.g. 'Woodford Reserve Distiller\u{2019}s Select' or 'Eagle Rare 10 Year'. Brand and expression only — no category words like 'Bourbon Whiskey' or 'Distillery'.")
        var name: String

        @Guide(description: "Whiskey category, e.g. 'Kentucky Straight Bourbon', 'Single Malt Scotch', 'Straight Rye', 'Tennessee Whiskey', 'Irish Whiskey'. Use your knowledge of the product.")
        var type: String

        @Guide(description: "Proof as printed on the label, e.g. '90' or '114.4'. If label shows ABV%, multiply by 2. Empty string if not on the label.")
        var proof: String

        @Guide(description: "Age statement ONLY if the exact text appears on this label, e.g. '10 Year'. Do NOT infer from product knowledge — if you cannot see age text in the OCR, return empty string.")
        var age: String

        @Guide(description: "Cask finish ONLY if explicitly stated on this label, e.g. 'Port Wine Cask Finish', 'Sherry Cask', 'Double Oaked'. Do NOT infer from product knowledge — return empty string if not in the OCR text.")
        var finish: String
    }

    // MARK: - Cask finish

    private static func extractFinish(from text: String) -> String? {
        let finishes: [(keywords: [String], label: String)] = [
            // ── Common cask finishes ────────────────────────────────────────
            (["port wine cask", "port wood", "port cask", "port finish", "port pipe"],       "Port Wine Cask Finish"),
            (["sherry cask", "sherry finish", "sherry wood", "sherry butt",
              "oloroso", "pedro ximenez"],                                                   "Sherry Cask Finish"),
            (["double oaked"],                                                               "Double Oaked"),
            (["toasted oak", "toasted barrel"],                                              "Toasted Oak Finish"),
            (["rum cask", "rum finish", "rum barrel"],                                       "Rum Cask Finish"),
            (["madeira cask", "madeira finish", "madeira wood"],                             "Madeira Cask Finish"),
            (["sauternes cask", "sauternes finish"],                                         "Sauternes Cask Finish"),
            (["cognac cask", "cognac finish"],                                               "Cognac Cask Finish"),
            (["armagnac cask", "armagnac finish", "armagnac barrel"],                        "Armagnac Cask Finish"),
            (["calvados", "apple brandy finish"],                                            "Calvados Finish"),
            (["tequila cask", "tequila barrel", "tequila finish"],                          "Tequila Cask Finish"),
            (["mezcal cask", "mezcal barrel", "mezcal finish"],                             "Mezcal Cask Finish"),
            (["beer barrel", "stout finish", "stout cask"],                                 "Beer Barrel Finish"),
            // ── Wine variety casks (specific before generic) ───────────────
            (["rosé cask", "rose cask", "rosé wine", "rose wine cask",
              "rosé barrel", "rose barrel"],                                                 "Rosé Wine Cask Finish"),
            (["amarone cask", "amarone finish", "amarone barrel"],                           "Amarone Cask Finish"),
            (["barolo cask", "barolo finish", "barolo barrel"],                              "Barolo Cask Finish"),
            (["pinot noir cask", "pinot noir finish", "pinot noir barrel"],                 "Pinot Noir Cask Finish"),
            (["chardonnay cask", "chardonnay finish", "chardonnay barrel"],                 "Chardonnay Cask Finish"),
            (["zinfandel cask", "zinfandel finish", "zinfandel barrel"],                    "Zinfandel Cask Finish"),
            (["grenache cask", "grenache finish", "grenache barrel"],                       "Grenache Cask Finish"),
            (["bordeaux cask", "bordeaux finish", "bordeaux barrel"],                       "Bordeaux Cask Finish"),
            (["moscatel cask", "moscatel finish", "moscatel barrel"],                       "Moscatel Cask Finish"),
            (["marsala cask", "marsala finish", "marsala barrel"],                          "Marsala Cask Finish"),
            (["manzanilla cask", "manzanilla finish"],                                      "Manzanilla Cask Finish"),
            (["tokaji cask", "tokaji finish", "tokay cask"],                                "Tokaji Cask Finish"),
            (["muscat cask", "muscat finish", "muscat barrel"],                             "Muscat Cask Finish"),
            // ── Oak / wood types ────────────────────────────────────────────
            (["mizunara"],                                                                   "Mizunara Oak Finish"),
            (["virgin oak", "new american oak"],                                             "Virgin Oak"),
            (["french oak"],                                                                 "French Oak"),
            (["cherry wood cask", "cherry cask", "cherry barrel"],                          "Cherry Wood Cask Finish"),
            (["acacia cask", "acacia wood", "acacia barrel"],                               "Acacia Cask Finish"),
            (["maple cask", "maple barrel", "maple wood"],                                  "Maple Cask Finish"),
            (["str cask", "str finish", "shaved, toasted",
              "shaved toasted re-charred"],                                                  "STR Cask Finish"),
            // ── Ex-spirit casks ─────────────────────────────────────────────
            (["ex-bourbon cask", "ex bourbon cask", "ex-bourbon barrel",
              "ex bourbon barrel", "former bourbon"],                                        "Ex-Bourbon Cask"),
            (["honey cask", "honey barrel finish"],                                         "Honey Cask Finish"),
            // ── Generic wine (last — catch-all after specific varieties) ────
            (["wine cask", "wine finish", "wine barrel"],                                   "Wine Cask Finish"),
        ]
        let lower = text.lowercased()
        for entry in finishes {
            if entry.keywords.contains(where: { lower.contains($0) }) {
                return entry.label
            }
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
