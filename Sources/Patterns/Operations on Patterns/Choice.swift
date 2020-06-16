//
//  SwiftPattern.swift
//  Patterns
//
//  Created by Kåre Morstøl on 20/03/2017.
//
//

import Foundation

public struct OrPattern<First: Pattern, Second: Pattern>: Pattern {
	public let first: First
	public let second: Second

	init(_ first: First, or second: Second) {
		self.first = first
		self.second = second
	}

	public var description: String {
		"(\(first) / \(second))"
	}

	public func createInstructions(_ instructions: inout Instructions) throws {
		let inst1 = try first.createInstructions()
		let inst2 = try second.createInstructions()
		instructions.append(.choice(offset: inst1.count + 3))
		instructions.append(contentsOf: inst1)
		instructions.append(.commit)
		instructions.append(.jump(offset: inst2.count + 1))
		instructions.append(contentsOf: inst2)
		instructions.append(.choiceEnd)
	}
}

public func / <First: Pattern, Second: Pattern>(p1: First, p2: Second) -> OrPattern<First, Second> {
	OrPattern(p1, or: p2)
}

public func / <Second: Pattern>(p1: Literal, p2: Second) -> OrPattern<Literal, Second> {
	OrPattern(p1, or: p2)
}

public func / <First: Pattern>(p1: First, p2: Literal) -> OrPattern<First, Literal> {
	OrPattern(p1, or: p2)
}

public func / (p1: Literal, p2: Literal) -> OrPattern<Literal, Literal> {
	OrPattern(p1, or: p2)
}
