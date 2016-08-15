//
//  Property+CoreDataProperties.swift
//  minimalTunes
//
//  Created by John Moody on 7/14/16.
//  Copyright © 2016 John Moody. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Property {

    @NSManaged var attribute: NSObject?
    @NSManaged var name: String?
    @NSManaged var type: NSObject?
    @NSManaged var album: Album?
    @NSManaged var artist: Artist?
    @NSManaged var tracks: NSSet?

}