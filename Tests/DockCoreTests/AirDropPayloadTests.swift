import Foundation
import Testing

@testable import DockCore

@Suite("AirDrop payload")
struct AirDropPayloadTests {
    private let report = URL(fileURLWithPath: "/Users/me/Documents/Report.pdf")
    private let photos = URL(fileURLWithPath: "/Users/me/Pictures/Trip", isDirectory: true)
    private let site = URL(string: "https://example.com/page?x=1")!

    // MARK: Files and links

    @Test func filesAndLinksAreKeptInDragOrderWithFilesFirst() {
        let payload = AirDropPayload(urls: [site, report, photos])
        #expect(payload.files.map(\.normalizedPath) == ["/Users/me/Documents/Report.pdf", "/Users/me/Pictures/Trip"])
        #expect(payload.links == [site])
        #expect(payload.items.dropLast().map(\.normalizedPath) == payload.files.map(\.normalizedPath))
        #expect(payload.items.last == site)
        #expect(payload.count == 3)
        #expect(!payload.isEmpty)
    }

    @Test func foldersAreSentLikeFiles() {
        let payload = AirDropPayload(urls: [photos])
        #expect(payload.files.map(\.normalizedPath) == ["/Users/me/Pictures/Trip"])
    }

    @Test func otherSchemesAreLeftOut() {
        let urls = [
            URL(string: "mailto:someone@example.com")!,
            URL(string: "data:text/plain,hello")!,
            URL(string: "ftp://example.com/file.zip")!,
            URL(string: "x-apple.systempreferences:com.apple.preference.security")!,
            URL(string: "tel:+15551234567")!,
        ]
        #expect(AirDropPayload(urls: urls).isEmpty)
    }

    @Test func linksNeedAHost() {
        #expect(!AirDropPayload.isLink(URL(string: "https:")!))
        #expect(!AirDropPayload.isLink(URL(string: "http:///path")!))
        #expect(AirDropPayload.isLink(URL(string: "HTTPS://Example.COM")!))
        #expect(AirDropPayload.isLink(URL(string: "http://localhost:8080/")!))
    }

    @Test func emptyFileURLIsIgnored() {
        #expect(AirDropPayload(urls: [URL(fileURLWithPath: "/")]).isEmpty)
    }

    // MARK: Duplicates

    @Test func sameFileWrittenTwoWaysCountsOnce() {
        let withSlash = URL(fileURLWithPath: "/Users/me/Pictures/Trip/")
        let viaDot = URL(fileURLWithPath: "/Users/me/Pictures/./Trip")
        let payload = AirDropPayload(urls: [photos, withSlash, viaDot])
        #expect(payload.files.count == 1)
        #expect(payload.files.first?.normalizedPath == "/Users/me/Pictures/Trip")
    }

    @Test func sameLinkCountsOnce() {
        let payload = AirDropPayload(urls: [site, URL(string: "https://example.com/page?x=1")!])
        #expect(payload.links == [site])
    }

    @Test func textRepeatingADraggedLinkIsNotASecondLink() {
        // A browser puts the address on the pasteboard as a URL and as text.
        let payload = AirDropPayload(urls: [site], texts: [site.absoluteString])
        #expect(payload.links == [site])
        #expect(payload.count == 1)
    }

    // MARK: Text

    @Test func textThatIsOneAddressIsALink() {
        let payload = AirDropPayload(urls: [], texts: ["  https://example.com/a \n"])
        #expect(payload.links == [URL(string: "https://example.com/a")!])
    }

    @Test func textThatIsNotJustAnAddressIsNotALink() {
        let texts = [
            "hello",
            "see https://example.com for more",
            "https://example.com and https://example.org",
            "",
            "   ",
            "file:///Users/me/Documents/Report.pdf",
            "mailto:someone@example.com",
        ]
        #expect(AirDropPayload(urls: [], texts: texts).isEmpty)
        for text in texts {
            #expect(AirDropPayload.link(in: text) == nil, "\(text.debugDescription) should not be a link")
        }
    }

    // MARK: Adding

    @Test func addingBuildsThePayloadUp() {
        var payload = AirDropPayload()
        #expect(payload.isEmpty)
        payload.add(report)
        payload.add(site)
        payload.add(report)
        #expect(payload.items == [report, site])
    }

    // MARK: Summary

    @Test func summaryCountsFilesAndLinks() {
        #expect(AirDropPayload().summary == "Nothing to send")
        #expect(AirDropPayload(urls: [report]).summary == "1 file")
        #expect(AirDropPayload(urls: [report, photos]).summary == "2 files")
        #expect(AirDropPayload(urls: [site]).summary == "1 link")
        #expect(
            AirDropPayload(urls: [report, photos, site, URL(string: "https://example.org")!]).summary
                == "2 files and 2 links")
        #expect(AirDropPayload(urls: [report, site]).summary == "1 file and 1 link")
    }
}
