//
//  VMBacktrack.swift
//
//
//  Created by Kåre Morstøl on 18/04/2020.
//

@usableFromInline
struct VMEngine<Input: BidirectionalCollection> where Input.Element: Hashable {
	@usableFromInline
	typealias Instructions = ContiguousArray<Instruction<Input>>
	@usableFromInline
	typealias Captures = ContiguousArray<(index: Input.Index,
	                                      instruction: VMEngine<Input>.Instructions.Index)>.SubSequence
	@usableFromInline
	let instructions: Instructions

	@usableFromInline
	init<P: Pattern>(_ pattern: P) throws where Input == P.Input {
		var instructions = try Instructions {
			$0.append(.fail) // dummy instruction used by '.choice'.
			try pattern.createInstructions(&$0)
			$0.append(.match)
		}
		instructions.moveMovablesForward()
		instructions.replaceSkips()
		self.instructions = instructions
	}

	@_specialize(where Input == String) // doesn't happen automatically (swiftlang-1200.0.28.1).
	@_specialize(where Input == String.UTF8View)
	@usableFromInline
	func match(in input: Input, at startIndex: Input.Index) -> Parser<Input>.Match? {
		launch(input: input, startIndex: startIndex)
	}
}

extension Parser.Match {
	@usableFromInline
	init(_ thread: VMEngine<Input>.Thread,
	     instructions: VMEngine<Input>.Instructions,
	     captures: VMEngine<Input>.Captures) {
		var newCaptures = [(name: String?, range: Range<Input.Index>)]()
		newCaptures.reserveCapacity(captures.count / 2)
		var captureBeginnings = [(name: String?, start: Input.Index)]()
		captureBeginnings.reserveCapacity(captures.capacity)
		for capture in captures {
			switch instructions[capture.instruction] {
			case let .captureStart(name, _):
				captureBeginnings.append((name, capture.index))
			case .captureEnd:
				let beginning = captureBeginnings.removeLast()
				newCaptures.append((name: beginning.name, range: beginning.start ..< capture.index))
			default:
				fatalError("Captured wrong instructions.")
			}
		}
		assert(captureBeginnings.isEmpty)
		self.endIndex = thread.inputIndex
		self.captures = newCaptures
	}
}

extension VMEngine {
	@usableFromInline
	struct Thread {
		@usableFromInline
		var instructionIndex: Instructions.Index
		@usableFromInline
		var inputIndex: Input.Index
		@usableFromInline
		var capturesEndIndex: Captures.Index
		@usableFromInline
		var isReturnAddress: Bool = false

		@usableFromInline
		init(startAt instructionIndex: Int, withDataFrom other: Thread) {
			self.instructionIndex = instructionIndex
			self.inputIndex = other.inputIndex
			self.capturesEndIndex = other.capturesEndIndex
		}

		@usableFromInline
		init(instructionIndex: Instructions.Index, inputIndex: Input.Index) {
			self.instructionIndex = instructionIndex
			self.inputIndex = inputIndex
			self.capturesEndIndex = 0
		}
	}

	@usableFromInline
	func launch(input: Input, startIndex: Input.Index? = nil) -> Parser<Input>.Match? {
		// Skip the first instruction, which is always '.fail'.
		var stack = ContiguousArray<Thread>()[...]
		stack.append(
			Thread(instructionIndex: instructions.startIndex + 1, inputIndex: startIndex ?? input.startIndex))
		var captures = Captures()

		while var thread = stack.popLast() {
			assert(!thread.isReturnAddress, "Stack unexpectedly contains .returnAddress after fail")
			captures.removeSuffix(from: thread.capturesEndIndex)
			defer { // Fail, when `break loop` is called.
				stack.removeSuffix(where: { $0.isReturnAddress })
			}

			loop: while true {
				switch instructions[thread.instructionIndex] {
				case let .elementEquals(char):
					guard thread.inputIndex != input.endIndex, input[thread.inputIndex] == char else { break loop }
					input.formIndex(after: &thread.inputIndex)
					thread.instructionIndex += 1
				case let .checkElement(test):
					guard thread.inputIndex != input.endIndex, test(input[thread.inputIndex]) else { break loop }
					input.formIndex(after: &thread.inputIndex)
					thread.instructionIndex += 1
				case let .checkIndex(test, offset):
					let index = input.index(thread.inputIndex, offsetBy: offset)
					guard test(input, index) else { break loop }
					thread.instructionIndex += 1
				case let .moveIndex(distance):
					guard input.formIndexSafely(&thread.inputIndex, offsetBy: distance) else { break loop }
					thread.instructionIndex += 1
				case let .search(closure):
					guard let index = closure(input, thread.inputIndex) else { break loop }
					thread.inputIndex = index
					thread.instructionIndex += 1
				case let .jump(distance):
					thread.instructionIndex += distance
				case let .captureStart(_, offset),
				     let .captureEnd(offset):
					let index = input.index(thread.inputIndex, offsetBy: offset)
					captures.append((index: index, instruction: thread.instructionIndex))
					thread.instructionIndex += 1
				case let .choice(offset, atIndex):
					var newThread = Thread(startAt: thread.instructionIndex + offset, withDataFrom: thread)
					if atIndex != 0, !input.formIndexSafely(&newThread.inputIndex, offsetBy: atIndex) {
						// we must always add to the stack here, so send it to an instruction that is always `.fail`
						newThread.instructionIndex = instructions.startIndex
					}
					newThread.capturesEndIndex = captures.endIndex
					stack.append(newThread)
					thread.instructionIndex += 1
				case .choiceEnd:
					thread.instructionIndex += 1
				case .commit:
					#if DEBUG
					let entry = stack.popLast()
					assert(entry != nil, "Empty stack during .commit")
					assert(entry.map { !$0.isReturnAddress } ?? true, "Missing thread during .commit")
					#else
					stack.removeLast()
					#endif
					thread.instructionIndex += 1
				case let .call(offset):
					var returnAddress = thread
					returnAddress.instructionIndex += 1
					returnAddress.isReturnAddress = true
					stack.append(returnAddress)
					thread.instructionIndex += offset
				case .return:
					guard let entry = stack.popLast() else { fatalError("Missing return address upon .return.") }
					assert(entry.isReturnAddress, "Unexpected uncommited thread in stack.")
					thread.instructionIndex = entry.instructionIndex
				case .fail:
					break loop
				case .match:
					return Parser.Match(thread, instructions: instructions, captures: captures)
				case .openCall:
					fatalError("`.openCall` should be removed by Grammar.")
				case .skip:
					fatalError("`.skip` should be removed by Parser in preprocessing.")
				}
			}
		}
		return nil
	}
}
