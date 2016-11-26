//
//  MaybeTheLastServerAttempt.swift
//  minimalTunes
//
//  Created by John Moody on 10/2/16.
//  Copyright © 2016 John Moody. All rights reserved.
//

import sReto

class P2PServer {
    let metadataDelegate = SharedLibraryRequestHandler()
    let wlanModule: WlanModule
    let remoteModule: RemoteP2PModule
    let localPeer: LocalPeer
    let delegate: AppDelegate
    let interface: MainWindowController
    let peerConnectionDictionary = NSMutableDictionary()
    let namePeerDictionary = NSMutableDictionary()
    var isStreaming = false
    var isPlayingBackStream = false

    
    init(_delegate: AppDelegate) {
        self.delegate = _delegate
        self.interface = delegate.mainWindowController!
        self.wlanModule = WlanModule(type: "metunes", dispatchQueue: dispatch_get_main_queue())
        self.remoteModule = RemoteP2PModule(baseUrl: NSURL(string: "ws://162.243.26.172:8080/")!, dispatchQueue: dispatch_get_main_queue())
        self.localPeer = LocalPeer(modules: [self.wlanModule], dispatchQueue: dispatch_get_main_queue())
        self.localPeer.start(
            onPeerDiscovered: { peer in
                print("discovered peer")
                self.onPeerDiscovered(peer)
            },
            onPeerRemoved: { peer in print("Removed peer: \(peer)") },
            onIncomingConnection: { peer, connection in
                print("Received incoming connection: \(connection) from peer: \(peer.identifier)")
                self.onIncomingConnection(peer, connection: connection)
            },
            displayName: "MyLocalPeer"
        )
    }
    
    func onPeerDiscovered(peer: RemotePeer) {
        let connection = peer.connect()
        connection.onClose = { connection in print("Connection closed.") }
        connection.onError = { error in print("error: \(error)") }
        connection.onData = { data in print("Received data!") }
        connection.onConnect = { connection in
            print("successfully connected")
            self.onIncomingConnection(peer, connection: connection)
            self.askPeerForLibraryName(peer, connection: connection)
        }
    }
    
    func onPeerRemoved(peer: RemotePeer) {
        //interface.removeNetworkedLibrary(peer.name!)
    }
    
    func onIncomingConnection(peer: RemotePeer, connection: Connection) {
        connection.onTransfer = { connection, transfer in
            transfer.onProgress = {transfer in print("current progress: \(transfer.progress) of \(transfer.length)") }
            transfer.onCompleteData = {transfer, data in self.parseTransfer(peer, connection: connection, transfer: transfer, data: data) }
        }
    }
    
