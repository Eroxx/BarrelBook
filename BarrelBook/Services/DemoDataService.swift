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

            // MARK: - Owned Collection
            struct OwnedSeed {
                let name, type, distillery: String
                let proof, price: Double
                let bottles: [(open: Bool, dead: Bool)]
                let isBiB, isSiB, isStorePick, isCaskStrength: Bool
                let storePickName: String?
                init(_ name: String,_ type: String,_ distillery: String,_ proof: Double,_ price: Double,
                     _ bottles: [(open: Bool, dead: Bool)],
                     isBiB: Bool = false, isSiB: Bool = false,
                     isStorePick: Bool = false, storePickName: String? = nil,
                     isCaskStrength: Bool = false) {
                    self.name=name; self.type=type; self.distillery=distillery
                    self.proof=proof; self.price=price; self.bottles=bottles
                    self.isBiB=isBiB; self.isSiB=isSiB; self.isStorePick=isStorePick
                    self.storePickName=storePickName; self.isCaskStrength=isCaskStrength
                }
            }
            let ownedSeeds: [OwnedSeed] = [
                OwnedSeed("Buffalo Trace","Bourbon","Buffalo Trace",90,24.99,[(true,false)]),
                OwnedSeed("Eagle Rare 10 Year","Bourbon","Buffalo Trace",90,34.99,[(true,false),(false,false)]),
                OwnedSeed("Four Roses Single Barrel","Bourbon","Four Roses",100,44.99,[(true,true)],isSiB:true),
                OwnedSeed("Wild Turkey 101","Bourbon","Wild Turkey",101,22.99,[(false,false)],isBiB:true),
                OwnedSeed("Lagavulin 16 Year","Scotch","Lagavulin",86,89.99,[(true,false)]),
                OwnedSeed("Woodford Reserve","Bourbon","Woodford Reserve",90.4,32.99,[(false,false)]),
                OwnedSeed("Knob Creek 9 Year","Bourbon","Jim Beam",100,38.99,[(true,false),(false,false)],isStorePick:true,storePickName:"Local Liquor"),
                OwnedSeed("Russell's Reserve 10 Year","Bourbon","Wild Turkey",90,35.99,[(true,false)]),
                OwnedSeed("Sazerac Rye","Rye","Buffalo Trace",90,28.99,[(false,false)],isBiB:true),
                OwnedSeed("Glenfiddich 12 Year","Scotch","Glenfiddich",80,42.99,[(true,false)]),
                OwnedSeed("Maker's Mark","Bourbon","Maker's Mark",90,26.99,[(true,false),(false,false)],isStorePick:true,storePickName:"Total Wine"),
                OwnedSeed("Old Grand-Dad Bonded","Bourbon","Jim Beam",100,19.99,[(false,false)],isBiB:true),
                OwnedSeed("Booker's","Bourbon","Jim Beam",126,89.99,[(true,false)],isCaskStrength:true),
                OwnedSeed("Larceny Barrel Proof","Bourbon","Heaven Hill",123,54.99,[(false,false)],isCaskStrength:true),
            ]
            var ownedWhiskeys: [Whiskey] = []
            for seed in ownedSeeds {
                let w = Whiskey(context: ctx)
                w.id = UUID(); w.name = seed.name; w.type = seed.type
                w.distillery = seed.distillery; w.proof = seed.proof; w.price = seed.price
                w.status = "owned"; w.isBiB = seed.isBiB; w.isSiB = seed.isSiB
                w.isStorePick = seed.isStorePick; w.storePickName = seed.storePickName
                w.isCaskStrength = seed.isCaskStrength
                w.addedDate = cal.date(byAdding: .day, value: -Int.random(in: 30...200), to: now) ?? now
                w.modificationDate = now; w.numberOfBottles = Int16(seed.bottles.count); w.isTasted = false
                for (idx, b) in seed.bottles.enumerated() {
                    let bottle = BottleInstance(context: ctx)
                    bottle.id = UUID(); bottle.whiskey = w; bottle.bottleNumber = Int16(idx+1)
                    bottle.price = seed.price; bottle.dateAdded = w.addedDate
                    bottle.isOpen = b.open; bottle.isDead = b.dead
                    if b.open { bottle.dateOpened = cal.date(byAdding: .day, value: -20, to: now) }
                    if b.dead { bottle.dateFinished = cal.date(byAdding: .day, value: -5, to: now) }
                }
                w.updateFinishedStatus()
                ownedWhiskeys.append(w)
            }

            // MARK: - Wishlist (varied distilleries, proof set, rarity set)
            struct WishlistSeed {
                let name, type, distillery: String
                let proof, price: Double
                let priority: Int16
                let rarity: WhiskeyRarity
            }
            let wishlistSeeds: [WishlistSeed] = [
                WishlistSeed(name:"Stagg Jr",           type:"Bourbon", distillery:"Buffalo Trace",  proof:131.1, price:49.99,  priority:5, rarity:.rare),
                WishlistSeed(name:"Blanton's Original", type:"Bourbon", distillery:"Buffalo Trace",  proof:93,    price:69.99,  priority:5, rarity:.unicorn),
                WishlistSeed(name:"Weller 12 Year",     type:"Bourbon", distillery:"Buffalo Trace",  proof:90,    price:39.99,  priority:4, rarity:.rare),
                WishlistSeed(name:"EH Taylor Small Batch", type:"Bourbon", distillery:"Buffalo Trace", proof:100, price:44.99, priority:4, rarity:.rare),
                WishlistSeed(name:"Pappy Van Winkle 15 Year", type:"Bourbon", distillery:"Buffalo Trace", proof:107, price:299.99, priority:3, rarity:.unicorn),
                WishlistSeed(name:"Elijah Craig Barrel Proof", type:"Bourbon", distillery:"Heaven Hill", proof:124.9, price:59.99, priority:4, rarity:.uncommon),
                WishlistSeed(name:"High West Double Rye", type:"Rye",    distillery:"High West",     proof:92,    price:34.99,  priority:3, rarity:.common),
                WishlistSeed(name:"Ardbeg 10 Year",     type:"Scotch",  distillery:"Ardbeg",         proof:92,    price:54.99,  priority:3, rarity:.uncommon),
            ]
            let wishlistStores = [store1, store2, store3, store1, store3, store2, store1, store2]
            for (i, seed) in wishlistSeeds.enumerated() {
                let w = Whiskey(context: ctx)
                w.id = UUID(); w.name = seed.name; w.type = seed.type; w.distillery = seed.distillery
                w.proof = seed.proof; w.status = "wishlist"; w.targetPrice = seed.price
                w.priority = seed.priority; w.rarity = seed.rarity.rawValue
                w.addedDate = cal.date(byAdding: .day, value: -Int.random(in: 5...60), to: now) ?? now
                w.modificationDate = now
                w.addToStores(wishlistStores[i % wishlistStores.count])
            }

            // MARK: - Journal Entries with populated flavor wheels
            let servingMethods = ["Neat", "Neat", "With a drop of water", "On the rocks"]
            let tastingNotes = [
                "Caramel and vanilla up front, long oaky finish. Classic Buffalo Trace profile.",
                "Smoky and rich with coastal brine. A peated masterpiece.",
                "Sweet corn, cinnamon, and a spicy long finish. High rye content shines.",
                "Fruity nose, complex spicy palate. Single barrel variation at its best.",
                "Honey and vanilla on the nose. The extra age adds beautiful complexity.",
                "Brown sugar and baking spice. Bonded proof gives great texture.",
                "Rich caramel with dark fruit. The barrel proof makes it chewy and full.",
                "Light and floral with fresh oak. A great introductory scotch.",
            ]
            let noses   = ["Sweet, oak, hint of vanilla","Smoke, peat, citrus","Corn, honey, baking spice","Caramel, dried fruit","Vanilla, toffee, light oak","Apple, pear, floral","Brown sugar, cinnamon","Cherry, nutmeg"]
            let palates = ["Vanilla, caramel, oak","Peaty, brine, lemon","Sweet corn, cinnamon, pepper","Rich caramel, dark fruit","Creamy vanilla, toffee","Fruity, honey, mild spice","Spicy, sweet, rounded","Stone fruit, oak, spice"]
            let finishes = ["Medium, warm, oaky","Long, smoky, coastal","Medium-long, spicy","Long, sweet, drying","Medium, smooth","Short to medium, clean","Warm, lingering spice","Medium, nutty tail"]

            // Flavor wheel profiles per entry — intensities for [fruity, floral, spicy, woody, sweet, smoky, nutty, earthy]
            let flavorProfiles: [[Double]] = [
                [0.2, 0.1, 0.3, 0.7, 0.8, 0.1, 0.4, 0.2],  // Buffalo Trace: sweet/woody
                [0.1, 0.1, 0.2, 0.4, 0.2, 0.9, 0.1, 0.5],  // Lagavulin: smoky/earthy
                [0.3, 0.1, 0.7, 0.5, 0.6, 0.1, 0.2, 0.2],  // Knob Creek: spicy/sweet
                [0.5, 0.3, 0.4, 0.4, 0.5, 0.1, 0.3, 0.1],  // Four Roses: fruity/balanced
                [0.2, 0.2, 0.2, 0.6, 0.7, 0.1, 0.5, 0.2],  // Russell's: sweet/nutty
                [0.1, 0.1, 0.3, 0.5, 0.7, 0.1, 0.6, 0.2],  // Sazerac: sweet/nutty
                [0.3, 0.1, 0.5, 0.6, 0.6, 0.1, 0.3, 0.2],  // Eagle Rare: woody/spicy
                [0.2, 0.3, 0.2, 0.5, 0.4, 0.1, 0.3, 0.3],  // Glenfiddich: floral/woody
                [0.2, 0.1, 0.4, 0.6, 0.7, 0.1, 0.4, 0.2],  // Maker's: sweet/woody
                [0.3, 0.2, 0.3, 0.5, 0.6, 0.1, 0.5, 0.2],  // Woodford: balanced
                [0.2, 0.1, 0.3, 0.7, 0.8, 0.1, 0.4, 0.2],  // Buffalo Trace (repeat)
                [0.1, 0.1, 0.2, 0.4, 0.2, 0.9, 0.1, 0.5],  // Lagavulin (repeat)
                [0.1, 0.1, 0.3, 0.5, 0.7, 0.1, 0.6, 0.2],  // Sazerac (repeat)
                [0.3, 0.2, 0.3, 0.5, 0.6, 0.1, 0.5, 0.2],  // Russell's (repeat)
            ]

            let whiskeyIndices = [0,1,2,4,5,6,7,8,9,10,0,1,4,7]  // 14 entries across 10 unique bottles
            let daysAgo        = [1,2,4,5,7,8,10,12,14,16,18,20,22,25]
            for (i, wIdx) in whiskeyIndices.enumerated() {
                guard wIdx < ownedWhiskeys.count else { continue }
                let whiskey = ownedWhiskeys[wIdx]; whiskey.isTasted = true
                let entry = JournalEntry(context: ctx)
                entry.id = UUID(); entry.whiskey = whiskey
                entry.date = cal.date(byAdding: .day, value: -daysAgo[i], to: now) ?? now
                entry.modificationDate = now
                entry.overallRating = Double.random(in: 6.5...9.0)
                entry.servingMethod = servingMethods[i % servingMethods.count]
                entry.notes   = tastingNotes[i % tastingNotes.count]
                entry.nose    = noses[i % noses.count]
                entry.palate  = palates[i % palates.count]
                entry.finish  = finishes[i % finishes.count]

                // Populate flavor wheel with realistic intensities
                var profile = FlavorProfile()
                let intensities = flavorProfiles[i % flavorProfiles.count]
                for phase in [profile.nose, profile.palate, profile.finish] {
                    _ = phase // accessed below via index
                }
                for (catIdx, category) in FlavorCategory.allCases.enumerated() {
                    let intensity = catIdx < intensities.count ? intensities[catIdx] : 0.0
                    if let noseIdx = profile.nose.firstIndex(where: { $0.category == category }) {
                        profile.nose[noseIdx].intensity = intensity
                    }
                    if let palateIdx = profile.palate.firstIndex(where: { $0.category == category }) {
                        profile.palate[palateIdx].intensity = max(0, intensity - 0.1)
                    }
                    if let finishIdx = profile.finish.firstIndex(where: { $0.category == category }) {
                        profile.finish[finishIdx].intensity = max(0, intensity - 0.2)
                    }
                }
                entry.flavorProfileData = profile
            }

            // MARK: - Infinity Bottle
            let infinity = InfinityBottle(context: ctx)
            infinity.id = UUID()
            infinity.name = "My Everyday Blend"
            infinity.typeCategory = "Bourbon"
            infinity.notes = "Ongoing blend of everyday pours. Started with Buffalo Trace and Woodford as the base."
            infinity.creationDate = cal.date(byAdding: .day, value: -90, to: now) ?? now
            infinity.modificationDate = now
            infinity.maxVolume = 750.0
            infinity.currentVolume = 0.0

            // Add pours from 5 bottles
            let infinityPours: [(Whiskey, Double, String)] = [
                (ownedWhiskeys[0], 2.0, "Base pour — clean and approachable"),
                (ownedWhiskeys[5], 1.5, "Added Woodford for floral notes"),
                (ownedWhiskeys[7], 1.5, "Russell's adds some age and depth"),
                (ownedWhiskeys[3], 1.0, "Wild Turkey for a proof bump"),
                (ownedWhiskeys[0], 1.0, "Topped off with more Buffalo Trace"),
            ]
            let pourDaysAgo = [85, 70, 55, 30, 10]
            for (idx, (whiskey, amount, note)) in infinityPours.enumerated() {
                let addition = BottleAddition(context: ctx)
                addition.id = UUID()
                addition.whiskey = whiskey
                addition.amount = amount
                addition.proof = whiskey.proof
                addition.date = cal.date(byAdding: .day, value: -pourDaysAgo[idx], to: now) ?? now
                addition.notes = note
                addition.infinityBottle = infinity
                infinity.currentVolume += amount
            }

            try ctx.save()
            DispatchQueue.main.async { completion(.success(())) }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
}
