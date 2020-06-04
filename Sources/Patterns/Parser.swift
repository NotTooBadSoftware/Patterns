//
//  Patterns.swift
//  Patterns
//
//  Created by Kåre Morstøl on 23/10/2018.
//

public protocol Pattern: CustomStringConvertible {
	typealias Input = String
	typealias ParsedRange = Range<Input.Index>
	typealias Instructions = ContiguousArray<Instruction<Input>> // TODO: use almost everywhere

	func createInstructions(_ instructions: inout Instructions)
	func createInstructions() -> Instructions
}

extension Pattern {
	public func createInstructions() -> Instructions {
		var instructions = Instructions()
		self.createInstructions(&instructions)
		return instructions
	}
}

public struct Parser<Input: BidirectionalCollection> where Input.Element: Equatable {
	public enum InitError: Error, CustomStringConvertible {
		case invalid([Pattern])
		case message(String)

		public var description: String {
			switch self {
			case let .invalid(patterns):
				return "Invalid series of patterns: \(patterns)"
			case let .message(string):
				return string
			}
		}
	}

	let matcher: VMBacktrackEngine<Input>

	public init<P: Pattern>(_ pattern: P) throws where P.Input == Input {
		self.matcher = try VMBacktrackEngine(pattern)
	}

	public init<P: Pattern>(search pattern: P) throws where P.Input == Input {
		try self.init(Skip() • pattern)
	}

	public func ranges(in input: Input, from startindex: Input.Index? = nil)
		-> AnySequence<Range<Input.Index>> {
		return AnySequence(matches(in: input, from: startindex).lazy.map(\.range))
	}

	public struct Match: Equatable {
		public let endIndex: Input.Index
		public let captures: [(name: String?, range: Range<Input.Index>)]

		@inlinable
		public static func == (lhs: Parser<Input>.Match, rhs: Parser<Input>.Match) -> Bool {
			lhs.endIndex == rhs.endIndex
				&& lhs.captures.elementsEqual(rhs.captures, by: { left, right in
					left.range == right.range && left.name == right.name
				})
		}

		@inlinable
		public var range: Range<Input.Index> {
			// TODO: Is `captures.last!.range.upperBound` always the highest captured index?
			// What if there is one large range and a smaller inside that?
			captures.isEmpty
				? endIndex ..< endIndex
				: captures.first!.range.lowerBound ..< captures.last!.range.upperBound
		}

		public func description(using input: Input) -> String {
			return """
			endIndex: \(input[endIndex])
			captures: \(captures.map { "\($0.name ?? "")    \(input[$0.range])" })

			"""
		}

		@inlinable
		public subscript(one name: String) -> Range<Input.Index>? {
			return captures.first(where: { $0.name == name })?.range
		}

		@inlinable
		public subscript(multiple name: String) -> [Range<Input.Index>] {
			return captures.filter { $0.name == name }.map(\.range)
		}

		public var names: Set<String> { Set(captures.compactMap(\.name)) }
	}

	@usableFromInline
	internal func match(in input: Input, from startIndex: Input.Index) -> Match? {
		return matcher.match(in: input, from: startIndex)
	}

	@inlinable
	public func matches(in input: Input, from startindex: Input.Index? = nil)
		-> UnfoldSequence<Match, Input.Index> {
		var stop = false
		var lastMatch: Match?
		return sequence(state: startindex ?? input.startIndex, next: { (index: inout Input.Index) in
			guard var match = self.match(in: input, from: index), !stop else { return nil }
			if match == lastMatch {
				guard index != input.endIndex else { return nil }
				input.formIndex(after: &index)
				guard let newMatch = self.match(in: input, from: index) else { return nil }
				match = newMatch
			}
			lastMatch = match
			let range = match.range
			if range.upperBound == index {
				guard range.upperBound != input.endIndex else {
					stop = true
					return match
				}
				input.formIndex(after: &index)
			} else {
				index = range.upperBound
			}
			return match
		})
	}
}
