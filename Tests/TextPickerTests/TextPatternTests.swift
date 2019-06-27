//
//  TextPatternTests.swift
//  TextPicker
//
//  Created by Kåre Morstøl on 20/03/2017.
//
//

import Foundation
import TextPicker
import XCTest

let doublequote = Literal("\"")

class TextPatternTests: XCTestCase {
	func testLiteral() {
		assertParseAll(Literal("a"), input: "abcd", result: "a", count: 1)
		assertParseAll(Literal("b"), input: "abcdb", result: "b", count: 2)
		assertParseAll(Literal("ab"), input: "abcaba", result: "ab", count: 2)
	}

	func testOneOf() {
		assertParseAll(digit, input: "ab12c3,d4", count: 4)
	}

	func testOptional() throws {
		assertParseAll(try Patterns(digit.repeat(min: 0)), input: "123abc123", count: 5)
		assertParseAll(try Patterns(digit.repeat(min: 0, max: 1), letter),
		               input: "123abc", result: ["3a", "b", "c"])
	}

	func testRepeat() {
		assertParseAll(digit.repeat(min: 2), input: "123abc123", count: 2)
		assertParseAll(digit.repeat(min: 1), input: "123abc", result: "123", count: 1)
		assertParseAll(digit.repeat(min: 3), input: "123abc", result: "123", count: 1)
		assertParseAll(digit.repeat(min: 4), input: "123abc", count: 0)

		assertParseAll(digit.repeat(min: 1), input: "a123abc123d", result: "123", count: 2)
		assertParseAll(digit.repeat(min: 1), input: "123abc09d4 8", count: 4)
	}

	func testOrPattern() {
		let pattern: TextPattern = Literal("a") || Literal("b")
		assertParseAll(pattern, input: "bcbd", result: "b", count: 2)
		assertParseAll(pattern, input: "acdaa", result: "a", count: 3)
		assertParseAll(pattern, input: "abcdb", count: 3)
	}

	func testLineStart() throws {
		let text = """
		line 1
		line 2
		line 3
		line 4
		"""
		let pattern: TextPattern = line.start
		assertParseAll(pattern, input: "", result: "", count: 1)
		assertParseAll(pattern, input: "\n", count: 2)
		assertParseAll(pattern, input: text, result: "", count: 4)
		assertParseAll(
			try Patterns(line.start, Bound(), Skip(), Bound(), Literal(" ")),
			input: text, result: "line", count: 4)
		assertParseAll(
			try Patterns(line.start, Literal("line")),
			input: text, result: "line", count: 4)
		assertParseAll(
			try Patterns(
				digit, Skip(), line.start, Literal("l")),
			input: text, result: ["1\nl", "2\nl", "3\nl"])

		XCTAssertThrowsError(try Patterns([line.start, line.start]))
		XCTAssertThrowsError(try Patterns([line.start, Bound(), line.start]))
		XCTAssertThrowsError(
			try Patterns([line.start, Skip(), line.start]))
		XCTAssertNoThrow(try Patterns([line.start, Skip(whileRepeating: alphanumeric || Literal("\n")), line.start]))
	}

	func testLineEnd() throws {
		let pattern: TextPattern = line.end
		assertParseAll(pattern, input: "", result: "", count: 1)
		assertParseAll(pattern, input: "\n", count: 2)
		assertParseAll(pattern, input: "\n\n", count: 3)

		let text = """
		line 1
		line 2
		line 3
		line 4
		"""
		assertParseAll(pattern, input: text, count: 4)
		assertParseAll(
			try Patterns(Literal(" "), Bound(), Skip(), Bound(), line.end),
			input: text, result: ["1", "2", "3", "4"])
		assertParseAll(
			try Patterns(digit, line.end),
			input: text, result: ["1", "2", "3", "4"])
		assertParseAll(
			try Patterns(digit, line.end, Skip(), Literal("l")),
			input: text, result: ["1\nl", "2\nl", "3\nl"])

		XCTAssertThrowsError(try Patterns(line.end, line.end))
		XCTAssertThrowsError(
			try Patterns(line.end, Bound(), line.end))
		XCTAssertThrowsError(
			try Patterns(line.end, Skip(), line.end))
		XCTAssertNoThrow(try Patterns([line.end, Skip(whileRepeating: alphanumeric || Literal("\n")), line.end]))

		assertParseAll(
			try Patterns(line.end),
			input: "\n", count: 2)
	}

	func testParseFile() throws {
		let file = #file
		let text = try! String(contentsOfFile: file, encoding: .utf8)
		let startAt = text.range(of: "func testParseFile()")!.upperBound

		let pattern: TextPattern = try Patterns(Bound(), Literal("\tlet "), Skip(), Bound(), Literal("="))
		let ranges = pattern.parseAll(text, from: startAt)

		XCTAssertEqual(ranges.count, 5)
		XCTAssertEqual(text[ranges.first!], "\tlet file "[...])
	}
}

extension TextPatternTests {
	public static var allTests = [
		("testLiteral", testLiteral),
		("testOneOf", testOneOf),
		("testOptional", testOptional),
		("testRepeat", testRepeat),
		("testOrPattern", testOrPattern),
		("testLineStart", testLineStart),
		("testLineEnd", testLineEnd),
		("testParseFile", testParseFile),
	]
}
