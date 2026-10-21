import Foundation

struct PWDCommand: ShellCommand {
    let name = "pwd"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        context.stdout(context.workingDirectory.path + "\n")
        return 0
    }
}

struct CDCommand: ShellCommand {
    let name = "cd"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        let target: URL
        if let first = arguments.first, !first.isEmpty {
            target = resolve(first, relativeTo: context)
        } else {
            target = context.home
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else {
            throw ShellError.failed("cd: \(target.path): No such file or directory")
        }
        context.workingDirectory = confine(target, to: context.root)
        return 0
    }
}

struct LSCommand: ShellCommand {
    let name = "ls"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        let long = arguments.contains("-l") || arguments.contains("-la") || arguments.contains("-al")
        let all = arguments.contains("-a") || arguments.contains("-la") || arguments.contains("-al")
        let pathArg = arguments.last(where: { !$0.hasPrefix("-") })
        let url = pathArg.map { resolve($0, relativeTo: context) } ?? context.workingDirectory
        let names = (try FileManager.default.contentsOfDirectory(atPath: url.path)).sorted()
        for name in names {
            if name.hasPrefix(".") && !all {
                continue
            }
            if long {
                let child = url.appendingPathComponent(name)
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir)
                let mark = isDir.boolValue ? "d" : "-"
                context.stdout("\(mark) \(name)\n")
            } else {
                context.stdout(name + "\n")
            }
        }
        return 0
    }
}

struct CatCommand: ShellCommand {
    let name = "cat"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        if arguments.isEmpty {
            throw ShellError.usage("cat: missing file")
        }
        for arg in arguments {
            let url = resolve(arg, relativeTo: context)
            let data = try Data(contentsOf: url)
            context.stdout(String(decoding: data, as: UTF8.self))
        }
        return 0
    }
}

struct MkdirCommand: ShellCommand {
    let name = "mkdir"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        guard let first = arguments.first else {
            throw ShellError.usage("mkdir: missing operand")
        }
        try FileManager.default.createDirectory(at: resolve(first, relativeTo: context),
                                                withIntermediateDirectories: arguments.contains("-p"))
        return 0
    }
}

struct TouchCommand: ShellCommand {
    let name = "touch"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        guard let first = arguments.first else {
            throw ShellError.usage("touch: missing file")
        }
        let url = resolve(first, relativeTo: context)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        return 0
    }
}

struct RMCommand: ShellCommand {
    let name = "rm"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        let recursive = arguments.contains("-r") || arguments.contains("-rf") || arguments.contains("-fr")
        let files = arguments.filter { !$0.hasPrefix("-") }
        if files.isEmpty {
            throw ShellError.usage("rm: missing operand")
        }
        for file in files {
            let url = resolve(file, relativeTo: context)
            if recursive {
                try FileManager.default.removeItem(at: url)
            } else {
                try FileManager.default.removeItem(at: url)
            }
        }
        return 0
    }
}

struct CPCommand: ShellCommand {
    let name = "cp"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        let files = arguments.filter { !$0.hasPrefix("-") }
        guard files.count >= 2 else {
            throw ShellError.usage("cp: missing destination")
        }
        let dest = resolve(files.last!, relativeTo: context)
        let src = resolve(files[0], relativeTo: context)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: src, to: dest)
        return 0
    }
}

struct MVCommand: ShellCommand {
    let name = "mv"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        let files = arguments.filter { !$0.hasPrefix("-") }
        guard files.count >= 2 else {
            throw ShellError.usage("mv: missing destination")
        }
        try FileManager.default.moveItem(at: resolve(files[0], relativeTo: context),
                                         to: resolve(files[1], relativeTo: context))
        return 0
    }
}

struct EchoCommand: ShellCommand {
    let name = "echo"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        context.stdout(arguments.joined(separator: " ") + "\n")
        return 0
    }
}

struct EnvCommand: ShellCommand {
    let name = "env"
    var aliases: [String] { ["printenv"] }
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        for key in context.environment.keys.sorted() {
            context.stdout("\(key)=\(context.environment[key] ?? "")\n")
        }
        return 0
    }
}

struct SetenvCommand: ShellCommand {
    let name = "setenv"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        guard arguments.count >= 2 else {
            throw ShellError.usage("setenv NAME VALUE")
        }
        context.environment[arguments[0]] = arguments[1]
        return 0
    }
}

struct WhoamiCommand: ShellCommand {
    let name = "whoami"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        context.stdout((NSUserName().isEmpty ? "mobile" : NSUserName()) + "\n")
        return 0
    }
}

struct UnameCommand: ShellCommand {
    let name = "uname"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        context.stdout("Darwin iPad\n")
        return 0
    }
}

struct DateCommand: ShellCommand {
    let name = "date"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        context.stdout(Date().description + "\n")
        return 0
    }
}

struct GrepCommand: ShellCommand {
    let name = "grep"
    var aliases: [String] { ["egrep", "fgrep"] }
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        guard arguments.count >= 2 else {
            throw ShellError.usage("grep PATTERN FILE")
        }
        let pattern = arguments[0]
        let url = resolve(arguments[1], relativeTo: context)
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.contains(pattern) {
                context.stdout(String(line) + "\n")
            }
        }
        return 0
    }
}

struct HeadCommand: ShellCommand {
    let name = "head"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        var count = 10
        var file: String?
        var i = 0
        while i < arguments.count {
            if arguments[i] == "-n", i + 1 < arguments.count {
                count = Int(arguments[i + 1]) ?? 10
                i += 2
                continue
            }
            file = arguments[i]
            i += 1
        }
        guard let file else {
            throw ShellError.usage("head FILE")
        }
        let text = String(decoding: try Data(contentsOf: resolve(file, relativeTo: context)), as: UTF8.self)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(count) {
            context.stdout(String(line) + "\n")
        }
        return 0
    }
}

struct WCCommand: ShellCommand {
    let name = "wc"
    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        guard let file = arguments.first else {
            throw ShellError.usage("wc FILE")
        }
        let text = String(decoding: try Data(contentsOf: resolve(file, relativeTo: context)), as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let words = text.split { $0.isWhitespace }.count
        context.stdout("\(lines) \(words) \(text.utf8.count) \(file)\n")
        return 0
    }
}

func resolve(_ path: String, relativeTo context: CommandContext) -> URL {
    let raw: URL
    if path == "~" {
        raw = context.home
    } else if path.hasPrefix("~/") {
        raw = context.home.appendingPathComponent(String(path.dropFirst(2)))
    } else if path.hasPrefix("/") {
        raw = URL(fileURLWithPath: path)
    } else {
        raw = context.workingDirectory.appendingPathComponent(path)
    }
    return confine(raw, to: context.root)
}

func confine(_ url: URL, to root: URL) -> URL {
    let rootPath = root.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    if path == rootPath || path.hasPrefix(rootPath + "/") {
        return url
    }
    return root
}
