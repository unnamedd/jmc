//
//  Artist+CoreDataProperties.swift
//  minimalTunes
//
//  Created by John Moody on 6/22/16.
//  Copyright © 2016 John Moody. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Artist {

    @NSManaged var id: NSNumber?
    @NSManaged var name: String?
    @NSManaged var albums: NSSet?
    @NSManaged var browser_object: ArtistColumnBrowserObject?
    @NSManaged var composers: NSSet?
    @NSManaged var properties: Property?
    @NSManaged var tracks: NSSet?

}