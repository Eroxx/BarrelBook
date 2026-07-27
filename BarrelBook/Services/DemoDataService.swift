import CoreData
import SwiftUI

/// Shared demo data loader — called from both SettingsView and ContentView.
struct DemoDataService {

    /// Clears all existing data then seeds a sample bourbon collection.
    /// Calls `completion(.success)` or `completion(.failure(error))` on the main thread.
    static func load(context ctx: NSManagedObjectContext,
                     completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let whiskeys = try ctx.fetch(Whiskey.fetchRequest())
            whiskeys.forEach { ctx.delete($0) }
            let journalEntries = try ctx.fetch(JournalEntry.fetchRequest())
            journalEntries.forEach { ctx.delete($0) }
            let infinityBottles = try ctx.fetch(InfinityBottle.fetchRequest())
            infinityBottles.forEach { ctx.delete($0) }
            let stores = try ctx.fetch(Store.fetchRequest())
            stores.forEach { ctx.delete($0) }
            try ctx.save()
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        do {
            let cal = Calendar.current
            let now = Date()

            // MARK: - Stores
            let store1 = Store(context: ctx)
            store1.id = UUID()
            store1.name = "Local Liquor & Wine"
            store1.address = "123 Main St"
            store1.isFavorite = true
            store1.modificationDate = now

            let store2 = Store(context: ctx)
            store2.id = UUID()
            store2.name = "Total Wine & More"
            store2.address = "456 Oak Ave"
            store2.isFavorite = true
            store2.modificationDate = now

            let store3 = Store(context: ctx)
            store3.id = UUID()
            store3.name = "The Whiskey Shop"
            store3.address = "789 Barrel Rd"
            store3.isFavorite = true
            store3.modificationDate = now

            let store4 = Store(context: ctx)
            store4.id = UUID()
            store4.name = "Spec's Wines, Spirits & Finer Foods"
            store4.address = "2410 Smith St"
            store4.isFavorite = false
            store4.modificationDate = now

            // MARK: - Owned Collection
            struct BottleState {
                let open: Bool
                let dead: Bool
                let daysAgoAdded: Int
                let daysAgoOpened: Int?
                let daysAgoFinished: Int?
                init(_ open: Bool, _ dead: Bool, daysAgoAdded: Int = Int.random(in: 10...365),
                     daysAgoOpened: Int? = nil, daysAgoFinished: Int? = nil) {
                    self.open = open; self.dead = dead
                    self.daysAgoAdded = daysAgoAdded
                    self.daysAgoOpened = daysAgoOpened
                    self.daysAgoFinished = daysAgoFinished
                }
            }

            struct OwnedSeed {
                let name, type, distillery: String
                let proof, price: Double
                /// Estimated secondary-market value; nil/0 falls back to paid in secondary totals.
                let secondaryMarketValue: Double?
                let bottles: [BottleState]
                let isBiB, isSiB, isStorePick, isCaskStrength: Bool
                let storePickName: String?
                let age: String?
                init(_ name: String, _ type: String, _ distillery: String,
                     _ proof: Double, _ price: Double,
                     _ bottles: [BottleState],
                     secondaryMarketValue: Double? = nil,
                     isBiB: Bool = false, isSiB: Bool = false,
                     isStorePick: Bool = false, storePickName: String? = nil,
                     isCaskStrength: Bool = false, age: String? = nil) {
                    self.name = name; self.type = type; self.distillery = distillery
                    self.proof = proof; self.price = price
                    self.secondaryMarketValue = secondaryMarketValue
                    self.bottles = bottles
                    self.isBiB = isBiB; self.isSiB = isSiB; self.isStorePick = isStorePick
                    self.storePickName = storePickName; self.isCaskStrength = isCaskStrength
                    self.age = age
                }
            }

            // Secondary values: mix of above / below / equal MSRP; a few left unset (nil)
            // so Secondary ≈ Paid until those bottles get an override (toggle still useful).
            let ownedSeeds: [OwnedSeed] = [
                // EVERYDAY BOURBONS
                OwnedSeed("Buffalo Trace", "Bourbon", "Buffalo Trace", 90, 24.99,
                          [BottleState(true, false, daysAgoAdded: 45, daysAgoOpened: 20),
                           BottleState(false, false, daysAgoAdded: 45)],
                          secondaryMarketValue: 29.99),

                OwnedSeed("Wild Turkey 101", "Bourbon", "Wild Turkey", 101, 22.99,
                          [BottleState(true, false, daysAgoAdded: 60, daysAgoOpened: 30)],
                          secondaryMarketValue: 27.99, isBiB: true),

                OwnedSeed("Maker's Mark", "Bourbon", "Maker's Mark", 90, 26.99,
                          [BottleState(true, false, daysAgoAdded: 30, daysAgoOpened: 10),
                           BottleState(false, false, daysAgoAdded: 30)],
                          secondaryMarketValue: 24.99),

                // unset — falls back to paid
                OwnedSeed("Evan Williams Black Label", "Bourbon", "Heaven Hill", 86, 12.99,
                          [BottleState(true, false, daysAgoAdded: 90, daysAgoOpened: 60)],
                          isBiB: false),

                OwnedSeed("Old Grand-Dad Bonded", "Bourbon", "Jim Beam", 100, 19.99,
                          [BottleState(false, false, daysAgoAdded: 14)],
                          secondaryMarketValue: 21.99, isBiB: true),

                OwnedSeed("Elijah Craig Small Batch", "Bourbon", "Heaven Hill", 94, 29.99,
                          [BottleState(true, false, daysAgoAdded: 55, daysAgoOpened: 25),
                           BottleState(false, false, daysAgoAdded: 55)],
                          secondaryMarketValue: 34.99),

                // MID-SHELF BOURBONS
                OwnedSeed("Eagle Rare 10 Year", "Bourbon", "Buffalo Trace", 90, 34.99,
                          [BottleState(true, false, daysAgoAdded: 70, daysAgoOpened: 40),
                           BottleState(false, false, daysAgoAdded: 70)],
                          secondaryMarketValue: 79.99, age: "10"),

                OwnedSeed("Woodford Reserve", "Bourbon", "Woodford Reserve", 90.4, 34.99,
                          [BottleState(true, false, daysAgoAdded: 35, daysAgoOpened: 15)],
                          secondaryMarketValue: 32.99),

                OwnedSeed("Knob Creek 9 Year", "Bourbon", "Jim Beam", 100, 38.99,
                          [BottleState(true, false, daysAgoAdded: 80, daysAgoOpened: 50),
                           BottleState(false, false, daysAgoAdded: 80)],
                          secondaryMarketValue: 44.99,
                          isStorePick: true, storePickName: "Local Liquor & Wine", age: "9"),

                OwnedSeed("Russell's Reserve 10 Year", "Bourbon", "Wild Turkey", 90, 39.99,
                          [BottleState(true, false, daysAgoAdded: 50, daysAgoOpened: 20)],
                          secondaryMarketValue: 42.99, age: "10"),

                OwnedSeed("Four Roses Single Barrel", "Bourbon", "Four Roses", 100, 44.99,
                          [BottleState(true, false, daysAgoAdded: 100, daysAgoOpened: 60),
                           BottleState(true, true, daysAgoAdded: 180, daysAgoOpened: 120,
                                       daysAgoFinished: 10)],
                          secondaryMarketValue: 49.99, isSiB: true),

                // unset — falls back to paid
                OwnedSeed("1792 Full Proof", "Bourbon", "Barton 1792", 125, 34.99,
                          [BottleState(false, false, daysAgoAdded: 7)]),

                OwnedSeed("Benchmark Full Proof", "Bourbon", "Buffalo Trace", 125, 14.99,
                          [BottleState(true, false, daysAgoAdded: 40, daysAgoOpened: 15),
                           BottleState(false, false, daysAgoAdded: 40)],
                          secondaryMarketValue: 16.99),

                // HIGH-SHELF / ALLOCATED BOURBONS
                OwnedSeed("Booker's Bourbon", "Bourbon", "Jim Beam", 127.4, 89.99,
                          [BottleState(true, false, daysAgoAdded: 120, daysAgoOpened: 30)],
                          secondaryMarketValue: 99.99, isCaskStrength: true),

                OwnedSeed("Larceny Barrel Proof A124", "Bourbon", "Heaven Hill", 122, 54.99,
                          [BottleState(false, false, daysAgoAdded: 21)],
                          secondaryMarketValue: 59.99, isCaskStrength: true),

                OwnedSeed("Elijah Craig Barrel Proof B523", "Bourbon", "Heaven Hill", 119.6, 59.99,
                          [BottleState(true, false, daysAgoAdded: 150, daysAgoOpened: 80)],
                          secondaryMarketValue: 79.99, isCaskStrength: true),

                OwnedSeed("Old Forester 1920", "Bourbon", "Brown-Forman", 115, 54.99,
                          [BottleState(true, false, daysAgoAdded: 60, daysAgoOpened: 20)],
                          secondaryMarketValue: 69.99, isBiB: false),

                OwnedSeed("Henry McKenna 10 Year BiB", "Bourbon", "Heaven Hill", 100, 39.99,
                          [BottleState(true, true, daysAgoAdded: 300, daysAgoOpened: 200,
                                       daysAgoFinished: 30),
                           BottleState(false, false, daysAgoAdded: 20)],
                          secondaryMarketValue: 99.99, isBiB: true, age: "10"),

                OwnedSeed("Blanton's Original", "Bourbon", "Buffalo Trace", 93, 64.99,
                          [BottleState(true, false, daysAgoAdded: 200, daysAgoOpened: 90)],
                          secondaryMarketValue: 175.00, isSiB: true),

                OwnedSeed("Weller Special Reserve", "Bourbon", "Buffalo Trace", 90, 29.99,
                          [BottleState(false, false, daysAgoAdded: 5)],
                          secondaryMarketValue: 74.99),

                OwnedSeed("Angel's Envy", "Bourbon", "Angel's Envy", 86.6, 44.99,
                          [BottleState(true, false, daysAgoAdded: 75, daysAgoOpened: 30)],
                          secondaryMarketValue: 42.99),

                // unset — falls back to paid
                OwnedSeed("Legent Bourbon", "Bourbon", "Jim Beam / Suntory", 94, 34.99,
                          [BottleState(false, false, daysAgoAdded: 12)]),

                // RYES
                OwnedSeed("Sazerac Rye", "Rye", "Buffalo Trace", 90, 28.99,
                          [BottleState(true, false, daysAgoAdded: 85, daysAgoOpened: 40),
                           BottleState(false, false, daysAgoAdded: 85)],
                          secondaryMarketValue: 34.99, isBiB: true),

                OwnedSeed("Rittenhouse Rye", "Rye", "Heaven Hill", 100, 24.99,
                          [BottleState(true, false, daysAgoAdded: 65, daysAgoOpened: 35)],
                          secondaryMarketValue: 29.99, isBiB: true),

                OwnedSeed("High West Double Rye", "Rye", "High West", 92, 34.99,
                          [BottleState(true, true, daysAgoAdded: 200, daysAgoOpened: 130,
                                       daysAgoFinished: 15),
                           BottleState(false, false, daysAgoAdded: 10)],
                          secondaryMarketValue: 32.99),

                OwnedSeed("Knob Creek Rye", "Rye", "Jim Beam", 100, 34.99,
                          [BottleState(false, false, daysAgoAdded: 18)],
                          secondaryMarketValue: 37.99, isSiB: true),

                OwnedSeed("WhistlePig 10 Year", "Rye", "WhistlePig", 100, 79.99,
                          [BottleState(true, false, daysAgoAdded: 110, daysAgoOpened: 50)],
                          secondaryMarketValue: 74.99, age: "10"),

                // SCOTCH
                // unset — falls back to paid
                OwnedSeed("Glenfiddich 12 Year", "Scotch", "Glenfiddich", 80, 42.99,
                          [BottleState(true, false, daysAgoAdded: 90, daysAgoOpened: 45)],
                          age: "12"),

                OwnedSeed("Lagavulin 16 Year", "Scotch", "Lagavulin", 86, 89.99,
                          [BottleState(true, false, daysAgoAdded: 130, daysAgoOpened: 60)],
                          secondaryMarketValue: 94.99, age: "16"),

                OwnedSeed("Laphroaig 10 Year", "Scotch", "Laphroaig", 86, 49.99,
                          [BottleState(true, true, daysAgoAdded: 250, daysAgoOpened: 180,
                                       daysAgoFinished: 25),
                           BottleState(false, false, daysAgoAdded: 15)],
                          secondaryMarketValue: 47.99, isCaskStrength: false, age: "10"),

                OwnedSeed("Ardbeg 10 Year", "Scotch", "Ardbeg", 92, 54.99,
                          [BottleState(true, false, daysAgoAdded: 60, daysAgoOpened: 25)],
                          secondaryMarketValue: 64.99, age: "10"),

                OwnedSeed("Oban 14 Year", "Scotch", "Oban", 86, 74.99,
                          [BottleState(false, false, daysAgoAdded: 9)],
                          secondaryMarketValue: 79.99, age: "14"),

                OwnedSeed("The Macallan 12 Year Sherry", "Scotch", "The Macallan", 86, 69.99,
                          [BottleState(true, false, daysAgoAdded: 95, daysAgoOpened: 40)],
                          secondaryMarketValue: 84.99, age: "12"),

                // unset — falls back to paid
                OwnedSeed("GlenDronach 12 Year", "Scotch", "GlenDronach", 86, 49.99,
                          [BottleState(false, false, daysAgoAdded: 22)],
                          age: "12"),

                // IRISH
                OwnedSeed("Redbreast 12 Year", "Irish", "Midleton", 80, 59.99,
                          [BottleState(true, false, daysAgoAdded: 75, daysAgoOpened: 30)],
                          secondaryMarketValue: 64.99, age: "12"),

                OwnedSeed("Green Spot", "Irish", "Midleton", 80, 49.99,
                          [BottleState(true, true, daysAgoAdded: 220, daysAgoOpened: 140,
                                       daysAgoFinished: 20),
                           BottleState(false, false, daysAgoAdded: 8)],
                          secondaryMarketValue: 54.99),

                // unset — falls back to paid
                OwnedSeed("Jameson Black Barrel", "Irish", "Midleton", 80, 34.99,
                          [BottleState(true, false, daysAgoAdded: 40, daysAgoOpened: 15)]),

                // JAPANESE
                OwnedSeed("Nikka Coffey Grain", "Japanese", "Nikka", 90, 69.99,
                          [BottleState(false, false, daysAgoAdded: 6)],
                          secondaryMarketValue: 72.99),

                OwnedSeed("Toki Suntory", "Japanese", "Suntory", 86, 44.99,
                          [BottleState(true, false, daysAgoAdded: 85, daysAgoOpened: 40)],
                          secondaryMarketValue: 39.99),

                OwnedSeed("Hibiki Harmony", "Japanese", "Suntory", 86, 79.99,
                          [BottleState(true, false, daysAgoAdded: 160, daysAgoOpened: 70)],
                          secondaryMarketValue: 99.99),

                // AMERICAN SINGLE MALT / OTHER
                // unset — falls back to paid
                OwnedSeed("Westland American Oak", "Single Malt", "Westland", 92, 59.99,
                          [BottleState(false, false, daysAgoAdded: 11)]),

                OwnedSeed("Balcones Texas Single Malt", "Single Malt", "Balcones", 106, 54.99,
                          [BottleState(true, false, daysAgoAdded: 70, daysAgoOpened: 30)],
                          secondaryMarketValue: 52.99),

                // STORE PICKS
                OwnedSeed("Old Fitzgerald Bottled-in-Bond", "Bourbon", "Heaven Hill", 100, 44.99,
                          [BottleState(false, false, daysAgoAdded: 4)],
                          secondaryMarketValue: 54.99, isBiB: true),

                OwnedSeed("Maker's Mark Private Select", "Bourbon", "Maker's Mark", 108.2, 59.99,
                          [BottleState(true, false, daysAgoAdded: 140, daysAgoOpened: 60)],
                          secondaryMarketValue: 69.99,
                          isStorePick: true, storePickName: "Total Wine & More"),

                OwnedSeed("Four Roses Single Barrel Store Pick", "Bourbon", "Four Roses", 100, 54.99,
                          [BottleState(false, false, daysAgoAdded: 3)],
                          secondaryMarketValue: 64.99,
                          isSiB: true, isStorePick: true, storePickName: "The Whiskey Shop"),

                OwnedSeed("Elijah Craig Toasted Barrel", "Bourbon", "Heaven Hill", 94, 44.99,
                          [BottleState(true, false, daysAgoAdded: 55, daysAgoOpened: 20)],
                          secondaryMarketValue: 54.99),

                OwnedSeed("Widow Jane 10 Year", "Bourbon", "Widow Jane", 91, 79.99,
                          [BottleState(false, false, daysAgoAdded: 16)],
                          secondaryMarketValue: 69.99, age: "10"),

                // REPLACEMENT DEMO — idx 47
                // Killed 7 days ago, marked as wanting a replacement
                OwnedSeed("Old Weller Antique 107", "Bourbon", "Buffalo Trace", 107, 29.99,
                          [BottleState(true, true, daysAgoAdded: 120, daysAgoOpened: 80,
                                       daysAgoFinished: 7)],
                          secondaryMarketValue: 119.99),

                // REPLACEMENT CHAIN — idx 48 (original) → idx 49 (replacement)
                // Original Bulleit killed 45 days ago; replacement bottle bought shortly after
                OwnedSeed("Bulleit 10 Year", "Bourbon", "Four Roses", 91.2, 44.99,
                          [BottleState(true, true, daysAgoAdded: 150, daysAgoOpened: 100,
                                       daysAgoFinished: 45)],
                          secondaryMarketValue: 49.99, age: "10"),

                OwnedSeed("Bulleit 10 Year", "Bourbon", "Four Roses", 91.2, 47.99,
                          [BottleState(false, false, daysAgoAdded: 40)],
                          secondaryMarketValue: 49.99, age: "10"),
            ]

            var ownedWhiskeys: [Whiskey] = []
            for seed in ownedSeeds {
                let w = Whiskey(context: ctx)
                w.id = UUID()
                w.name = seed.name
                w.type = seed.type
                w.distillery = seed.distillery
                w.proof = seed.proof
                w.price = seed.price
                // Persist secondary when seeded; leave Core Data default 0 when nil
                // (blank → secondaryCurrentValue falls back to paid).
                w.secondaryMarketValue = seed.secondaryMarketValue ?? 0
                w.status = "owned"
                w.isBiB = seed.isBiB
                w.isSiB = seed.isSiB
                w.isStorePick = seed.isStorePick
                w.storePickName = seed.storePickName
                w.isCaskStrength = seed.isCaskStrength
                if let age = seed.age { w.age = age }
                let firstBottleAdded = seed.bottles.map { $0.daysAgoAdded }.max() ?? 30
                w.addedDate = cal.date(byAdding: .day, value: -firstBottleAdded, to: now) ?? now
                w.modificationDate = now
                w.numberOfBottles = Int16(seed.bottles.count)
                w.isTasted = false

                for (idx, b) in seed.bottles.enumerated() {
                    let bottle = BottleInstance(context: ctx)
                    bottle.id = UUID()
                    bottle.whiskey = w
                    bottle.bottleNumber = Int16(idx + 1)
                    bottle.price = seed.price
                    bottle.dateAdded = cal.date(byAdding: .day, value: -b.daysAgoAdded, to: now) ?? now
                    bottle.isOpen = b.open
                    bottle.isDead = b.dead
                    if b.open, let d = b.daysAgoOpened {
                        bottle.dateOpened = cal.date(byAdding: .day, value: -d, to: now)
                    }
                    if b.dead, let d = b.daysAgoFinished {
                        bottle.dateFinished = cal.date(byAdding: .day, value: -d, to: now)
                    }
                }
                w.updateFinishedStatus()
                ownedWhiskeys.append(w)
            }

            // MARK: - Replacement Setup
            // idx 47: Old Weller Antique — killed, wants a replacement
            if ownedWhiskeys.count > 47 {
                ownedWhiskeys[47].replacementStatus = "wantToReplace"
            }
            // idx 48 → 49: Bulleit 10 Year replacement chain
            if ownedWhiskeys.count > 49 {
                let original    = ownedWhiskeys[48]
                let replacement = ownedWhiskeys[49]
                original.replacedBy        = replacement
                replacement.replaces       = original
                replacement.replacementStatus = "isReplacement"
            }

            // MARK: - Wishlist
            struct WishlistSeed {
                let name, type, distillery: String
                let proof, price: Double
                let priority: Int16
                let rarity: WhiskeyRarity
                let store: Store?
            }
            let wishlistSeeds: [WishlistSeed] = [
                WishlistSeed(name: "George T. Stagg",         type: "Bourbon", distillery: "Buffalo Trace",  proof: 142.5, price: 99.99,  priority: 5, rarity: .unicorn,  store: store1),
                WishlistSeed(name: "William Larue Weller",    type: "Bourbon", distillery: "Buffalo Trace",  proof: 136.2, price: 89.99,  priority: 5, rarity: .unicorn,  store: store1),
                WishlistSeed(name: "Pappy Van Winkle 15 Year",type: "Bourbon", distillery: "Buffalo Trace",  proof: 107,   price: 299.99, priority: 3, rarity: .unicorn,  store: nil),
                WishlistSeed(name: "Van Winkle Lot B 12 Year",type: "Bourbon", distillery: "Buffalo Trace",  proof: 90.4,  price: 149.99, priority: 3, rarity: .unicorn,  store: nil),
                WishlistSeed(name: "Weller 12 Year",          type: "Bourbon", distillery: "Buffalo Trace",  proof: 90,    price: 39.99,  priority: 4, rarity: .rare,     store: store3),
                WishlistSeed(name: "Stagg Jr.",                type: "Bourbon", distillery: "Buffalo Trace",  proof: 131.1, price: 49.99,  priority: 5, rarity: .rare,     store: store1),
                WishlistSeed(name: "EH Taylor Small Batch",   type: "Bourbon", distillery: "Buffalo Trace",  proof: 100,   price: 44.99,  priority: 4, rarity: .rare,     store: nil),
                WishlistSeed(name: "WhistlePig 15 Year",      type: "Rye",     distillery: "WhistlePig",     proof: 92,    price: 149.99, priority: 3, rarity: .uncommon, store: store4),
                WishlistSeed(name: "Springbank 12 Year",      type: "Scotch",  distillery: "Springbank",     proof: 92,    price: 84.99,  priority: 3, rarity: .uncommon, store: store4),
                WishlistSeed(name: "Redbreast 21 Year",       type: "Irish",   distillery: "Midleton",       proof: 80,    price: 249.99, priority: 2, rarity: .rare,     store: store2),
                WishlistSeed(name: "Yamazaki 12 Year",        type: "Japanese",distillery: "Suntory",        proof: 86,    price: 149.99, priority: 4, rarity: .rare,     store: nil),
                WishlistSeed(name: "Blanton's Straight from the Barrel", type: "Bourbon", distillery: "Buffalo Trace", proof: 128.6, price: 129.99, priority: 5, rarity: .rare, store: store1),
            ]
            for seed in wishlistSeeds {
                let w = Whiskey(context: ctx)
                w.id = UUID()
                w.name = seed.name
                w.type = seed.type
                w.distillery = seed.distillery
                w.proof = seed.proof
                w.status = "wishlist"
                w.targetPrice = seed.price
                w.priority = seed.priority
                w.rarity = seed.rarity.rawValue
                w.addedDate = cal.date(byAdding: .day, value: -Int.random(in: 5...90), to: now) ?? now
                w.modificationDate = now
                if let store = seed.store {
                    w.addToStores(store)
                }
            }

            // MARK: - Journal Entries
            // Indices into ownedWhiskeys to journal-taste
            // We'll taste about 24 of the 46 bottles
            let tastedIndices: [(whiskeyIdx: Int, daysAgo: Int, rating: Double,
                                  serving: String, notes: String, nose: String,
                                  palate: String, finish: String,
                                  // [fruity, floral, spicy, woody, sweet, smoky, nutty, earthy]
                                  flavors: [Double])] = [
                // Buffalo Trace (idx 0) - daysAgo 5
                (0, 5, 8.2, "Neat",
                 "Classic Buffalo Trace profile — caramel and vanilla up front with a long, warming oak finish. Easy-drinking at 90 proof but complex enough to sip slowly.",
                 "Caramel, vanilla, light oak", "Vanilla, caramel, dried fruit", "Medium, warm, oaky",
                 [0.2, 0.1, 0.3, 0.7, 0.8, 0.05, 0.4, 0.2]),

                // Wild Turkey 101 (idx 1) - daysAgo 8
                (1, 8, 7.8, "Neat",
                 "Spicy and bold. That classic Wild Turkey rye bite comes through beautifully. Great value for the proof and complexity.",
                 "Vanilla, caramel, rye spice", "Spicy rye, caramel, oak tannins", "Long, spicy, dry",
                 [0.15, 0.1, 0.75, 0.6, 0.5, 0.05, 0.3, 0.25]),

                // Maker's Mark (idx 2) - daysAgo 6
                (2, 6, 7.5, "Neat",
                 "Soft and approachable. Wheat-forward with beautiful caramel. Not as complex as some but incredibly smooth for 90 proof.",
                 "Wheat, caramel, light vanilla", "Sweet wheat, caramel, honey", "Medium, smooth, slightly sweet",
                 [0.15, 0.2, 0.2, 0.5, 0.85, 0.0, 0.35, 0.1]),

                // Old Grand-Dad Bonded (idx 4) - daysAgo 7
                (4, 7, 8.0, "With a drop of water",
                 "Punchy high-rye mash bill shines at bonded proof. Huge value — this punches way above its price point. Peppery finish with surprising complexity.",
                 "Rye bread, honey, black pepper", "Spicy corn, rye, dried herbs", "Long, peppery, warm",
                 [0.1, 0.1, 0.85, 0.55, 0.5, 0.0, 0.25, 0.3]),

                // Elijah Craig Small Batch (idx 5) - daysAgo 10
                (5, 10, 8.3, "Neat",
                 "That Heaven Hill caramel-forward profile with notes of dark chocolate and baking spice. The charred barrel influence is prominent and delicious.",
                 "Brown sugar, toasted oak, light cherry", "Rich caramel, dark chocolate, baking spice", "Long, warm, slightly bitter chocolate",
                 [0.2, 0.1, 0.55, 0.7, 0.75, 0.0, 0.45, 0.2]),

                // Eagle Rare 10yr (idx 6) - daysAgo 12
                (6, 12, 8.6, "Neat",
                 "Absolutely outstanding for the price. Complex age-driven oak with a beautifully integrated sweetness. One of the best sub-$40 bourbons available when you can find it.",
                 "Orange peel, vanilla, gentle oak", "Rich vanilla, toffee, baking spice, dried fruit", "Long, silky, oaky warmth",
                 [0.35, 0.2, 0.4, 0.7, 0.75, 0.0, 0.45, 0.25]),

                // Woodford Reserve (idx 7) - daysAgo 9
                (7, 9, 7.9, "Neat",
                 "Balanced and polished. The triple-distilled profile comes through with a smooth, almost creamy texture. Fruit-forward with nice grain sweetness.",
                 "Stone fruit, vanilla, toasted grain", "Dried fruit, caramel, hint of mint", "Medium, clean, slightly fruity",
                 [0.55, 0.3, 0.35, 0.5, 0.65, 0.0, 0.3, 0.15]),

                // Knob Creek 9yr store pick (idx 8) - daysAgo 14
                (8, 14, 8.7, "Neat",
                 "This store pick is exceptional. The 9-year age on a high-rye mash bill at 100 proof is dialed in perfectly. Rich, complex, and satisfying. Worth hunting this pick down.",
                 "Toasted oak, brown sugar, rye spice", "Rich caramel, rye, dark fruit, charred wood", "Very long, oaky, spicy",
                 [0.3, 0.1, 0.7, 0.85, 0.7, 0.0, 0.35, 0.3]),

                // Russell's Reserve 10yr (idx 9) - daysAgo 4
                (9, 4, 8.4, "Neat",
                 "Beautifully aged Wild Turkey at a lower proof. The extra age tames the proof beautifully while adding layers of vanilla and dried fruit. Incredible balance.",
                 "Caramel, vanilla, hint of dried apricot", "Rich vanilla, toffee, gentle rye spice", "Long, smooth, slowly fading warmth",
                 [0.3, 0.15, 0.45, 0.65, 0.8, 0.0, 0.5, 0.2]),

                // Four Roses Single Barrel (idx 10) - daysAgo 18
                (10, 18, 9.0, "Neat",
                 "This is a special bottle. The OESV recipe at full proof is absolutely stunning — fruity, complex, and endlessly interesting. This is why Four Roses is held in such high regard.",
                 "Ripe red fruit, rose petals, caramel", "Layered fruit, dark cherry, spice, vanilla", "Incredibly long, spicy-sweet, warm",
                 [0.7, 0.4, 0.6, 0.5, 0.65, 0.0, 0.3, 0.1]),

                // Booker's (idx 13) - daysAgo 20
                (13, 20, 8.8, "With a drop of water",
                 "Monster bourbon. With a drop of water it opens up into something incredible. The raw cask strength proof makes it chewy and full of flavor. Not for the faint of heart.",
                 "Raw oak, dark caramel, alcohol heat", "Intense vanilla, brown sugar, black pepper", "Very long, warming, bold",
                 [0.2, 0.1, 0.65, 0.8, 0.75, 0.0, 0.4, 0.25]),

                // Elijah Craig Barrel Proof B523 (idx 15) - daysAgo 22
                (15, 22, 9.1, "Neat",
                 "B batch ECBP is the best batch. 119.6 proof feels remarkably balanced — no water needed. Complex, rich, and endlessly rewarding. This is one of the best bourbons available at any price.",
                 "Dark chocolate, roasted oak, dried cherry", "Rich molasses, spice, dark fruit, leather", "Extraordinarily long, complex finish",
                 [0.35, 0.1, 0.7, 0.85, 0.75, 0.0, 0.5, 0.4]),

                // Old Forester 1920 (idx 16) - daysAgo 15
                (16, 15, 8.5, "Neat",
                 "Old Forester 1920 is one of the most underrated bourbons in the game. Big and bold at 115 proof, beautifully complex, and incredibly affordable. Layers of baking spice and dark fruit.",
                 "Dark fruit, toasted spice, rich caramel", "Dark cherry, cinnamon, chocolate, vanilla", "Long, warming, chocolate and spice linger",
                 [0.45, 0.1, 0.7, 0.75, 0.7, 0.0, 0.3, 0.25]),

                // Blanton's Original (idx 18) - daysAgo 25
                (18, 25, 8.3, "Neat",
                 "The OG allocated bourbon that started the craze. At retail price it's outstanding — single barrel complexity with a beautiful floral and orange peel note. Worth tracking down at MSRP.",
                 "Orange blossom, vanilla, light floral", "Honey, dried orange, subtle oak", "Medium-long, sweet, gently fading",
                 [0.4, 0.45, 0.3, 0.5, 0.7, 0.0, 0.35, 0.1]),

                // Sazerac Rye (idx 22) - daysAgo 11
                (22, 11, 8.1, "Neat",
                 "Classic Buffalo Trace rye. Understated but elegant — not the biggest rye but beautifully balanced. The herbal, anise-like rye notes are really pleasant.",
                 "Anise, rye bread, light vanilla", "Spicy rye, cinnamon, subtle fruit", "Medium, dry, spicy",
                 [0.15, 0.2, 0.65, 0.5, 0.4, 0.0, 0.3, 0.2]),

                // Rittenhouse Rye (idx 23) - daysAgo 16
                (23, 16, 8.2, "On the rocks",
                 "The cocktail rye king, but outstanding neat too. Bottled-in-bond rye with a punchy profile — classic and balanced. Incredible value.",
                 "Rye spice, dried herbs, light caramel", "Big rye, black pepper, hint of sweetness", "Long, dry, peppery",
                 [0.1, 0.15, 0.9, 0.45, 0.35, 0.0, 0.2, 0.25]),

                // WhistlePig 10yr (idx 26) - daysAgo 28
                (26, 28, 8.9, "Neat",
                 "Exceptional Canadian rye aged to perfection in Vermont. Luxurious mouthfeel with layers of complexity — this is what a great rye whiskey can be.",
                 "Rich rye, vanilla, dried tropical fruit", "Dense rye spice, dark cherry, toasted oak", "Very long, complex, lingering spice",
                 [0.4, 0.2, 0.75, 0.7, 0.5, 0.0, 0.45, 0.2]),

                // Glenfiddich 12yr (idx 27) - daysAgo 30
                (27, 30, 7.6, "Neat",
                 "A great gateway Scotch and still enjoyable for seasoned drinkers. Light and approachable with beautiful pear and floral notes. The quintessential entry-point single malt.",
                 "Fresh pear, light malt, faint oak", "Pear, vanilla, subtle floral", "Short to medium, clean, malty",
                 [0.5, 0.35, 0.15, 0.4, 0.5, 0.05, 0.3, 0.1]),

                // Lagavulin 16yr (idx 28) - daysAgo 35
                (28, 35, 9.3, "Neat",
                 "The gold standard of peated Scotch. Incredibly complex smoke with coastal brine, dried fruit underneath, and a finish that lasts forever. One of the greatest whiskies ever made.",
                 "Heavy peat smoke, coastal brine, dried fruit underneath", "Enormous smoke, tarry rope, iodine, dark fruit", "Eternally long, smoky, slightly sweet coastal character",
                 [0.2, 0.1, 0.2, 0.5, 0.25, 0.95, 0.15, 0.65]),

                // Laphroaig 10yr (idx 29) - daysAgo 40
                (29, 40, 8.7, "Neat",
                 "Medicinal, maritime, and magnificent. Laphroaig is not for everyone but for those who love it, this is near perfection. Iodine, smoke, and a sweet malty backbone.",
                 "Band-aid, coastal peat, seaweed", "Medicinal peat, iodine, sweet malt underneath", "Long, smoky, slightly sweet",
                 [0.1, 0.1, 0.15, 0.4, 0.3, 0.9, 0.1, 0.6]),

                // Ardbeg 10yr (idx 30) - daysAgo 18
                (30, 18, 8.8, "Neat",
                 "Ardbeg at its most accessible. Huge Islay peat smoke balanced with lemon citrus and vanilla sweetness in a way that makes it surprisingly approachable. Remarkable complexity.",
                 "Intense peat, lemon zest, light vanilla", "Smoky, citrus, sweet caramel underneath", "Very long, smoky, lingering lemon",
                 [0.25, 0.15, 0.2, 0.45, 0.35, 0.88, 0.1, 0.5]),

                // Macallan 12yr Sherry (idx 32) - daysAgo 22
                (32, 22, 8.5, "Neat",
                 "The sherry influence is outstanding here — dried fruit, chocolate, and warm spice. The Macallan sherry oak style is one of the most distinctive in Scotch whisky.",
                 "Rich sherry, dried fruit, Christmas spice", "Dark fruit, chocolate, cinnamon, dried raisins", "Long, rich, gently fading sweetness",
                 [0.55, 0.15, 0.5, 0.6, 0.7, 0.0, 0.5, 0.2]),

                // Redbreast 12yr (idx 34) - daysAgo 13
                (34, 13, 9.0, "Neat",
                 "The standard bearer for Irish pot still whiskey. Redbreast 12 is one of the most complete and satisfying whiskies at any price. The combination of fruit, spice, and creamy texture is magical.",
                 "Tropical fruit, pot still spice, light vanilla", "Rich tropical fruit, spice, creamy texture", "Very long, spiced, slowly fading warmth",
                 [0.7, 0.35, 0.55, 0.4, 0.6, 0.0, 0.4, 0.15]),

                // Hibiki Harmony (idx 38) - daysAgo 27
                (38, 27, 8.6, "Neat",
                 "Japanese whisky philosophy at its finest. Incredible harmony between multiple grain and malt components. Delicate but complex — every sip reveals something new. A whisky for contemplation.",
                 "White flowers, honey, subtle spice", "Layered honey, orange peel, gentle wood", "Medium-long, clean, harmonious",
                 [0.45, 0.55, 0.25, 0.45, 0.65, 0.0, 0.35, 0.1]),
            ]

            for entry in tastedIndices {
                guard entry.whiskeyIdx < ownedWhiskeys.count else { continue }
                let whiskey = ownedWhiskeys[entry.whiskeyIdx]
                whiskey.isTasted = true

                let je = JournalEntry(context: ctx)
                je.id = UUID()
                je.whiskey = whiskey
                je.date = cal.date(byAdding: .day, value: -entry.daysAgo, to: now) ?? now
                je.modificationDate = now
                je.overallRating = entry.rating
                je.servingMethod = entry.serving
                je.notes = entry.notes
                je.nose = entry.nose
                je.palate = entry.palate
                je.finish = entry.finish

                // Populate flavor wheel
                var profile = FlavorProfile()
                let intensities = entry.flavors
                for (catIdx, category) in FlavorCategory.allCases.enumerated() {
                    let intensity = catIdx < intensities.count ? intensities[catIdx] : 0.0
                    if let noseIdx = profile.nose.firstIndex(where: { $0.category == category }) {
                        profile.nose[noseIdx].intensity = intensity
                    }
                    if let palateIdx = profile.palate.firstIndex(where: { $0.category == category }) {
                        profile.palate[palateIdx].intensity = max(0, intensity - 0.08)
                    }
                    if let finishIdx = profile.finish.firstIndex(where: { $0.category == category }) {
                        profile.finish[finishIdx].intensity = max(0, intensity - 0.18)
                    }
                }
                je.flavorProfileData = profile
            }

            // MARK: - Infinity Bottles
            let infinity1 = InfinityBottle(context: ctx)
            infinity1.id = UUID()
            infinity1.name = "My Everyday Blend"
            infinity1.typeCategory = "Bourbon"
            infinity1.notes = "Ongoing blend of everyday pours. Started with Buffalo Trace as the base, layering in Woodford for fruit and Knob Creek for depth. This evolves with each addition."
            infinity1.creationDate = cal.date(byAdding: .day, value: -120, to: now) ?? now
            infinity1.modificationDate = now
            infinity1.maxVolume = 750.0
            infinity1.currentVolume = 0.0

            let pours1: [(Int, Double, String, Int)] = [
                (0,  2.5, "Base pour — Buffalo Trace for that caramel and vanilla foundation", 115),
                (7,  2.0, "Woodford for stone fruit and grain complexity", 95),
                (8,  1.5, "Knob Creek store pick adds big oak and depth", 70),
                (9,  1.5, "Russell's Reserve 10yr brings age and balance", 50),
                (0,  1.0, "Topping off with more Buffalo Trace", 20),
                (4,  0.5, "Tiny dash of OGD Bonded for a proof bump and spice", 10),
            ]
            for (wIdx, amount, note, daysAgo) in pours1 {
                guard wIdx < ownedWhiskeys.count else { continue }
                let addition = BottleAddition(context: ctx)
                addition.id = UUID()
                addition.whiskey = ownedWhiskeys[wIdx]
                addition.amount = amount
                addition.proof = ownedWhiskeys[wIdx].proof
                addition.date = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
                addition.notes = note
                addition.infinityBottle = infinity1
                infinity1.currentVolume += amount
            }

            let infinity2 = InfinityBottle(context: ctx)
            infinity2.id = UUID()
            infinity2.name = "Islay Smoke Project"
            infinity2.typeCategory = "Scotch"
            infinity2.notes = "An experiment blending Islay's greatest peat monsters. Started with equal parts Lagavulin and Laphroaig, added Ardbeg for citrus balance. The smoke is immense but complex."
            infinity2.creationDate = cal.date(byAdding: .day, value: -60, to: now) ?? now
            infinity2.modificationDate = now
            infinity2.maxVolume = 750.0
            infinity2.currentVolume = 0.0

            let pours2: [(Int, Double, String, Int)] = [
                (28, 3.0, "Lagavulin 16 — the smoky, complex base", 55),
                (29, 3.0, "Laphroaig 10 — medicinal iodine depth", 45),
                (30, 2.0, "Ardbeg 10 — citrus and peat balance", 30),
                (28, 1.5, "More Lagavulin to smooth it out", 10),
            ]
            for (wIdx, amount, note, daysAgo) in pours2 {
                guard wIdx < ownedWhiskeys.count else { continue }
                let addition = BottleAddition(context: ctx)
                addition.id = UUID()
                addition.whiskey = ownedWhiskeys[wIdx]
                addition.amount = amount
                addition.proof = ownedWhiskeys[wIdx].proof
                addition.date = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
                addition.notes = note
                addition.infinityBottle = infinity2
                infinity2.currentVolume += amount
            }

            try ctx.save()
            DispatchQueue.main.async { completion(.success(())) }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
}
