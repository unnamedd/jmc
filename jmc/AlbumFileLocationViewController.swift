//
//  AlbumFileLocationViewController.swift
//  jmc
//
//  Created by John Moody on 9/7/17.
//  Copyright © 2017 John Moody. All rights reserved.
//

import Cocoa

class AlbumFilePathNode: NSObject {
    
    var pathComponent: String
    var children = [AlbumFilePathNode]()
    var parent: AlbumFilePathNode?
    var totalFiles = Set<NSObject>()
    var objectPathDictionaryIfRoot: [NSObject: URL]?
    
    
    init(pathComponent: String, parent: AlbumFilePathNode? = nil) {
        self.pathComponent = pathComponent
        self.parent = parent
        super.init()
        if let parent = parent {
            if let index = parent.children.index(where: {$0.pathComponent.localizedStandardCompare(pathComponent) == ComparisonResult.orderedDescending}) {
                parent.children.insert(self, at: index)
            } else {
                parent.children.append(self)
            }
        }
    }
    
    func numberBeneath() -> Int {
        var sum = 0
        for child in self.children {
            sum += child.numberBeneath()
            if child.children.count == 0 {
                sum += 1
            }
        }
        return sum
    }
    
    func completePathRepresentation() -> String {
        var pathComponents = [self.pathComponent]
        var node = self
        while node.parent != nil {
            node = node.parent!
            pathComponents.append(node.pathComponent)
        }
        pathComponents.reverse()
        let path = "/" + pathComponents.filter({$0 != "" && $0 != "/"}).joined(separator: "/")
        return path
    }
    
    func removeFileRecursive(_ file: NSObject) {
        if let file = self.totalFiles.remove(file) {
            for child in self.children {
                child.removeFileRecursive(file)
            }
        }
    }
    
    func getEmptyNodesBeneath() -> [AlbumFilePathNode] {
        var nodes = [AlbumFilePathNode]()
        for child in self.children {
            nodes.append(contentsOf: child.getEmptyNodesBeneath())
        }
        if self.totalFiles.count < 1 {
            nodes.append(self)
        }
        return nodes
    }
    
    func purge() {
        for child in self.children {
            child.purge()
        }
        if self.totalFiles.count < 1 {
            self.parent!.children.remove(at: self.parent!.children.index(of: self)!)
        }
    }
    
    func getChildrenWithObject(object: NSObject) {
        if self.totalFiles.contains(object) {
            for child in self.children {
                
            }
        }
    }
    
}

class AlbumFilePathTree: NSObject {
    
    var rootNode: AlbumFilePathNode
    
    func createNode(with pathComponents: inout [String], under parentOrRoot: AlbumFilePathNode? = nil, with file: NSObject) {
        guard pathComponents.count > 0 else { return }
        
        let currentNode = parentOrRoot ?? rootNode
        currentNode.totalFiles.insert(file)
        
        let nextPathComponent = pathComponents.removeFirst()
        
        if let nextNode = currentNode.children.first(where: {$0.pathComponent == nextPathComponent}) {
            createNode(with: &pathComponents, under: nextNode, with: file)
        } else {
            let newNode = AlbumFilePathNode(pathComponent: nextPathComponent, parent: currentNode)
            let nextURLString = URL(fileURLWithPath: newNode.completePathRepresentation()).absoluteString
            let setUnderNextNode = Set(currentNode.totalFiles.filter({file in
                let location = {() -> String? in
                    switch file {
                    case let track as Track:
                        return track.location
                    case let albumFile as AlbumFile:
                        return albumFile.location
                    case let albumArtwork as AlbumArtwork:
                        return albumArtwork.location
                    default:
                        return "poop"
                    }
                }()
                return location?.hasPrefix(nextURLString) ?? false
            }))
            newNode.totalFiles = setUnderNextNode
            if pathComponents.count > 0 {
                createNode(with: &pathComponents, under: newNode, with: file)
            } else {
                newNode.totalFiles.insert(file)
                return
            }
        }
    }
    
