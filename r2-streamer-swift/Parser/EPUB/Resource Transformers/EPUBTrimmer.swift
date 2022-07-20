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
                let divString = "</div>"
                if let contentDivIndex = content.range(of: contentDivString)?.lowerBound {
                    let indexOfDiv = content.index(contentDivIndex, offsetBy: -divString.count)
                    content.removeSubrange(content.index(content.startIndex, offsetBy: indexOfEnclosingBeforeTag)..<indexOfDiv)
                }
            }
        }
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

public func indexOf(_ content: String, at index: Int, before: Character) -> Int? {
    var newIndex = index
    while newIndex < content.count {
        if content[content.index(content.startIndex, offsetBy: newIndex)] == before {
            return newIndex
        }
        newIndex += 1
    }
    return nil
}

public func startIndexOfLink(in content: String, link: Link) -> Int? {
    guard let title = link.title else { return nil }
    if let id = link.href.split(separator: "#").last, let index = content.range(of: id)?.lowerBound {
        return content.distance(from: content.startIndex, to: index)
    } else if let index = content.range(of: title)?.lowerBound {
        return content.distance(from: content.startIndex, to: index)
    } else if let index = content.range(of: title.dropLast(1))?.lowerBound {
        return content.distance(from: content.startIndex, to: index)
    } else {
        return nil
    }
}

private let contentDivString = "<!--#content-->"
