import XCTest
@testable import PassboltBar

// Samples match go-passbolt-cli 0.5.2 output format (2-space indented JSON, omitempty fields), fake data.
private let listJSON = """
[
  {
    "id": "8b0d6f2e-1c34-4a8e-9a57-3f1e2d9c0a11",
    "name": "GitHub",
    "username": "octocat",
    "uri": "https://github.com"
  },
  {
    "id": "c2f1a9b4-77d0-4e6b-8f3a-5d2c1b0e9f22",
    "name": "Försäkringskassan",
    "username": "",
    "uri": ""
  },
  {
    "id": "e5a3c8d1-0b2f-4c7e-a6d9-1f4b3e2a8c33",
    "name": "Router admin"
  }
]
"""

private let getJSON = """
{
  "folder_parent_id": "",
  "name": "GitHub",
  "username": "octocat",
  "uri": "https://github.com",
  "password": "s3cr3t-P@ss",
  "description": "work account",
  "metadata": {
    "name": "GitHub",
    "object_type": "PASSBOLT_RESOURCE_METADATA",
    "resource_type_id": "a28a04cd-6f53-518a-967c-9963bf9cec51",
    "uris": ["https://github.com"],
    "username": "octocat"
  },
  "secret": {
    "object_type": "PASSBOLT_SECRET_DATA",
    "password": "s3cr3t-P@ss"
  },
  "deleted": false,
  "expired": false
}
"""

// v5 item with two URLs, a secret note and custom fields (label in metadata, value in secret).
private let getV5JSON = """
{
  "name": "AWS",
  "username": "root",
  "uri": "https://aws.amazon.com",
  "password": "hunter2",
  "description": "prod",
  "metadata": {
    "name": "AWS",
    "uris": ["https://aws.amazon.com", "https://console.aws.amazon.com"],
    "description": "prod",
    "custom_fields": [
      {"id": "11111111-1111-4111-8111-111111111111", "type": "text", "metadata_key": "Account ID"},
      {"id": "22222222-2222-4222-8222-222222222222", "type": "password", "metadata_key": "API secret"},
      {"id": "33333333-3333-4333-8333-333333333333", "type": "number", "metadata_key": "Port"},
      {"id": "44444444-4444-4444-8444-444444444444", "type": "boolean", "metadata_key": "MFA"},
      {"id": "55555555-5555-4555-8555-555555555555", "type": "text", "metadata_key": "Empty"}
    ]
  },
  "secret": {
    "password": "hunter2",
    "description": "rotate yearly",
    "custom_fields": [
      {"id": "11111111-1111-4111-8111-111111111111", "type": "text", "secret_value": "1234-5678"},
      {"id": "22222222-2222-4222-8222-222222222222", "type": "password", "secret_value": "AKIA-x"},
      {"id": "33333333-3333-4333-8333-333333333333", "type": "number", "secret_value": 8443},
      {"id": "44444444-4444-4444-8444-444444444444", "type": "boolean", "secret_value": true},
      {"id": "55555555-5555-4555-8555-555555555555", "type": "text", "secret_value": null}
    ]
  },
  "deleted": false,
  "expired": false
}
"""

final class ParsingTests: XCTestCase {
    func testDecodeDetailsV5() throws {
        let fields = try PassboltCLI.decodeDetails(Data(getV5JSON.utf8))
        XCTAssertEqual(fields.map(\.label), ["Username", "Password", "URL", "URL", "Description", "Note",
                                             "Account ID", "API secret", "Port", "MFA"])
        XCTAssertEqual(fields.map(\.value), ["root", "hunter2", "https://aws.amazon.com", "https://console.aws.amazon.com",
                                             "prod", "rotate yearly", "1234-5678", "AKIA-x", "8443", "true"])
        XCTAssertEqual(fields.filter(\.secret).map(\.label), ["Password", "API secret"])
    }

    func testDecodeDetailsV4() throws {
        // No `uris` in the metadata, and the description isn't repeated as a note.
        let fields = try PassboltCLI.decodeDetails(Data(getJSON.utf8))
        XCTAssertEqual(fields.map(\.label), ["Username", "Password", "URL", "Description"])
    }

    func testDecodeList() throws {
        let list = try PassboltCLI.decodeList(Data(listJSON.utf8))
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[0].username, "octocat")
        XCTAssertEqual(list[2].name, "Router admin")
        XCTAssertNil(list[2].uri)
    }

    func testDecodeEmptyList() throws {
        XCTAssertEqual(try PassboltCLI.decodeList(Data("[]\n".utf8)).count, 0)
    }

    func testDecodePassword() throws {
        XCTAssertEqual(try PassboltCLI.decodePassword(Data(getJSON.utf8)), "s3cr3t-P@ss")
    }

    func testErrorMapping() {
        XCTAssertEqual(PassboltCLI.error(from: "Error: creating Client: get Private Key: unlock Key: gopenpgp: error in unlocking key\n").kind, .wrongPassphrase)
        XCTAssertEqual(PassboltCLI.error(from: "Error: logging in: getting CSRF Token: handling MFA callback: reading TOTP: EOF").kind, .totpMissing)
        XCTAssertEqual(PassboltCLI.error(from: "Error: logging in: failed MFA Challenge 2 times: MFA challenge failed").kind, .totpRejected)
        XCTAssertEqual(PassboltCLI.error(from: "Error: boom\n").message, "Error: boom")
    }
}