    init(files: inout [NSObject : URL]) {
        self.rootNode = AlbumFilePathNode(pathComponent: "/")
        self.rootNode.totalFiles = Set(files.keys)
        self.rootNode.objectPathDictionaryIfRoot = files
        super.init()
        for file in files {
            let url = file.value
            var path = url.path.components(separatedBy: "/").filter({$0 != ""})
            let object = file.key
            createNode(with: &path, with: object)
        }
    }
    
    func getFilteredTree(withSearchString searchString: String) -> AlbumFilePathTree {
        let currentFiles = self.rootNode.objectPathDictionaryIfRoot!
        var filteredFiles = currentFiles.filter({ (key: NSObject, value: URL) -> Bool in
            return value.path.localizedCaseInsensitiveContains(searchString)
        })
        return AlbumFilePathTree(files: &filteredFiles)
    }
    
    func getNodesForObjects(objects: Set<NSObject>) {
        
    }
}

class AlbumFileLocationViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    
    var masterTree: AlbumFilePathTree!
    var filteredTree: AlbumFilePathTree!
    var parentController: ConsolidateLibrarySheetController!
    
    var isSearching = false
    
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var tableLabel: NSTextField!
    @IBOutlet weak var showSelectionButton: NSButton!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        self.outlineView.expandItem(nil, expandChildren: true)
    }
    
    func setupForOldLocations() {
        self.tableLabel.stringValue = "Current locations:"
        self.showSelectionButton.stringValue = "Show New Location"
    }
    
    func setupForNewLocations() {
        self.tableLabel.stringValue = "New locations:"
        self.showSelectionButton.title = "Show Old Location"
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if outlineView.selectedRowIndexes.count > 0 {
            self.showSelectionButton.isEnabled = true
        } else {
            self.showSelectionButton.isEnabled = false
        }
    }
    
    @IBAction func showSelectionPressed(_ sender: Any) {
        let pathNodes = outlineView.selectedRowIndexes.map({return outlineView.item(atRow: $0) as! AlbumFilePathNode})
        var representedObjects = Set<NSObject>()
        for pathNode in pathNodes {
            representedObjects.formUnion(pathNode.totalFiles)
        }
        self.parentController.showSelectionPressed(sender: self, items: representedObjects)
    }
    
    func showItems(items: Set<NSObject>) {
        
        self.outlineView.selectRowIndexes(<#T##indexes: IndexSet##IndexSet#>, byExtendingSelection: <#T##Bool#>)
    }
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? AlbumFilePathNode else { return nil }
        let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "pathnode"), owner: node) as! NSTableCellView
        view.objectValue = node
        let url = URL(fileURLWithPath: node.completePathRepresentation())
        let keys = [URLResourceKey.effectiveIconKey, URLResourceKey.customIconKey]
        if let values = try? url.resourceValues(forKeys: Set(keys)) {
            view.imageView?.image = values.customIcon ?? values.effectiveIcon as? NSImage
        } else {
            if node.children.count > 0 {
                view.imageView?.image = NSImage(named: NSImage.Name.folder)
            } else {
                view.imageView?.image = NSImage(named: NSImage.Name.multipleDocuments)
            }
        }
        view.textField?.stringValue = node.pathComponent
        return view
    }
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        switch self.isSearching {
        case true:
            guard let node = item as? AlbumFilePathNode else { return self.filteredTree.rootNode.children.count }
            return node.children.count
        case false:
            guard let node = item as? AlbumFilePathNode else { return self.masterTree.rootNode.children.count }
            return node.children.count
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        switch self.isSearching {
        case true:
            guard let node = item as? AlbumFilePathNode else { return self.filteredTree.rootNode }
            return node.children[index]
        case false:
            guard let node = item as? AlbumFilePathNode else { return self.masterTree.rootNode }
            return node.children[index]
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? AlbumFilePathNode else { return false }
        return node.children.count > 0
    }
    
    //searching
    func searchFieldDidStartSearching(_ sender: NSSearchField) {
        self.isSearching = true
        self.filteredTree = self.masterTree.getFilteredTree(withSearchString: sender.stringValue)
        self.outlineView.reloadData()
        self.outlineView.expandItem(nil, expandChildren: true)
    }
    
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        self.isSearching = false
        self.outlineView.reloadData()
        self.outlineView.expandItem(nil, expandChildren: true)
    }
    
}