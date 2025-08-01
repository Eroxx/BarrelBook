//
//  InfinityBottle+CoreDataProperties.swift
//  
//
//  Created by Eric Linder on 4/7/25.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension InfinityBottle {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<InfinityBottle> {
        return NSFetchRequest<InfinityBottle>(entityName: "InfinityBottle")
    }

    @NSManaged public var bottleImage: Data?
    @NSManaged public var creationDate: Date?
    @NSManaged public var currentVolume: Double
    @NSManaged public var id: UUID?
    @NSManaged public var maxVolume: Double
    @NSManaged public var modificationDate: Date?
    @NSManaged public var name: String?
    @NSManaged public var notes: String?
    @NSManaged public var recordID: String?
    @NSManaged public var typeCategory: String?
    @NSManaged public var additions: NSSet?
    @NSManaged public var journalEntries: NSSet?
    @NSManaged public var tastings: NSSet?

}

// MARK: Generated accessors for additions
extension InfinityBottle {

    @objc(addAdditionsObject:)
    @NSManaged public func addToAdditions(_ value: BottleAddition)

    @objc(removeAdditionsObject:)
    @NSManaged public func removeFromAdditions(_ value: BottleAddition)

    @objc(addAdditions:)
    @NSManaged public func addToAdditions(_ values: NSSet)

    @objc(removeAdditions:)
    @NSManaged public func removeFromAdditions(_ values: NSSet)

}

// MARK: Generated accessors for journalEntries
extension InfinityBottle {

    @objc(addJournalEntriesObject:)
    @NSManaged public func addToJournalEntries(_ value: JournalEntry)

    @objc(removeJournalEntriesObject:)
    @NSManaged public func removeFromJournalEntries(_ value: JournalEntry)

    @objc(addJournalEntries:)
    @NSManaged public func addToJournalEntries(_ values: NSSet)

    @objc(removeJournalEntries:)
    @NSManaged public func removeFromJournalEntries(_ values: NSSet)

}

// MARK: Generated accessors for tastings
extension InfinityBottle {

    @objc(addTastingsObject:)
    @NSManaged public func addToTastings(_ value: BottleTasting)

    @objc(removeTastingsObject:)
    @NSManaged public func removeFromTastings(_ value: BottleTasting)

    @objc(addTastings:)
    @NSManaged public func addToTastings(_ values: NSSet)

    @objc(removeTastings:)
    @NSManaged public func removeFromTastings(_ values: NSSet)

}

extension InfinityBottle : Identifiable {

}
