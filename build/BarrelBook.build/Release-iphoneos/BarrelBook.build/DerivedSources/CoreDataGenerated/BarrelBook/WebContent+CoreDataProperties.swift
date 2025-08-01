//
//  WebContent+CoreDataProperties.swift
//  
//
//  Created by Eric Linder on 4/7/25.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension WebContent {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<WebContent> {
        return NSFetchRequest<WebContent>(entityName: "WebContent")
    }

    @NSManaged public var content: String?
    @NSManaged public var date: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var sourceURL: String?
    @NSManaged public var title: String?
    @NSManaged public var whiskey: Whiskey?

}

extension WebContent : Identifiable {

}
