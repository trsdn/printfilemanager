import XCTest
@testable import PrintFileManagerCore

/// The previous rule refused plain http unless the host was loopback. That blocked the setup this
/// app exists for -- a model server on the user's own network, which cannot have a certificate --
/// and decided on the user's behalf what is safe on their own machine.
///
/// Nothing here blocks anything. These tests pin that, and pin which combinations are worth a note.
final class EndpointTransportPolicyTests: XCTestCase {

    // MARK: - Nothing is ever refused

    func testAPlainHTTPLANEndpointIsAccepted() {
        // The exact endpoint that was rejected.
        let url = URL(string: "http://192.168.2.177:8080/v1/")!

        XCTAssertEqual(EndpointTransportPolicy.advice(for: url, hasAPIKey: false), .none)
        XCTAssertNil(EndpointTransportPolicy.note(for: url, hasAPIKey: false))
    }

    func testAPlainHTTPPublicEndpointIsStillAcceptedAndOnlyNoted() {
        let url = URL(string: "http://example.com/v1/")!

        XCTAssertEqual(
            EndpointTransportPolicy.advice(for: url, hasAPIKey: false),
            .plaintextRefusedByTransportSecurity(host: "example.com", carriesAPIKey: false)
        )
        // A note, not a refusal.
        XCTAssertNotNil(EndpointTransportPolicy.note(for: url, hasAPIKey: false))
    }

    func testTheNoteSaysWhatMacOSWillActuallyDo() {
        // Measured from a sandboxed build with no NSAppTransportSecurity key: plain http to a
        // dotted name that is not `.local` is refused with NSURLErrorDomain -1022, so the request
        // is never sent. "Readable in transit" described a request that does not happen, which
        // sends the user looking for a network fault instead of a scheme they can change.
        let note = EndpointTransportPolicy.note(for: URL(string: "http://models.lan/v1/")!, hasAPIKey: false)

        XCTAssertEqual(note?.contains("macOS refuses plain http"), true)
        XCTAssertEqual(note?.contains("reachable from the internet"), false)
    }

    func testAnUnqualifiedHostnameIsTreatedAsLocal() {
        // `http://modelserver:8080` is a normal way to reach a machine on a home network, and ATS
        // lets an unqualified name through -- measured as a DNS failure, not a -1022 refusal.
        // Warning about it would be a false alarm about a setup that works.
        XCTAssertTrue(EndpointTransportPolicy.isPrivate(host: "modelserver"))
        XCTAssertNil(EndpointTransportPolicy.note(for: URL(string: "http://modelserver:8080/v1/")!, hasAPIKey: true))
    }

    // MARK: - Which schemes are usable at all

    func testHTTPAndHTTPSAreTheSupportedSchemes() {
        XCTAssertTrue(EndpointTransportPolicy.isSupportedScheme("http"))
        XCTAssertTrue(EndpointTransportPolicy.isSupportedScheme("HTTPS"))
    }

    func testASchemeThatCannotCarryARequestIsNotSupported() {
        // `file:` and `ftp:` reached URLSession and failed obscurely; neither can carry a chat
        // completion, and `file:` points the endpoint at the user's own disk.
        for scheme in ["file", "ftp", "ws", "javascript", "", nil] {
            XCTAssertFalse(EndpointTransportPolicy.isSupportedScheme(scheme), scheme ?? "nil")
        }
    }

    func testTheNoteNamesTheKeyOnlyWhenThereIsOneToExpose() {
        let url = URL(string: "http://example.com/v1/")!

        XCTAssertEqual(
            EndpointTransportPolicy.note(for: url, hasAPIKey: true)?.contains("API key"), true
        )
        XCTAssertEqual(
            EndpointTransportPolicy.note(for: url, hasAPIKey: false)?.contains("API key"), false
        )
    }

    func testHTTPSIsNeverNoted() {
        for host in ["api.openai.com", "192.168.2.177", "localhost"] {
            let url = URL(string: "https://\(host)/v1/")!
            XCTAssertNil(EndpointTransportPolicy.note(for: url, hasAPIKey: true), host)
        }
    }

    // MARK: - Which hosts count as private

    func testEveryPrivateRangeIsRecognised() {
        for host in [
            "localhost", "127.0.0.1", "127.1.2.3", "::1",
            "10.0.0.1", "10.255.255.254",
            "172.16.0.1", "172.31.255.254",
            "192.168.2.177", "192.168.0.1",
            "169.254.1.1",
            "printer.local", "fe80::1", "fd00::1"
        ] {
            XCTAssertTrue(EndpointTransportPolicy.isPrivate(host: host), host)
        }
    }

    func testAddressesJustOutsideThePrivateRangesAreNotPrivate() {
        // The boundaries are where a sloppy prefix match would wrongly let a public address
        // through as "local".
        for host in [
            "172.15.0.1", "172.32.0.1",     // either side of 172.16/12
            "192.169.0.1", "192.167.0.1",   // either side of 192.168/16
            "11.0.0.1", "9.255.255.255",    // either side of 10/8
            "169.253.0.1",                  // just outside link-local
            "example.com", "notlocalhost.com", "localhost.evil.com",
            "2001:4860:4860::8888"          // public IPv6
        ] {
            XCTAssertFalse(EndpointTransportPolicy.isPrivate(host: host), host)
        }
    }

    func testSomethingThatMerelyLooksLikeAnAddressIsTreatedAsAHostname() {
        for host in ["192.168.2", "192.168.2.177.5", "192.168.2.999", "192.168.2.x", "1.2.3.04x"] {
            XCTAssertFalse(EndpointTransportPolicy.isPrivate(host: host), host)
        }
    }

    func testABracketedIPv6HostIsUnwrapped() {
        XCTAssertTrue(EndpointTransportPolicy.isPrivate(host: "[::1]"))
    }

    func testAMalformedEndpointIsNotNoted() {
        // Nothing to say about a URL with no host; it simply will not work, which the request
        // reports for itself.
        XCTAssertNil(EndpointTransportPolicy.note(for: URL(string: "http:///v1/")!, hasAPIKey: true))
    }
}
