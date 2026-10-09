import Foundation
import Testing

@testable import DockCore

@Suite("Sticky note colors")
struct StickyNoteColorTests {
    @Test func storageValuesAreTheRawValuesInOrder() {
        #expect(
            StickyNoteColor.storageValues == [
                "yellow", "orange", "pink", "green", "blue", "purple", "white", "black", "translucent",
            ])
        for value in StickyNoteColor.storageValues {
            let isLowercase = value.allSatisfy(\.isLowercase)
            #expect(isLowercase, "\(value) is stored in dock.json and should stay lowercase")
        }
    }

    @Test func unknownValuesFallBackToYellow() {
        #expect(StickyNoteColor(storageValue: "pink") == .pink)
        #expect(StickyNoteColor(storageValue: "Pink") == .yellow)
        #expect(StickyNoteColor(storageValue: "chartreuse") == .yellow)
        #expect(StickyNoteColor(storageValue: "") == .yellow)
        #expect(StickyNoteColor.default == .yellow)
    }

    @Test func everyColorHasAName() {
        let names = StickyNoteColor.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
        let capitalized = names.allSatisfy { !$0.isEmpty && $0.first?.isUppercase == true }
        #expect(capitalized)
    }

    @Test func onlyTheTranslucentNoteHasNoFill() {
        for color in StickyNoteColor.allCases {
            #expect((color.fill == nil) == (color == .translucent), "\(color)")
        }
    }

    @Test func fillsAreInRange() {
        for color in StickyNoteColor.allCases {
            guard let fill = color.fill else { continue }
            for component in [fill.red, fill.green, fill.blue] {
                #expect((0 ... 1).contains(component), "\(color)")
            }
        }
    }

    @Test func inkContrastsWithThePaper() {
        #expect(StickyNoteColor.black.ink == .light)
        #expect(StickyNoteColor.translucent.ink == .adaptive)
        for color in StickyNoteColor.allCases where color != .black && color != .translucent {
            #expect(color.ink == .dark, "\(color)")
        }
    }
}

@Suite("Sticky note text")
struct StickyNoteTextTests {
    // MARK: Storage

    @Test func storageNormalizesLineEndings() {
        #expect(StickyNoteText.storageValue(for: "a\r\nb\rc\nd") == "a\nb\nc\nd")
    }

    @Test func storageKeepsWhitespaceAndBlankLines() {
        #expect(StickyNoteText.storageValue(for: "  indented\n\n\ntrailing  \n") == "  indented\n\n\ntrailing  \n")
        #expect(StickyNoteText.storageValue(for: "") == "")
    }

    @Test func storageCapsTheLength() {
        let long = String(repeating: "x", count: StickyNoteText.maximumLength + 50)
        #expect(StickyNoteText.storageValue(for: long).count == StickyNoteText.maximumLength)
        let exact = String(repeating: "y", count: StickyNoteText.maximumLength)
        #expect(StickyNoteText.storageValue(for: exact) == exact)
    }

    @Test func storageCountsCharactersNotBytes() {
        let emoji = String(repeating: "🙂", count: StickyNoteText.maximumLength + 1)
        let stored = StickyNoteText.storageValue(for: emoji)
        #expect(stored.count == StickyNoteText.maximumLength)
        let onlySmileys = stored.allSatisfy { $0 == "🙂" }
        #expect(onlySmileys)
    }

    // MARK: Blank

    @Test func blankMeansOnlyWhitespace() {
        #expect(StickyNoteText.isBlank(""))
        #expect(StickyNoteText.isBlank(" \n\t\n"))
        #expect(!StickyNoteText.isBlank(" . "))
    }

    // MARK: Preview

    @Test func previewIsTheTrimmedNonBlankLines() {
        #expect(StickyNoteText.preview(of: "  Buy milk  \n\n  Call Sam\n") == "Buy milk\nCall Sam")
    }

    @Test func previewOfABlankNoteIsEmpty() {
        #expect(StickyNoteText.preview(of: "") == "")
        #expect(StickyNoteText.preview(of: "\n \n") == "")
    }

    @Test func previewStopsAfterMaxLinesWithAnEllipsis() {
        let note = "one\ntwo\nthree\nfour"
        #expect(StickyNoteText.preview(of: note, maxLines: 3) == "one\ntwo\nthree…")
        #expect(StickyNoteText.preview(of: note, maxLines: 4) == "one\ntwo\nthree\nfour")
        #expect(StickyNoteText.preview(of: note, maxLines: 1) == "one…")
    }

    @Test func blankLinesDoNotCountTowardsTheLimit() {
        #expect(StickyNoteText.preview(of: "one\n\n\ntwo\n\nthree", maxLines: 3) == "one\ntwo\nthree")
    }

    @Test func previewCutsLongTextWithAnEllipsis() {
        let note = "The quick brown fox jumps over the lazy dog"
        #expect(StickyNoteText.preview(of: note, maxLength: 19) == "The quick brown fox…")
        #expect(StickyNoteText.preview(of: note, maxLength: 20) == "The quick brown fox…")
        #expect(StickyNoteText.preview(of: note, maxLength: 100) == note)
    }

    @Test func aCutAtALineBreakLeavesNoDanglingNewline() {
        #expect(StickyNoteText.preview(of: "abc\ndef", maxLength: 4) == "abc…")
    }

    @Test func previewDefaultsFitATile() {
        let note = (1 ... 10).map { "line \($0)" }.joined(separator: "\n")
        #expect(StickyNoteText.preview(of: note) == "line 1\nline 2\nline 3…")
        let paragraph = String(repeating: "word ", count: 100)
        let preview = StickyNoteText.preview(of: paragraph)
        #expect(preview.hasSuffix("…"))
        #expect(preview.count <= StickyNoteText.previewLength + 1)
    }

    @Test func zeroLimitsGiveNothing() {
        #expect(StickyNoteText.preview(of: "note", maxLines: 0) == "")
        #expect(StickyNoteText.preview(of: "note", maxLength: 0) == "")
    }

    // MARK: First line and counts

    @Test func firstLineSkipsBlankLines() {
        #expect(StickyNoteText.firstLine(of: "\n\n  Title \nbody") == "Title")
        #expect(StickyNoteText.firstLine(of: "   ") == "")
    }

    @Test func wordCountSplitsOnAnyWhitespace() {
        #expect(StickyNoteText.wordCount("") == 0)
        #expect(StickyNoteText.wordCount("one") == 1)
        #expect(StickyNoteText.wordCount("  one \n two\tthree  ") == 3)
    }

    @Test func countSummaryReadsNaturally() {
        #expect(StickyNoteText.countSummary("") == "0 words")
        #expect(StickyNoteText.countSummary("hello") == "1 word")
        #expect(StickyNoteText.countSummary("hello there") == "2 words")
        let long = String(repeating: "word ", count: 30)
        #expect(StickyNoteText.countSummary(long) == "30 words · 150 characters")
        let full = String(repeating: "a", count: StickyNoteText.maximumLength)
        #expect(StickyNoteText.countSummary(full) == "1 word · \(StickyNoteText.maximumLength) characters (limit)")
    }
}
