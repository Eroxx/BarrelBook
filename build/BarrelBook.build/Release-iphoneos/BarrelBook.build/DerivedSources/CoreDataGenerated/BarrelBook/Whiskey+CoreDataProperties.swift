//
//  Whiskey+CoreDataProperties.swift
//  
//
//  Created by Eric Linder on 4/7/25.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension Whiskey {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Whiskey> {
        return NSFetchRequest<Whiskey>(entityName: "Whiskey")
    }

    @NSManaged public var age: String?
    @NSManaged public var distillery: String?
    @NSManaged public var finish: String?
    @NSManaged public var id: UUID?
    @NSManaged public var isBiB: Bool
    @NSManaged public var isFinished: Bool
    @NSManaged public var isOpen: Bool
    @NSManaged public var isSiB: Bool
    @NSManaged public var isStorePick: Bool
    @NSManaged public var modificationDate: Date?
    @NSManaged public var name: String?
    @NSManaged public var notes: String?
    @NSManaged public var numberOfBottles: Int16
    @NSManaged public var price: Double
    @NSManaged public var priority: Int16
    @NSManaged public var proof: Double
    @NSManaged public var recordID: String?
    @NSManaged public var status: String?
    @NSManaged public var storePickName: String?
    @NSManaged public var targetPrice: Double
    @NSManaged public var type: String?
    @NSManaged public var whereToFind: String?
    @NSManaged public var bottleAdditions: NSSet?
    @NSManaged public var customFields: NSSet?
    @NSManaged public var journalEntries: NSSet?
    @NSManaged public var webContent: NSSet?

}

// MARK: Generated accessors for bottleAdditions
extension Whiskey {

    @objc(addBottleAdditionsObject:)
    @NSManaged public func addToBottleAdditions(_ value: BottleAddition)

    @objc(removeBottleAdditionsObject:)
    @NSManaged public func removeFromBottleAdditions(_ value: BottleAddition)

    @objc(addBottleAdditions:)
    @NSManaged public func addToBottleAdditions(_ values: NSSet)

    @objc(removeBottleAdditions:)
    @NSManaged public func removeFromBottleAdditions(_ values: NSSet)

}

// MARK: Generated accessors for customFields
extension Whiskey {

    @objc(addCustomFieldsObject:)
    @NSManaged public func addToCustomFields(_ value: WhiskeyCustomField)

    @objc(removeCustomFieldsObject:)
    @NSManaged public func removeFromCustomFields(_ value: WhiskeyCustomField)

    @objc(addCustomFields:)
    @NSManaged public func addToCustomFields(_ values: NSSet)

    @objc(removeCustomFields:)
    @NSManaged public func removeFromCustomFields(_ values: NSSet)

}

// MARK: Generated accessors for journalEntries
extension Whiskey {

    @objc(addJournalEntriesObject:)
    @NSManaged public func addToJournalEntries(_ value: JournalEntry)

    @objc(removeJournalEntriesObject:)
    @NSManaged public func removeFromJournalEntries(_ value: JournalEntry)

    @objc(addJournalEntries:)
    @NSManaged public func addToJournalEntries(_ values: NSSet)

    @objc(removeJournalEntries:)
    @NSManaged public func removeFromJournalEntries(_ values: NSSet)

}

// MARK: Generated accessors for webContent
extension Whiskey {

    @objc(addWebContentObject:)
    @NSManaged public func addToWebContent(_ value: WebContent)

    @objc(removeWebContentObject:)
    @NSManaged public func removeFromWebContent(_ value: WebContent)

    @objc(addWebContent:)
    @NSManaged public func addToWebContent(_ values: NSSet)

    @objc(removeWebContent:)
    @NSManaged public func removeFromWebContent(_ values: NSSet)

}

extension Whiskey : Identifiable {

}
