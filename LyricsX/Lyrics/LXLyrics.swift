//
//  LXLyrics.swift
//  LyricsX
//
//  Created by 邓翔 on 2017/2/5.
//  Copyright © 2017年 ddddxxx. All rights reserved.
//

import Foundation

struct LXLyricsLine {
    
    var sentence: String
    var translation: String?
    var position: Double
    var enabled: Bool
    
    var timeTag: String {
        let min = Int(position / 60)
        let sec = position - Double(min * 60)
        return String(format: "%02d:%06.3f", min, sec)
    }
    
    init(sentence: String, translation: String? = nil, position: Double) {
        self.sentence = sentence
        self.translation = translation
        self.position = position
        enabled = true
    }
    
    init?(sentence: String, translation: String? = nil, timeTag: String) {
        var tagContent = timeTag
        tagContent.remove(at: tagContent.startIndex)
        tagContent.remove(at: tagContent.index(before: tagContent.endIndex))
        let components = tagContent.components(separatedBy: ":")
        if components.count == 2,
            let min = Double(components[0]),
            let sec = Double(components[1]) {
            let position = sec + min * 60
            self.init(sentence: sentence, translation: translation, position: position)
        } else {
            return nil
        }
    }
    
}

extension LXLyricsLine: Equatable, Hashable {
    
    var hashValue: Int {
        return sentence.hashValue ^ position.hashValue ^ (translation?.hash ?? 0)
    }
    
    static func ==(lhs: LXLyricsLine, rhs: LXLyricsLine) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
    
}

// MARK: -

struct LXLyrics {
    
    var lyrics: [LXLyricsLine]
    var idTags: [IDTagKey: String]
    var metadata: [MetadataKey: String]
    
    var offset: Int {
        get {
            return idTags[.offset].flatMap() { Int($0) } ?? 0
        }
        set {
            idTags[.offset] = "\(newValue)"
        }
    }
    
    var timeDelay: Double {
        get {
            return Double(offset) / 1000
        }
        set {
            offset = Int(newValue * 1000)
        }
    }
    
    static let regexForIDTag = try! NSRegularExpression(pattern: "\\[[^\\]]+:[^\\]]+\\]")
    static let regexForTimeTag = try! NSRegularExpression(pattern: "\\[\\d+:\\d+.\\d+\\]|\\[\\d+:\\d+\\]")
    
    init?(_ lrcContents: String) {
        lyrics = []
        idTags = [:]
        metadata = [:]
        
        let lyricsLines = lrcContents.components(separatedBy: .newlines)
        for line in lyricsLines {
            let timeTagsMatched = LXLyrics.regexForTimeTag.matches(in: line, options: [], range: NSMakeRange(0, line.characters.count))
            if timeTagsMatched.count > 0 {
                let index: Int = timeTagsMatched.last!.range.location + timeTagsMatched.last!.range.length
                let lyricsSentence: String = line.substring(from: line.characters.index(line.startIndex, offsetBy: index))
                let components = lyricsSentence.components(separatedBy: "【")
                let lyricsStr: String
                let translation: String?
                if components.count == 2, components[1].characters.last == "】" {
                    lyricsStr = components[0]
                    translation = String(components[1].characters.dropLast())
                } else {
                    lyricsStr = lyricsSentence
                    translation = nil
                }
                let lyrics = timeTagsMatched.flatMap() { result -> LXLyricsLine? in
                    let timeTagStr = (line as NSString).substring(with: result.range) as String
                    return LXLyricsLine(sentence: lyricsStr, translation: translation, timeTag: timeTagStr)
                }
                self.lyrics += lyrics
            } else {
                let idTagsMatched = LXLyrics.regexForIDTag.matches(in: line, range: NSMakeRange(0, line.characters.count))
                guard idTagsMatched.count > 0 else {
                    continue
                }
                for result in idTagsMatched {
                    var tagStr = ((line as NSString).substring(with: result.range)) as String
                    tagStr.remove(at: tagStr.startIndex)
                    tagStr.remove(at: tagStr.index(before: tagStr.endIndex))
                    let components = tagStr.components(separatedBy: ":")
                    if components.count == 2 {
                        let key = IDTagKey(components[0])
                        let value = components[1]
                        idTags[key] = value
                    }
                }
            }
        }
        
        if lyrics.count == 0 {
            return nil
        }
        
        lyrics.sort() { $0.position < $1.position }
    }
    
