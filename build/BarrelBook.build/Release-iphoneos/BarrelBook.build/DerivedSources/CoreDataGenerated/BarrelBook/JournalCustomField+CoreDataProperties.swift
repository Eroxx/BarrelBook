//
//  JournalCustomField+CoreDataProperties.swift
//  
//
//  Created by Eric Linder on 4/7/25.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension JournalCustomField {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<JournalCustomField> {
        return NSFetchRequest<JournalCustomField>(entityName: "JournalCustomField")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var modificationDate: Date?
    @NSManaged public var name: String?
    @NSManaged public var recordID: String?
    @NSManaged public var type: String?
    @NSManaged public var value: NSObject?
    @NSManaged public var journalEntry: JournalEntry?

}

extension JournalCustomField : Identifiable {

}
