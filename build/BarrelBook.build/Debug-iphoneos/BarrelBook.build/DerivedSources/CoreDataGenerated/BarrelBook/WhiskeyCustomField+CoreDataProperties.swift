//
//  WhiskeyCustomField+CoreDataProperties.swift
//  
//
//  Created by Eric Linder on 4/9/25.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension WhiskeyCustomField {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<WhiskeyCustomField> {
        return NSFetchRequest<WhiskeyCustomField>(entityName: "WhiskeyCustomField")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var modificationDate: Date?
    @NSManaged public var name: String?
    @NSManaged public var recordID: String?
    @NSManaged public var type: String?
    @NSManaged public var value: NSObject?
    @NSManaged public var whiskey: Whiskey?

}

extension WhiskeyCustomField : Identifiable {

}
