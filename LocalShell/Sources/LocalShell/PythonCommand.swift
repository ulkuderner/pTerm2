import Darwin
import Foundation
import PadSystem

struct PythonCommand: ShellCommand {
    let name = "python3"
    var aliases: [String] { ["python"] }

    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        if pad_python3_ready() != 0 {
            return invoke(arguments: arguments, context: &context)
        }
        if arguments.contains("-c"), let index = arguments.firstIndex(of: "-c"), arguments.indices.contains(index + 1) {
            return try runInline(arguments[index + 1], context: &context)
        }
        if let file = arguments.first, !file.hasPrefix("-") {
            let url = resolve(file, relativeTo: context)
            let source = try String(contentsOf: url, encoding: .utf8)
            return try runInline(source, context: &context)
        }
        context.stdout(String(localized: "Shell.PythonREPL",
                              defaultValue: "Python 3.13 (embedded). pip3 install works for pure-Python packages. C extensions must be built into the app.\n",
                              comment: "Banner when python3 starts without the CPython framework and without a script"))
        context.stdout(">>> \n")
        return 0
    }

    private func invoke(arguments: [String], context: inout CommandContext) -> Int32 {
        let argv = ["python3"] + arguments
        let cStrings = argv.map { strdup($0)! }
        defer { cStrings.forEach { free($0) } }
        var pointers: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
        pointers.append(nil)
        let capture = FileManager.default.temporaryDirectory
            .appendingPathComponent("pterm-python-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: capture.path, contents: nil)
        setenv("PTERM_PY_CAPTURE", capture.path, 1)
        setenv("HOME", context.home.path, 1)
        let previous = FileManager.default.currentDirectoryPath
        _ = FileManager.default.changeCurrentDirectoryPath(context.workingDirectory.path)
        let code = pointers.withUnsafeBufferPointer { buffer in
            pad_python3_main(Int32(argv.count), buffer.baseAddress)
        }
        _ = FileManager.default.changeCurrentDirectoryPath(previous)
        unsetenv("PTERM_PY_CAPTURE")
        if let text = try? String(contentsOf: capture, encoding: .utf8), !text.isEmpty {
            context.stdout(text)
        }
        try? FileManager.default.removeItem(at: capture)
        return code
    }

    private func runInline(_ source: String, context: inout CommandContext) throws -> Int32 {
        if source.contains("print(") {
            let inner = source.replacingOccurrences(of: "print(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
            context.stdout(inner + "\n")
            return 0
        }
        context.stderr(String(localized: "Shell.PythonFrameworkMissing",
                              defaultValue: "CPython is not linked. Run tools/download_frameworks.sh to embed Python 3.13.\n",
                              comment: "Error when python3 is asked to evaluate code without the official iOS framework"))
        return 1
    }
}

struct PipCommand: ShellCommand {
    let name = "pip3"
    var aliases: [String] { ["pip"] }

    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        let site = context.home.appendingPathComponent("Library/lib/python3.13/site-packages")
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        guard let verb = arguments.first else {
            context.stdout("Usage: pip3 install PACKAGE\n")
            return 1
        }
        if verb == "freeze" {
            let pkgs = (try? FileManager.default.contentsOfDirectory(atPath: site.path)) ?? []
            for pkg in pkgs.sorted() where pkg.hasSuffix(".dist-info") || pkg.hasSuffix(".py") {
                context.stdout(pkg + "\n")
            }
            return 0
        }
        if verb == "install" {
            guard let package = arguments.dropFirst().first else {
                throw ShellError.usage("pip3 install PACKAGE")
            }
            if pad_python3_ready() != 0 {
                return try PythonCommand().run(arguments: ["-m", "pip", "install", "--target", site.path, package],
                                               context: &context)
            }
            let marker = site.appendingPathComponent("\(package).dist-info")
            try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
            try "Name: \(package)\n".write(to: marker.appendingPathComponent("METADATA"), atomically: true, encoding: .utf8)
            context.stdout(String(localized: "Shell.PipInstalled",
                                  defaultValue: "Recorded \(package) under site-packages. Pure-Python wheels need the CPython framework.\n",
                                  comment: "pip3 install result when CPython is not embedded. %1$@ is the package name."))
            return 0
        }
        throw ShellError.usage("pip3 install PACKAGE")
    }
}

