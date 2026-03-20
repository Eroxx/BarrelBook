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

            let store = Store(context: ctx)
            store.id = UUID()
            store.name = "Local Liquor & Wine"
            store.address = "123 Main St"
            store.isFavorite = true
            store.modificationDate = now

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

            let wishlistSeeds: [(String,String,String,Double,Int16)] = [
                ("Stagg Jr","Bourbon","Buffalo Trace",49.99,5),
                ("Blanton's Original","Bourbon","Buffalo Trace",69.99,5),
                ("Weller 12 Year","Bourbon","Buffalo Trace",39.99,4),
                ("EH Taylor Small Batch","Bourbon","Buffalo Trace",44.99,4),
            ]
            for (name,type,dist,price,pri) in wishlistSeeds {
                let w = Whiskey(context: ctx)
                w.id = UUID(); w.name = name; w.type = type; w.distillery = dist
                w.status = "wishlist"; w.targetPrice = price; w.priority = pri
                w.addedDate = cal.date(byAdding: .day, value: -Int.random(in: 5...60), to: now) ?? now
                w.modificationDate = now; w.addToStores(store)
            }

            let servingMethods = ["Neat","Neat","With a drop of water","On the rocks"]
            let tastingNotes = ["Caramel and vanilla up front, oaky finish.","Smoky and rich.","Sweet corn, cinnamon, long finish.","Fruity nose, spicy palate."]
            let noses = ["Sweet, oak, hint of vanilla","Smoke, peat, citrus","Corn, honey, baking spice","Caramel, dried fruit","Vanilla, toffee, light oak","Apple, pear, floral","Brown sugar, cinnamon","Cherry, nutmeg"]
            let palates = ["Vanilla, caramel, oak","Peaty, brine, lemon","Sweet corn, cinnamon, pepper","Rich caramel, dark fruit","Creamy vanilla, toffee","Fruity, honey, mild spice","Spicy, sweet, rounded","Stone fruit, oak, spice"]
            let finishes = ["Medium, warm, oaky","Long, smoky, coastal","Medium-long, spicy","Long, sweet, drying","Medium, smooth","Short to medium, clean","Warm, lingering spice","Medium, nutty tail"]
            let whiskeyIndices = [0,1,2,4,5,6,7,8,9,10,0,1,4,7]
            let daysAgo      = [1,2,4,5,7,8,10,12,14,16,18,20,22,25]
            for (i, wIdx) in whiskeyIndices.enumerated() {
                guard wIdx < ownedWhiskeys.count else { continue }
                let whiskey = ownedWhiskeys[wIdx]; whiskey.isTasted = true
                let entry = JournalEntry(context: ctx)
                entry.id = UUID(); entry.whiskey = whiskey
                entry.date = cal.date(byAdding: .day, value: -daysAgo[i], to: now) ?? now
                entry.modificationDate = now
                entry.overallRating = Double.random(in: 6.5...9.0)
                entry.servingMethod = servingMethods[i % servingMethods.count]
                entry.notes = tastingNotes[i % tastingNotes.count]
                entry.nose = noses[i % noses.count]
                entry.palate = palates[i % palates.count]
                entry.finish = finishes[i % finishes.count]
                entry.flavorProfileData = FlavorProfile()
            }

            try ctx.save()
            DispatchQueue.main.async { completion(.success(())) }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
}
