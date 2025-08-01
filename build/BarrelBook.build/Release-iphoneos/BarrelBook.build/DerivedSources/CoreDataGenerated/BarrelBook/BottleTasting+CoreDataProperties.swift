//
//  BottleTasting+CoreDataProperties.swift
//  
//
//  Created by Eric Linder on 4/7/25.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension BottleTasting {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<BottleTasting> {
        return NSFetchRequest<BottleTasting>(entityName: "BottleTasting")
    }

    @NSManaged public var date: Date?
    @NSManaged public var finish: String?
    @NSManaged public var id: UUID?
    @NSManaged public var modificationDate: Date?
    @NSManaged public var nose: String?
    @NSManaged public var notes: String?
    @NSManaged public var palate: String?
    @NSManaged public var rating: Double
    @NSManaged public var recordID: String?
    @NSManaged public var infinityBottle: InfinityBottle?

}

extension BottleTasting : Identifiable {

}