    func parseTransfer(peer: RemotePeer, connection: Connection, transfer: Transfer, data: NSData) {
        var requestDict: NSDictionary!
        do {
            requestDict = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.AllowFragments) as! NSDictionary
        } catch {
            print(error)
        }
        let dataType = requestDict["type"] as! String
        switch dataType {
        case "request":
            parseRequest(peer, connection: connection, transfer: transfer, requestDict: requestDict)
        case "payload":
            parsePayload(peer, connection: connection, transfer: transfer, requestDict: requestDict)
        default:
            print("the tingler detects an invalid transfer")
        }
    }
    
    func getTrack(id: Int, libraryName: String) {
        let peer = namePeerDictionary[libraryName] as! RemotePeer
        let connection = peer.connect()
        connection.onConnect = { connection in
            self.onIncomingConnection(peer, connection: connection)
        }
        askPeerForSong(peer, connection: connection, id: id)
    }
    
    func getDataForPlaylist(item: SourceListNode) {
        let peer = self.namePeerDictionary[item.item.library!.name!] as! RemotePeer
        let connection = peer.connect()
        connection.onConnect = { connection in
            self.onIncomingConnection(peer, connection: connection)
        }
        let visibleColumns = NSUserDefaults.standardUserDefaults().objectForKey(DEFAULTS_SAVED_COLUMNS_STRING) as! NSDictionary
        let visibleColumnsArray = visibleColumns.allKeysForObject(false) as! [String]
        let id = item.item.playlist!.id! as Int
        askPeerForPlaylist(peer, connection: connection, id: id, visibleColumns: visibleColumnsArray)
    }
    
    func parsePayload(peer: RemotePeer, connection: Connection, transfer: Transfer, requestDict: NSDictionary) {
        let payloadType = requestDict["payload"] as! String
        switch payloadType {
            case "name":
                let name = requestDict["name"] as! String
                interface.addNetworkedLibrary(name)
                let connectionDictionary = NSMutableDictionary()
                connectionDictionary["peer"] = peer
                self.namePeerDictionary[name] = peer
                self.askPeerForSourceList(peer, connection: connection)
            case "list":
                let list = requestDict["list"] as! [NSDictionary]
                let name = requestDict["name"] as! String
                interface.addSourcesForNetworkedLibrary(list, peer: name)
            case "playlist":
                let requestedID = requestDict["id"] as! Int
                let item = interface.getNetworkPlaylist(requestedID)
                let playlist = requestDict["playlist"] as! NSDictionary
                addTracksForPlaylistData(playlist, item: item!)
                print("the tingler got a playlist")
            case "track":
                guard delegate.mainWindowController?.is_streaming == true else {return}
                let trackB64 = requestDict["track"] as! String
                let trackData = NSData(base64EncodedString: trackB64, options: NSDataBase64DecodingOptions.IgnoreUnknownCharacters)
                guard trackData != nil else {return}
                let fileManager = NSFileManager.defaultManager()
                let libraryPath = NSUserDefaults.standardUserDefaults().stringForKey(DEFAULTS_LIBRARY_PATH_STRING)
                let libraryURL = NSURL(fileURLWithPath: libraryPath!)
                let trackFilePath = libraryURL.URLByAppendingPathComponent("test.mp3").path
                fileManager.createFileAtPath(trackFilePath!, contents: trackData, attributes: nil)
                delegate.mainWindowController!.playNetworkSongCallback()
                print("the tingler got a song")
        default:
            print("the tingler got an invalid payload")
        }
    }
    
    func parseRequest(peer: RemotePeer, connection: Connection, transfer: Transfer, requestDict: NSDictionary) {
        guard (requestDict["type"] as! String) == "request" else {return}
        let request = requestDict["request"] as! String
        switch request {
            case "name":
                sendPeerLibraryName(peer, connection: connection)
            case "list":
                sendPeerSourceList(peer, connection: connection)
            case "playlist":
                let playlistID = requestDict["id"] as! Int
                let visibleColumnsArray = requestDict["fields"] as! [String]
                sendPeerPlaylistInfo(peer, connection: connection, playlistID: playlistID, visibleColumns: visibleColumnsArray)
            case "track":
                let id = requestDict["id"] as! Int
                sendPeerTrack(peer, connection: connection, trackID: id)
        default:
            print("the tingler detects an invalid request")
        }
        
    }
    
    func sendPeerPlaylistInfo(peer: RemotePeer, connection: Connection, playlistID: Int, visibleColumns: [String]) {
        let playlist = metadataDelegate.getPlaylist(playlistID, fields: visibleColumns)
        let playlistPayloadDictionary = NSMutableDictionary()
        playlistPayloadDictionary["type"] = "payload"
        playlistPayloadDictionary["payload"] = "playlist"
        playlistPayloadDictionary["library"] = NSUserDefaults.standardUserDefaults().stringForKey(DEFAULTS_LIBRARY_NAME_STRING)
        playlistPayloadDictionary["id"] = playlistID
        playlistPayloadDictionary["playlist"] = playlist
        var serializedDict: NSData!
        do {
            serializedDict = try NSJSONSerialization.dataWithJSONObject(playlistPayloadDictionary, options: NSJSONWritingOptions.PrettyPrinted)
        } catch {
            print(error)
        }
        if !connection.isConnected {
            onIncomingConnection(peer, connection: connection)
        }
        connection.send(serializedDict)
    }
    
    func sendPeerTrack(peer: RemotePeer, connection: Connection, trackID: Int) {
        let trackData = metadataDelegate.getSong(trackID)
        let trackPayloadDictionary = NSMutableDictionary()
        trackPayloadDictionary["type"] = "payload"
        trackPayloadDictionary["payload"] = "track"
        trackPayloadDictionary["track"] = trackData?.base64EncodedStringWithOptions(NSDataBase64EncodingOptions.Encoding64CharacterLineLength)
        var serializedDict: NSData!
        do {
            serializedDict = try NSJSONSerialization.dataWithJSONObject(trackPayloadDictionary, options: NSJSONWritingOptions.PrettyPrinted)
        } catch {
            print(error)
        }
        if !connection.isConnected {
            onIncomingConnection(peer, connection: connection)
        }
        connection.send(serializedDict)
    }
    
    func sendPeerLibraryName(peer: RemotePeer, connection: Connection) {
        let libraryName = NSUserDefaults.standardUserDefaults().stringForKey("libraryName")
        let libraryNameDictionary = NSMutableDictionary()
        libraryNameDictionary["type"] = "payload"
        libraryNameDictionary["payload"] = "name"
        libraryNameDictionary["name"] = libraryName
        var serializedDict: NSData!
        do {
            serializedDict = try NSJSONSerialization.dataWithJSONObject(libraryNameDictionary, options: NSJSONWritingOptions.PrettyPrinted)
        } catch {
            print(error)
        }
        if !connection.isConnected {
            onIncomingConnection(peer, connection: connection)
        }
        connection.send(serializedDict)
    }
    
    func sendPeerSourceList(peer: RemotePeer, connection: Connection) {
        let sourceList = metadataDelegate.getSourceList()
        let sourceListPayloadDictionary = NSMutableDictionary()
        sourceListPayloadDictionary["name"] = NSUserDefaults.standardUserDefaults().stringForKey("libraryName")
        sourceListPayloadDictionary["type"] = "payload"
        sourceListPayloadDictionary["payload"] = "list"
        sourceListPayloadDictionary["list"] = sourceList
        var serializedDict: NSData!
        do {
            serializedDict = try NSJSONSerialization.dataWithJSONObject(sourceListPayloadDictionary, options: NSJSONWritingOptions.PrettyPrinted)
        } catch {
            print(error)
        }
        if !connection.isConnected {
            onIncomingConnection(peer, connection: connection)
        }
        connection.send(serializedDict)
    }
    
    func askPeerForLibraryName(peer: RemotePeer, connection: Connection) {
        let requestDictionary = NSMutableDictionary()
        requestDictionary["type"] = "request"
        requestDictionary["request"] = "name"
        var data: NSData!
        do {
            data = try NSJSONSerialization.dataWithJSONObject(requestDictionary, options: NSJSONWritingOptions.PrettyPrinted)
            if !connection.isConnected {
                onIncomingConnection(peer, connection: connection)
            }
            connection.send(data: data)
        } catch {
            print("error asking for library name: \(error)")
        }
    }
    
    func askPeerForSourceList(peer: RemotePeer, connection: Connection) {
        let requestDictionary = NSMutableDictionary()
        requestDictionary["type"] = "request"
        requestDictionary["request"] = "list"
        var data: NSData!
        do {
            data = try NSJSONSerialization.dataWithJSONObject(requestDictionary, options: NSJSONWritingOptions.PrettyPrinted)
            if !connection.isConnected {
                onIncomingConnection(peer, connection: connection)
            }
            connection.send(data: data)
        } catch {
            print("error asking for source list: \(error)")
        }
    }
    
    func askPeerForPlaylist(peer: RemotePeer, connection: Connection, id: Int, visibleColumns: [String]) {
        let requestDictionary = NSMutableDictionary()
        requestDictionary["type"] = "request"
        requestDictionary["request"] = "playlist"
        requestDictionary["fields"] = visibleColumns
        requestDictionary["id"] = id
        var data: NSData!
        do {
            data = try NSJSONSerialization.dataWithJSONObject(requestDictionary, options: NSJSONWritingOptions.PrettyPrinted)
            if !connection.isConnected {
                onIncomingConnection(peer, connection: connection)
            }
            connection.send(data: data)
        } catch {
            print("error asking for playlist: \(error)")
        }
    }
    
    func askPeerForSong(peer: RemotePeer, connection: Connection, id: Int) {
        let requestDictionary = NSMutableDictionary()
        requestDictionary["type"] = "request"
        requestDictionary["request"] = "track"
        requestDictionary["id"] = id
        var data: NSData!
        do {
            data = try NSJSONSerialization.dataWithJSONObject(requestDictionary, options: NSJSONWritingOptions.PrettyPrinted)
            if !connection.isConnected {
                onIncomingConnection(peer, connection: connection)
            }
            connection.send(data: data)
        } catch {
            print("error asking for song: \(error)")
        }
    }
    
    func addTracksForPlaylistData(playlistDictionary: NSDictionary, item: SourceListItem) {
        //get tracks
        let tracks = playlistDictionary["playlist"] as! [NSDictionary]
        let addedArtists = NSMutableDictionary()
        let addedAlbums = NSMutableDictionary()
        let addedComposers = NSMutableDictionary()
        let addedGenres = NSMutableDictionary()
        let addedTracks = NSMutableDictionary()
        var addedTrackViews = [TrackView]()
        let dateFormatter = NSDateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        for track in tracks {
            let newTrack = NSEntityDescription.insertNewObjectForEntityForName("Track", inManagedObjectContext: managedContext) as! Track
            let newTrackView = NSEntityDescription.insertNewObjectForEntityForName("TrackView", inManagedObjectContext: managedContext) as! TrackView
            newTrackView.is_network = true
            newTrackView.track = newTrack
            newTrack.is_network = true
            newTrack.is_playing = false
            for field in track.allKeys as! [String] {
                let trackArtist: Artist
                switch field {
                case "id":
                    let id = track["id"] as! Int
                    newTrack.id = track["id"] as? Int
                    addedTracks[id] = newTrack
                case "is_enabled":
                    newTrack.status = track["is_enabled"] as? Bool
                case "name":
                    newTrack.name = track["name"] as? String
                    newTrackView.name_order = track["name_order"] as? Int
                case "time":
                    newTrack.time = track["time"] as? NSNumber
                case "artist":
                    let artistName = track["artist"] as! String
                    let artist: Artist = {
                        if addedArtists[artistName] != nil {
                            return addedArtists[artistName] as! Artist
                        } else {
                            let artistCheck = checkIfArtistExists(artistName)
                            if artistCheck == nil {
                                let artist = NSEntityDescription.insertNewObjectForEntityForName("Artist", inManagedObjectContext: managedContext) as! Artist
                                artist.name = artistName
                                artist.is_network = true
                                addedArtists[artistName] = artist
                                return artist
                            } else {
                                return artistCheck!
                            }
                        }
                    }()
                    newTrack.artist = artist
                    newTrackView.artist_order = track["artist_order"] as? Int
                    trackArtist = artist
                case "album":
                    let albumName = track["album"] as! String
                    let album: Album = {
                        if addedAlbums[albumName] != nil {
                            return addedAlbums[albumName] as! Album
                        } else {
                            let albumCheck = checkIfAlbumExists(albumName)
                            if albumCheck == nil {
                                let album = NSEntityDescription.insertNewObjectForEntityForName("Album", inManagedObjectContext: managedContext) as! Album
                                album.name = albumName
                                album.is_network = true
                                addedAlbums[albumName] = album
                                return album
                            } else {
                                return albumCheck!
                            }
                        }
                    }()
                    newTrack.album = album
                    newTrackView.album_order = track["album_order"] as? Int
                case "date_added":
                    newTrack.date_added = dateFormatter.dateFromString(track["date_added"] as! String)
                    newTrackView.date_added_order = track["date_added_order"] as? Int
                case "date_modified":
                    newTrack.date_modified = dateFormatter.dateFromString(track["date_modified"] as! String)
                case "date_released":
                    newTrack.album?.release_date = dateFormatter.dateFromString(track["date_released"] as! String)
                    newTrackView.release_date_order = track["release_date_order"] as? Int
                case "comments":
                    newTrack.comments = track["comments"] as? String
                case "composer":
                    let composerName = track["composer"] as! String
                    let composer: Composer = {
                        if addedComposers[composerName] != nil {
                            return addedComposers[composerName] as! Composer
                        } else {
                            let composerCheck = checkIfComposerExists(composerName)
                            if composerCheck == nil {
                                let composer = NSEntityDescription.insertNewObjectForEntityForName("Composer", inManagedObjectContext: managedContext) as! Composer
                                composer.name = composerName
                                composer.is_network = true
                                addedComposers[composerName] = composer
                                return composer
                            } else {
                                return composerCheck!
                            }
                        }
                    }()
                    newTrack.composer = composer
                case "disc_number":
                    newTrack.disc_number = track["disc_number"] as? Int
                case "equalizer_preset":
                    newTrack.equalizer_preset = track["equalizer_preset"] as? String
                case "genre":
                    let genreName = track["genre"] as! String
                    let genre: Genre = {
                        if addedComposers[genreName] != nil {
                            return addedGenres[genreName] as! Genre
                        } else {
                            let genreCheck = checkIfGenreExists(genreName)
                            if genreCheck == nil {
                                let genre = NSEntityDescription.insertNewObjectForEntityForName("Genre", inManagedObjectContext: managedContext) as! Genre
                                genre.name = genreName
                                genre.is_network = true
                                addedGenres[genreName] = genre
                                return genre
                            } else {
                                return genreCheck!
                            }
                        }
                    }()
                    newTrack.genre = genre
                    newTrackView.genre_order = track["genre_order"] as? Int
                case "kind":
                    newTrack.file_kind = track["kind"] as? String
                    newTrackView.kind_order = track["kind_order"] as? Int
                case "date_last_played":
                    newTrack.date_last_played = dateFormatter.dateFromString(track["date_last_played"] as! String)
                case "date_last_skipped":
                    newTrack.date_last_skipped = dateFormatter.dateFromString(track["date_last_skipped"] as! String)
                case "movement_name":
                    newTrack.movement_name = track["movement_name"] as? String
                case "movement_number":
                    newTrack.movement_number = track["movement_number"] as? Int
                case "play_count":
                    newTrack.play_count = track["play_count"] as? Int
                case "rating":
                    newTrack.rating = track["rating"] as? Int
                case "bit_rate":
                    newTrack.bit_rate = track["bit_rate"] as? Int
                case "sample_rate":
                    newTrack.sample_rate = track["sample_Rate"] as? Int
                case "size":
                    newTrack.size = track["size"] as? Int
                case "skip_count":
                    newTrack.skip_count = track["skip_count"] as? Int
                case "sort_album":
                    newTrack.sort_album = track["sort_album"] as? String
                case "sort_album_artist":
                    newTrack.sort_album_artist = track["sort_album_artist"] as? String
                    newTrackView.album_artist_order = track["album_artist_order"] as? Int
                case "sort_artist":
                    newTrack.sort_artist = track["sort_artist"] as? String
                case "sort_composer":
                    newTrack.sort_composer = track["sort_composer"] as? String
                case "sort_name":
                    newTrack.sort_name = track["sort_name"] as? String
                case "track_number":
                    newTrack.track_num = track["track_number"] as? Int
                case "album_artist":
                    let artistName = track["album_artist"] as! String
                    let artist: Artist = {
                        if addedArtists[artistName] != nil {
                            return addedArtists[artistName] as! Artist
                        } else {
                            let artistCheck = checkIfArtistExists(artistName)
                            if artistCheck == nil {
                                let artist = NSEntityDescription.insertNewObjectForEntityForName("Artist", inManagedObjectContext: managedContext) as! Artist
                                artist.name = artistName
                                artist.is_network = true
                                addedArtists[artistName] = artist
                                return artist
                            } else {
                                return artistCheck!
                            }
                        }
                    }()
                    newTrack.album?.album_artist = artist
                default:
                    break
                }
            }
            addedTrackViews.append(newTrackView)
        }
        let track_id_list = addedTrackViews.map({return Int($0.track!.id!)})
        item.playlist?.track_id_list = track_id_list
        delegate.mainWindowController!.doneAddingNetworkPlaylistCallback(item)
        
    }
}