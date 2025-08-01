//
//  JournalEntry+CoreDataProperties.swift
//  
//
//  Created by Eric Linder on 4/9/25.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension JournalEntry {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<JournalEntry> {
        return NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
    }

    @NSManaged public var date: Date?
    @NSManaged public var finish: String?
    @NSManaged public var id: UUID?
    @NSManaged public var isInfinityBottle: Bool
    @NSManaged public var modificationDate: Date?
    @NSManaged public var nose: String?
    @NSManaged public var overallRating: Double
    @NSManaged public var palate: String?
    @NSManaged public var recordID: String?
    @NSManaged public var review: String?
    @NSManaged public var servingMethod: String?
    @NSManaged public var setting: String?
    @NSManaged public var customFields: NSSet?
    @NSManaged public var infinityBottle: InfinityBottle?
    @NSManaged public var whiskey: Whiskey?

}

// MARK: Generated accessors for customFields
extension JournalEntry {

    @objc(addCustomFieldsObject:)
    @NSManaged public func addToCustomFields(_ value: JournalCustomField)

    @objc(removeCustomFieldsObject:)
    @NSManaged public func removeFromCustomFields(_ value: JournalCustomField)

    @objc(addCustomFields:)
    @NSManaged public func addToCustomFields(_ values: NSSet)

    @objc(removeCustomFields:)
    @NSManaged public func removeFromCustomFields(_ values: NSSet)

}

extension JournalEntry : Identifiable {

}
