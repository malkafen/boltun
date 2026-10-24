import Foundation
import Testing
@testable import BoltunKit

@Suite struct JSONValueTests {
    @Test func decodesEveryKind() throws {
        let value = try MattermostJSON.decoder.decode(JSONValue.self, from: Data(#"{"a":null,"b":true,"c":1.5,"d":"x","e":[1,"y"],"f":{"g":false}}"#.utf8))
        #expect(value["a"] == .null)
        #expect(value["b"] == .bool(true))
        #expect(value["c"] == .number(1.5))
        #expect(value["d"] == .string("x"))
        #expect(value["e"] == .array([.number(1), .string("y")]))
        #expect(value["f"]?["g"] == .bool(false))
        #expect(value["missing"] == nil)
    }

    @Test func roundTrips() throws {
        let value: JSONValue = .object(["n": .null, "b": .bool(false), "x": .number(-2), "s": .string("é"), "a": .array([.object([:])])])
        let data = try MattermostJSON.encoder.encode(value)
        #expect(try MattermostJSON.decoder.decode(JSONValue.self, from: data) == value)
    }

    @Test func stringValue() {
        #expect(JSONValue.string("a").stringValue == "a")
        #expect(JSONValue.number(42).stringValue == "42")
        #expect(JSONValue.number(1.25).stringValue == "1.25")
        #expect(JSONValue.number(1e300).stringValue == "1e+300")
        #expect(JSONValue.number(.infinity).stringValue == "inf")
        #expect(JSONValue.bool(true).stringValue == "true")
        #expect(JSONValue.bool(false).stringValue == "false")
        #expect(JSONValue.null.stringValue == nil)
        #expect(JSONValue.array([]).stringValue == nil)
    }

    @Test func boolValue() {
        #expect(JSONValue.bool(true).boolValue == true)
        #expect(JSONValue.string("true").boolValue == true)
        #expect(JSONValue.string("false").boolValue == false)
        #expect(JSONValue.string("yes").boolValue == nil)
        #expect(JSONValue.number(0).boolValue == false)
        #expect(JSONValue.number(2).boolValue == true)
        #expect(JSONValue.null.boolValue == nil)
    }

    @Test func numericValues() {
        #expect(JSONValue.number(3.9).intValue == 3)
        #expect(JSONValue.string("12").intValue == 12)
        #expect(JSONValue.string("1.5").doubleValue == 1.5)
        #expect(JSONValue.string("x").doubleValue == nil)
        #expect(JSONValue.bool(true).doubleValue == nil)
        #expect(JSONValue.number(1e300).intValue == nil)
        #expect(JSONValue.number(.nan).intValue == nil)
    }

    @Test func containers() {
        #expect(JSONValue.array([.null]).arrayValue == [.null])
        #expect(JSONValue.string("x").arrayValue == nil)
        #expect(JSONValue.object(["k": .null]).objectValue == ["k": .null])
        #expect(JSONValue.number(1).objectValue == nil)
        #expect(JSONValue.number(1)["k"] == nil)
    }
}
