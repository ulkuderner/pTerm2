import Foundation

func it_fatalError(_ message: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) -> Never {
    fatalError(message(), file: file, line: line)
}

func it_assert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) {
    precondition(condition(), message(), file: file, line: line)
}

func DLog(_ message: @autoclosure () -> String) {
#if DEBUG
    print(message())
#endif
}
