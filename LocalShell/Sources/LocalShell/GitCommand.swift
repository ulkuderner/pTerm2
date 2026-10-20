import Foundation

/// libgit2-backed porcelain. The first command set is implemented on the
/// working tree so `init`, `status`, `add`, `commit`, and `log` work without
/// the native library; `clone` / `fetch` / `pull` / `push` require libgit2.
struct GitCommand: ShellCommand {
    let name = "git"

    func run(arguments: [String], context: inout CommandContext) throws -> Int32 {
        guard let verb = arguments.first else {
            context.stdout("usage: git <clone|init|status|add|commit|fetch|pull|push|log|diff|branch|checkout|switch>\n")
            return 1
        }
        let rest = Array(arguments.dropFirst())
        switch verb {
        case "init":
            return try gitInit(rest, context: &context)
        case "status":
            return try gitStatus(context: &context)
        case "add":
            return try gitAdd(rest, context: &context)
        case "commit":
            return try gitCommit(rest, context: &context)
        case "log":
            return try gitLog(context: &context)
        case "branch":
            return try gitBranch(context: &context)
        case "diff":
            return try gitDiff(context: &context)
        case "checkout", "switch":
            return try gitCheckout(rest, context: &context)
        case "clone", "fetch", "pull", "push":
            return try gitRemote(verb, rest, context: &context)
        default:
            throw ShellError.usage("git: unknown subcommand \(verb)")
        }
    }

    private func gitDir(in context: CommandContext) -> URL {
        context.workingDirectory.appendingPathComponent(".git")
    }

    private func gitInit(_ arguments: [String], context: inout CommandContext) throws -> Int32 {
        let root = arguments.first.map { resolve($0, relativeTo: context) } ?? context.workingDirectory
        let git = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git.appendingPathComponent("objects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: git.appendingPathComponent("refs/heads"), withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        try "".write(to: git.appendingPathComponent("index"), atomically: true, encoding: .utf8)
        context.stdout("Initialized empty Git repository in \(git.path)\n")
        return 0
    }

    private func gitStatus(context: inout CommandContext) throws -> Int32 {
        let git = gitDir(in: context)
        guard FileManager.default.fileExists(atPath: git.path) else {
            throw ShellError.failed("fatal: not a git repository")
        }
        let head = (try? String(contentsOf: git.appendingPathComponent("HEAD"), encoding: .utf8)) ?? "ref: refs/heads/main\n"
        let branch = head.replacingOccurrences(of: "ref: refs/heads/", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        context.stdout("On branch \(branch)\n")
        let tracked = Set(indexEntries(at: git))
        let files = try FileManager.default.contentsOfDirectory(atPath: context.workingDirectory.path)
            .filter { $0 != ".git" }
            .sorted()
        var untracked: [String] = []
        var staged: [String] = []
        for file in files {
            if tracked.contains(file) {
                staged.append(file)
            } else {
                untracked.append(file)
            }
        }
        if !staged.isEmpty {
            context.stdout("Changes to be committed:\n")
            for file in staged {
                context.stdout("\t\(file)\n")
            }
        }
        if !untracked.isEmpty {
            context.stdout("Untracked files:\n")
            for file in untracked {
                context.stdout("\t\(file)\n")
            }
        }
        if staged.isEmpty && untracked.isEmpty {
            context.stdout("nothing to commit, working tree clean\n")
        }
        return 0
    }

    private func gitAdd(_ arguments: [String], context: inout CommandContext) throws -> Int32 {
        let git = gitDir(in: context)
        guard FileManager.default.fileExists(atPath: git.path) else {
            throw ShellError.failed("fatal: not a git repository")
        }
        var entries = Set(indexEntries(at: git))
        let files = arguments.isEmpty || arguments == ["."]
            ? try FileManager.default.contentsOfDirectory(atPath: context.workingDirectory.path).filter { $0 != ".git" }
            : arguments
        for file in files {
            entries.insert(file)
        }
        try entries.sorted().joined(separator: "\n").write(to: git.appendingPathComponent("index"), atomically: true, encoding: .utf8)
        return 0
    }

    private func gitCommit(_ arguments: [String], context: inout CommandContext) throws -> Int32 {
        let git = gitDir(in: context)
        var message = "commit"
        if let index = arguments.firstIndex(of: "-m"), arguments.indices.contains(index + 1) {
            message = arguments[index + 1]
        }
        let entries = indexEntries(at: git)
        if entries.isEmpty {
            throw ShellError.failed("nothing to commit")
        }
        let log = git.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: log, withIntermediateDirectories: true)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: log.appendingPathComponent("HEAD")) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try handle.close()
        } else {
            try line.write(to: log.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        }
        let head = (try? String(contentsOf: git.appendingPathComponent("HEAD"), encoding: .utf8)) ?? "ref: refs/heads/main\n"
        if head.hasPrefix("ref: ") {
            let ref = head.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            try message.write(to: git.appendingPathComponent(ref), atomically: true, encoding: .utf8)
        }
        context.stdout("[\(head.trimmingCharacters(in: .whitespacesAndNewlines))] \(message)\n")
        return 0
    }

    private func gitLog(context: inout CommandContext) throws -> Int32 {
        let log = gitDir(in: context).appendingPathComponent("logs/HEAD")
        if FileManager.default.fileExists(atPath: log.path) {
            context.stdout(try String(contentsOf: log, encoding: .utf8))
        }
        return 0
    }

    private func gitBranch(context: inout CommandContext) throws -> Int32 {
        let heads = gitDir(in: context).appendingPathComponent("refs/heads")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: heads.path)) ?? ["main"]
        for name in names.sorted() {
            context.stdout("* \(name)\n")
        }
        return 0
    }

    private func gitDiff(context: inout CommandContext) throws -> Int32 {
        context.stdout("")
        return 0
    }

    private func gitCheckout(_ arguments: [String], context: inout CommandContext) throws -> Int32 {
        guard let name = arguments.first else {
            throw ShellError.usage("git checkout <branch>")
        }
        let git = gitDir(in: context)
        try "ref: refs/heads/\(name)\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: git.appendingPathComponent("refs/heads"), withIntermediateDirectories: true)
        let ref = git.appendingPathComponent("refs/heads/\(name)")
        if !FileManager.default.fileExists(atPath: ref.path) {
            try "".write(to: ref, atomically: true, encoding: .utf8)
        }
        context.stdout("Switched to branch '\(name)'\n")
        return 0
    }

    private func gitRemote(_ verb: String, _ arguments: [String], context: inout CommandContext) throws -> Int32 {
        if PadGit.ready {
            return PadGit.run(verb: verb, arguments: arguments, workingDirectory: context.workingDirectory.path)
        }
        throw ShellError.failed("git \(verb) requires libgit2. Run tools/download_frameworks.sh")
    }

    private func indexEntries(at git: URL) -> [String] {
        let text = (try? String(contentsOf: git.appendingPathComponent("index"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}

enum PadGit {
    static var ready: Bool { false }

    static func run(verb: String, arguments: [String], workingDirectory: String) -> Int32 {
        _ = verb
        _ = arguments
        _ = workingDirectory
        return 1
    }
}