    init?(metadata: [MetadataKey: String]) {
        guard let lrcURLStr = metadata[.lyricsURL],
            let lrcURL = URL(string: lrcURLStr),
            let lrcContent = try? String(contentsOf: lrcURL) else {
            return nil
        }
        
        self.init(lrcContent)
        self.metadata = metadata
    }
    
    subscript(_ position: Double) -> (current:LXLyricsLine?, next:LXLyricsLine?) {
        let lyrics = self.lyrics.filter() { $0.enabled }
        guard let index = lyrics.index(where: { $0.position - timeDelay > position }) else {
            return (lyrics.last, nil)
        }
        let previous = lyrics.index(index, offsetBy: -1, limitedBy: lyrics.startIndex).flatMap() { lyrics[$0] }
        return (previous, lyrics[index])
    }
    
}

extension LXLyrics {
    
    mutating func filtrate(using regex: NSRegularExpression) {
        for (index, lyric) in lyrics.enumerated() {
            let sentence = lyric.sentence.replacingOccurrences(of: " ", with: "")
            let numberOfMatches = regex.numberOfMatches(in: sentence, options: [], range: NSMakeRange(0, sentence.characters.count))
            if numberOfMatches > 0 {
                lyrics[index].enabled = false
                continue
            }
        }
    }
    
    mutating func smartFiltrate() {
        for (index, lyric) in lyrics.enumerated() {
            let sentence = lyric.sentence
            if let idTagTitle = idTags[.title],
                let idTagArtist = idTags[.artist],
                sentence.contains(idTagTitle),
                sentence.contains(idTagArtist) {
                lyrics[index].enabled = false
            } else if let iTunesTitle = metadata[.searchTitle],
                let iTunesArtist = metadata[.searchArtist],
                sentence.contains(iTunesTitle),
                sentence.contains(iTunesArtist) {
                lyrics[index].enabled = false
            }
        }
    }
    
}

extension LXLyrics {
    
    var grade: Int {
        var grade = 0
        if idTags[.artist] == metadata[.searchArtist] {
            grade += 1 << 10
        }
        if idTags[.title] == metadata[.searchTitle] {
            grade += 1 << 8
        }
        if metadata[.includeTranslation] == "true" {
            grade += 1 << 2
        }
        return grade
    }
    
}

extension LXLyrics {
    
    struct IDTagKey: RawRepresentable, Hashable {
        
        var rawValue: String
        
        init(_ rawValue: String) {
            self.rawValue = rawValue
        }
        
        init(rawValue: String) {
            self.rawValue = rawValue
        }
        
        var hashValue: Int {
            return rawValue.hash
        }
        
        static let title: IDTagKey = .init("ti")
        
        static let album: IDTagKey = .init("al")
        
        static let artist: IDTagKey = .init("ar")
        
        static let author: IDTagKey = .init("au")
        
        static let lrcBy: IDTagKey = .init("by")
        
        static let offset: IDTagKey = .init("offset")
        
    }
    
    enum MetadataKey {
        
        case source
        
        case lyricsURL
        
        case searchTitle
        
        case searchArtist
        
        case artworkURL
        
        case includeTranslation
        
    }
    
}

extension LXLyrics {
    
    mutating func merge(translation: LXLyrics) {
        var index = lyrics.startIndex
        var transIndex = translation.lyrics.startIndex
        while index < lyrics.endIndex, transIndex < translation.lyrics.endIndex {
            if lyrics[index].position - translation.lyrics[transIndex].position < 0.1 {
                let transStr = translation.lyrics[transIndex].sentence
                if transStr.replacingOccurrences(of: " ", with: "").characters.count > 0 {
                    lyrics[index].translation = transStr
                }
                lyrics.formIndex(after: &index)
                translation.lyrics.formIndex(after: &transIndex)
            } else if lyrics[index].position > translation.lyrics[transIndex].position {
                translation.lyrics.formIndex(after: &transIndex)
            } else {
                lyrics.formIndex(after: &index)
            }
        }
    }
    
}

// MARK: - Debug Print Support

extension LXLyrics.IDTagKey: CustomStringConvertible {
    
    public var description: String {
        return rawValue
    }
    
}

extension LXLyricsLine: CustomStringConvertible {
    
    public var description: String {
        var description = "[\(timeTag)]" + sentence
        if let trans = translation {
            description += "【\(trans)】"
        }
        return description
    }
    
}

extension LXLyrics: CustomStringConvertible {
    
    public var description: String {
        let tag = idTags.map({"[\($0.key):\($0.value)]"}).joined(separator: "\n")
        let lrc = lyrics.map({$0.description}).joined(separator: "\n")
        return tag + "\n" + lrc
    }
    
}
