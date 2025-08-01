import Foundation
import CoreData

extension JournalEntry {
    // Computed property to get/set the flavor profile
    var flavorProfileData: FlavorProfile? {
        get {
            guard let data = flavorProfile else { return nil }
            do {
                return try JSONDecoder().decode(FlavorProfile.self, from: data)
            } catch {
                print("Error decoding flavor profile: \(error)")
                return nil
            }
        }
        set {
            do {
                flavorProfile = try JSONEncoder().encode(newValue)
            } catch {
                print("Error encoding flavor profile: \(error)")
                flavorProfile = nil
            }
        }
    }
    
    // Helper to create a new flavor profile
    func createNewFlavorProfile() {
        flavorProfileData = FlavorProfile()
    }
    
    // Helper to update flavor intensity
    func updateFlavorIntensity(category: FlavorCategory, phase: TastingPhase, intensity: Double) {
        var profile = flavorProfileData ?? FlavorProfile()
        
        var intensities = phase == .nose ? profile.nose : (phase == .palate ? profile.palate : profile.finish)
        if let index = intensities.firstIndex(where: { $0.category == category }) {
            intensities[index].intensity = intensity
            if phase == .nose {
                profile.nose = intensities
            } else if phase == .palate {
                profile.palate = intensities
            } else {
                profile.finish = intensities
            }
        }
        
        flavorProfileData = profile
    }
    
    // Helper to update subflavors
    func updateSubflavors(category: FlavorCategory, phase: TastingPhase, subflavors: Set<String>) {
        var profile = flavorProfileData ?? FlavorProfile()
        
        var intensities = phase == .nose ? profile.nose : (phase == .palate ? profile.palate : profile.finish)
        if let index = intensities.firstIndex(where: { $0.category == category }) {
            intensities[index].selectedSubflavors = subflavors
            if phase == .nose {
                profile.nose = intensities
            } else if phase == .palate {
                profile.palate = intensities
            } else {
                profile.finish = intensities
            }
        }
        
        flavorProfileData = profile
    }
} 