//
//  BottleAddition+CoreDataProperties.swift
//  
//
//  Created by Eric Linder on 4/7/25.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension BottleAddition {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<BottleAddition> {
        return NSFetchRequest<BottleAddition>(entityName: "BottleAddition")
    }

    @NSManaged public var amount: Double
    @NSManaged public var date: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var modificationDate: Date?
    @NSManaged public var notes: String?
    @NSManaged public var proof: Double
    @NSManaged public var recordID: String?
    @NSManaged public var infinityBottle: InfinityBottle?
    @NSManaged public var whiskey: Whiskey?

}

extension BottleAddition : Identifiable {

}
