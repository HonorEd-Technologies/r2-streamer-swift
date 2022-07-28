//
//  Copyright 2022 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import R2Shared
import Fuzi
import CryptoKit

final class EPUBTrimmer {
    private let trimmedToc: [Link]
    private let toc: [Link]

    init(trimmedToc: [Link], toc: [Link]) {
        self.trimmedToc = trimmedToc
        self.toc = toc
    }
    
    func trim(resource: Resource) -> Resource {
        guard resource.link.mediaType.isHTML else {
            return resource
        }
        return resource.mapAsString { content in
            var content = content
            
                // RTL dir attributes injection
            let indexInChapter = self.toc.filter({ $0.href.contains(resource.link.href) })
            for i in 0..<indexInChapter.count {
                var nextLink: Link?
                if i < indexInChapter.count - 1 {
                    nextLink = indexInChapter[i + 1]
                }
                trimContent(content: &content, inChapter: indexInChapter[i], nextLink: nextLink, given: self.trimmedToc)
            }
            return content
        }
    }
}

public func trimContent(content: inout String, inChapter chapter: Link, nextLink: Link?, given trimmedToc: [Link]) {
    if containsLink(arr: trimmedToc, element: chapter) {
        return
    } else {
        if let startIndex = startIndexOfLink(in: content, link: chapter), let indexOfEnclosingBeforeTag = indexOf(content, at: startIndex, after: "<") {
            if let nextLink = nextLink {
                if let endIndex = startIndexOfLink(in: content, link: nextLink), let indexOfEnclosingAfterTag = indexOf(content, at: endIndex, after: "<") {
                    content.removeSubrange(content.index(content.startIndex, offsetBy: indexOfEnclosingBeforeTag)..<content.index(content.startIndex, offsetBy: indexOfEnclosingAfterTag))
                }
            } else {
                var trimmedContent = content
                
                trimmedContent.removeSubrange(trimmedContent.index(trimmedContent.startIndex, offsetBy: indexOfEnclosingBeforeTag)..<trimmedContent.endIndex)
                let unfulfilledTags = unfullfilledTagsInOrder(trimmedContent, startIndex: nil, endIndex: nil)
                populateEndOfEPUBChapter(content: content, trimmedContent: &trimmedContent, tags: unfulfilledTags)
                content = trimmedContent
            }
        }
    }
}

public func populateEndOfEPUBChapter(content: String, trimmedContent: inout String, tags: [String]) {
    var endString = ""
    var numOccurences: [String: Int] = [:]
    for i in 0..<tags.count {
        let tag = tags[i]
        findEndTagFromEndString(within: content, tag: tag, endString: &endString, position: numOccurences[tag] ?? 0)
        numOccurences[tag] = (numOccurences[tag] ?? 0) + 1
    }
    trimmedContent += endString
}

public func findEndTagFromEndString(within content: String, tag: String, endString: inout String, position: Int) {
    let endTag = #"<\/(\s)*"# + tag + #"(\s)*>"#
    let matches = matches(for: endTag, in: content)
    guard matches.count - 1 - position >= 0 && position >= 0 else { return }
    let match = matches[matches.count - position - 1]
    endString = String(content[content.index(content.startIndex, offsetBy: match.lowerBound)..<content.endIndex])
}

func matches(for regex: String, in text: String) -> [NSRange] {

    do {
        let regex = try NSRegularExpression(pattern: regex)
        let results = regex.matches(in: text,
                                    range: NSRange(text.startIndex..., in: text))
        return results.map({ $0.range })
    } catch let error {
        print("invalid regex: \(error.localizedDescription)")
        return []
    }
}

public func containsLink(arr: [Link], element: Link) -> Bool {
    return arr.compactMap(\.title).filter({
        if let title = element.title {
            return $0.contains(title) || title.contains($0)
        }
        return false
    }).count != 0
}

public func indexOf(_ content: String, at index: Int, after: Character) -> Int? {
    var newIndex = index
    while newIndex > 0 {
        if content[content.index(content.startIndex, offsetBy: newIndex)] == after {
            return newIndex
        }
        newIndex -= 1
    }
    return nil
}

public func startIndexOfLink(in content: String, link: Link) -> Int? {
    guard let title = link.title else { return nil }
    if let id = link.href.split(separator: "#").last, let index = content.range(of: "id=\"\(id)\"")?.lowerBound {
        return content.distance(from: content.startIndex, to: index)
    } else if let index = content.range(of: title)?.lowerBound {
        return content.distance(from: content.startIndex, to: index)
    } else if let index = content.range(of: title.dropLast(1))?.lowerBound {
        return content.distance(from: content.startIndex, to: index)
    } else {
        return nil
    }
}


public func unfullfilledTagsInOrder(_ content: String, startIndex: String.Index?, endIndex: String.Index?) -> [String] {
    var tagArray: [String] = []
    var trimmedContent = String(content[(startIndex ?? content.startIndex)..<(endIndex ?? content.endIndex)])
    guard var startTagIndex = trimmedContent.firstIndex(of: "<") else { return tagArray }
    var endTagIndex = startTagIndex
    while endTagIndex < trimmedContent.endIndex {
        let char = trimmedContent[endTagIndex]
        if char == ">" {
            if trimmedContent[trimmedContent.index(startTagIndex, offsetBy: 1)] == "/" {
                if let tag = tagFromContent(trimmedContent, startingAt: startTagIndex) {
                    tagArray.popLast()
                }
            } else if trimmedContent[trimmedContent.index(endTagIndex, offsetBy: -1)] != "/" {
                if let tag = tagFromContent(trimmedContent, startingAt: startTagIndex) {
                    tagArray.append(tag)
                }
            }
            trimmedContent = String(trimmedContent[trimmedContent.index(endTagIndex, offsetBy: 1)..<(endIndex ?? trimmedContent.endIndex)])
            if let nextStartTag = trimmedContent.firstIndex(of: "<") {
                startTagIndex = nextStartTag
                endTagIndex = startTagIndex
            } else {
                break
            }
        } else {
            endTagIndex = content.index(endTagIndex, offsetBy: 1)
        }
    }
    return tagArray
}

public func tagFromContent(_ content: String, startingAt index: String.Index) -> String? {
    guard content[index] == "<" else { return nil }
    var nextIndex = content.index(index, offsetBy: 1)
    var prependingWhiteText = true
    guard content[nextIndex] != "!", content[nextIndex] != "?" else { return nil }
    if content[nextIndex] == "/" {
        nextIndex = content.index(nextIndex, offsetBy: 1)
    }
    var char = content[nextIndex]
    var string = ""
    while char != ">" && char != "/" || (char == " " && prependingWhiteText) {
        if char == " " {
            nextIndex = content.index(nextIndex, offsetBy: 1)
            char = content[nextIndex]
            continue
        }
        prependingWhiteText = false
        string.append(char)
        nextIndex = content.index(nextIndex, offsetBy: 1)
        char = content[nextIndex]
    }
    
    return string
}