final class CredentialTests: XCTestCase {
    func testTOTPSecretParsing() throws {
        XCTAssertEqual(try TOTPSecret.parse(" JBSW Y3DP EHPK 3PXP \n"), "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(try TOTPSecret.parse("otpauth://totp/Passbolt:me%40x.se?secret=JBSWY3DPEHPK3PXP&issuer=Passbolt"),
                       "JBSWY3DPEHPK3PXP")
    }

    func testTOTPValidation() {
        XCTAssertTrue(TOTPSecret.isValid("JBSWY3DPEHPK3PXP"))
        XCTAssertFalse(TOTPSecret.isValid("123456"))
        XCTAssertFalse(TOTPSecret.isValid("not-base32-at-all!"))
    }

    func testBase32() {
        XCTAssertEqual(TOTPSecret.base32Encode(Data("Hello!".utf8) + Data([0xDE, 0xAD, 0xBE, 0xEF])), "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(TOTPSecret.base32Encode(Data("f".utf8)), "MY")
    }

    /// Hand-built protobuf, same layout Google Authenticator exports.
    private func account(_ secret: Data, name: String, issuer: String) -> Data {
        func field(_ n: UInt8, _ d: Data) -> Data { Data([n << 3 | 2, UInt8(d.count)]) + d }
        let params = field(1, secret) + field(2, Data(name.utf8)) + field(3, Data(issuer.utf8)) + Data([0x20, 0x01, 0x28, 0x01])
        return field(1, params)
    }

    private func migrationLink(_ payload: Data) -> String {
        let b64 = (payload + Data([0x10, 0x01])).base64EncodedString()
        return "otpauth-migration://offline?data=" + b64.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }

    func testGoogleAuthenticatorExport() throws {
        let secret = Data("Hello!".utf8) + Data([0xDE, 0xAD, 0xBE, 0xEF])
        let github = account(Data(repeating: 7, count: 10), name: "octocat", issuer: "GitHub")
        let passbolt = account(secret, name: "per@kumpan.se", issuer: "passbolt.kumpan.tech")

        XCTAssertEqual(try TOTPSecret.parse(migrationLink(github + passbolt)), "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(try TOTPSecret.parse(migrationLink(passbolt)), "JBSWY3DPEHPK3PXP")
        XCTAssertThrowsError(try TOTPSecret.parse(migrationLink(github + account(secret, name: "x", issuer: "Other"))))
        XCTAssertThrowsError(try TOTPSecret.parse("otpauth-migration://offline?data=%FF%FF"))
    }

    func testEnvironment() {
        let plain = PassboltCLI.environment(Credentials(passphrase: "pw"))
        XCTAssertEqual(plain["USERPASSWORD"], "pw")
        XCTAssertNil(plain["MFAMODE"])
        let mfa = PassboltCLI.environment(Credentials(passphrase: "pw", totpSecret: "ABC"))
        XCTAssertEqual(mfa["MFAMODE"], "noninteractive-totp")
        XCTAssertEqual(mfa["MFATOTPTOKEN"], "ABC")
    }
}

final class UpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(Updater.isVersion("1.0.10", newerThan: "1.0.9"))
        XCTAssertTrue(Updater.isVersion("1.1", newerThan: "1.0.99"))
        XCTAssertFalse(Updater.isVersion("1.0.5", newerThan: "1.0.5"))
        XCTAssertFalse(Updater.isVersion("1.0", newerThan: "1.0.0"))
        XCTAssertFalse(Updater.isVersion("1.0.4", newerThan: "1.0.5"))
    }
}

final class PasswordGeneratorTests: XCTestCase {
    func testLengthAndClasses() {
        for _ in 0..<200 {
            let pw = PasswordGenerator.generate()
            XCTAssertEqual(pw.count, 20)
            for c in PasswordGenerator.classes { XCTAssertTrue(pw.contains(where: c.contains), pw) }
            let allowed = Set(PasswordGenerator.classes.joined())
            XCTAssertTrue(pw.allSatisfy(allowed.contains))
        }
    }

    func testUnique() {
        XCTAssertEqual(Set((0..<100).map { _ in PasswordGenerator.generate() }).count, 100)
    }

    func testRandomIndexInRange() {
        for _ in 0..<1000 { XCTAssertTrue((0..<86).contains(PasswordGenerator.randomIndex(below: 86))) }
    }
}

final class SearchFilterTests: XCTestCase {
    let items = try! PassboltCLI.decodeList(Data(listJSON.utf8))

    func names(_ q: String) -> [String] { filterResources(items, query: q).compactMap(\.name) }

    func testEmptyQueryReturnsAll() { XCTAssertEqual(names("  ").count, 3) }
    func testNameSubstringCaseInsensitive() { XCTAssertEqual(names("hub"), ["GitHub"]) }
    func testUsernameAndURI() {
        XCTAssertEqual(names("octo"), ["GitHub"])
        XCTAssertEqual(names("github.com"), ["GitHub"])
    }
    func testDiacriticInsensitive() { XCTAssertEqual(names("forsak"), ["Försäkringskassan"]) }
    func testFuzzy() { XCTAssertEqual(names("rtradm"), ["Router admin"]) }
    func testNoMatch() { XCTAssertEqual(names("zzz"), []) }
    func testPrefixRanksFirst() {
        let extra = items + [Resource(id: "x", name: "My Router", username: nil, uri: nil)]
        XCTAssertEqual(filterResources(extra, query: "router").compactMap(\.name), ["Router admin", "My Router"])
    }
}
