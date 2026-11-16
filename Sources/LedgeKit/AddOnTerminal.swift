#if canImport(Darwin)
import Darwin
import Foundation

/// Runs a program on a pseudo-terminal for the add-on's terminal page (LedgeKit 0.18.0): the person's login shell
/// unless told otherwise, at the size Ledge asks for, its output sent to Ledge in order.
///
/// A whole terminal add-on:
///
/// ```swift
/// let terminal = AddOnTerminal()
/// var handlers = AddOnHandlers()
/// terminal.connect(&handlers)
/// exit(await AddOnSession.run(id: "terminal", handlers: handlers))
/// ```
///
/// The program runs as the person, with their access, like one started in Terminal. It starts on Ledge's first size
/// and again on the next key after it ends. What the person types goes to the program and nowhere else.
public final class AddOnTerminal: @unchecked Sendable {
    /// Where output goes. Ledge's terminal page, unless changed (tests read it here).
    public var onOutput: @Sendable (Data) -> Void = { AddOnSession.terminal(output: $0) }
    /// The program ended, with its exit status. Ledge is told by `connect`.
    public var onExit: @Sendable (Int32) -> Void = { _ in }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "LedgeKit.AddOnTerminal")
    private var master: Int32 = -1
    private var child: pid_t = 0
    private var reader: DispatchSourceRead?
    private var exitWatch: DispatchSourceProcess?
    private var lastSize: TerminalSize?
    private var lastFolder: String?
    private var session: AsyncStream<SessionMessage>.Continuation?

    public init() {}

    public var isRunning: Bool { lock.withLock { child > 0 } }
    /// The size Ledge last asked for.
    public var size: TerminalSize? { lock.withLock { lastSize } }

    /// The person's login shell, from their account: what Terminal starts.
    public static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    /// Starts `program` (the login shell, as a login shell, when nil) at `size`, in `directory` (home when nil).
    /// `environment` is added to the terminal's own: TERM, LANG, HOME, USER, SHELL, PATH and TMPDIR.
    public func start(size: TerminalSize, program: String? = nil, arguments: [String] = [],
                      directory: String? = nil, environment: [String: String] = [:]) throws {
        try size.validate()
        guard !isRunning else { throw AddOnError("The terminal's program is already running.") }
        let path = program ?? Self.loginShell
        // A login shell's name starts with a dash, as Terminal starts it: it reads .zprofile and path_helper's PATH.
        let name = program == nil ? "-" + (path as NSString).lastPathComponent : (path as NSString).lastPathComponent
        let folder = directory ?? NSHomeDirectory()

        var variables = Self.baseEnvironment(shell: Self.loginShell)
        for (key, value) in environment { variables[key] = value }
        let env = variables.map { "\($0.key)=\($0.value)" }.sorted()

        // Everything the child needs is made before fork: between fork and exec it may only make async-signal-safe
        // calls, so no Swift allocation there.
        let cPath = strdup(path)
        let cFolder = strdup(folder)
        let cArgs = ([name] + arguments).map { strdup($0) } + [nil]
        let cEnv = env.map { strdup($0) } + [nil]
        defer {
            free(cPath); free(cFolder)
            cArgs.forEach { free($0) }
            cEnv.forEach { free($0) }
        }
        var window = winsize(ws_row: UInt16(size.rows), ws_col: UInt16(size.columns), ws_xpixel: 0, ws_ypixel: 0)
        var defaultAction = sigaction()
        defaultAction.__sigaction_u.__sa_handler = SIG_DFL
        sigemptyset(&defaultAction.sa_mask)
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)

        var fd: Int32 = -1
        let pid = cArgs.withUnsafeBufferPointer { args in
            cEnv.withUnsafeBufferPointer { envp in
                forkpty(&fd, nil, nil, &window).withChild {
                    // The child: signals back to their defaults, then the program.
                    var number: Int32 = 1
                    while number < NSIG {
                        if number != SIGKILL && number != SIGSTOP { _ = sigaction(number, &defaultAction, nil) }
                        number += 1
                    }
                    _ = sigprocmask(SIG_SETMASK, &emptyMask, nil)
                    _ = chdir(cFolder)
                    _ = execve(cPath, args.baseAddress, envp.baseAddress)
                    _exit(127)
                }
            }
        }
        guard pid > 0, fd >= 0 else { throw AddOnError("The terminal couldn't start \(name).") }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)

        lock.withLock {
            master = fd
            child = pid
            lastSize = size
            lastFolder = nil
        }
        watch(fd: fd, pid: pid)
    }

    /// Writes what the person typed to the program.
    public func write(_ data: Data) {
        let fd = lock.withLock { master }
        guard fd >= 0, !data.isEmpty else { return }
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR || errno == EAGAIN {
                    usleep(1000)
                } else {
                    return
                }
            }
        }
    }

    /// Tells the program the terminal's new size.
    public func resize(_ size: TerminalSize) {
        guard (try? size.validate()) != nil else { return }
        let fd = lock.withLock { () -> Int32 in
            lastSize = size
            return master
        }
        guard fd >= 0 else { return }
        var window = winsize(ws_row: UInt16(size.rows), ws_col: UInt16(size.columns), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(fd, TIOCSWINSZ, &window)
    }

    /// Ends the program, as closing a Terminal window does: a hangup to it and everything it started.
    public func stop() {
        let pid = lock.withLock { child }
        guard pid > 0 else { return }
        kill(-pid, SIGHUP)
        kill(pid, SIGHUP)
    }

    /// The folder the program is in now, read from the process: shells don't say when they change folder.
    public var folder: String? {
        let pid = lock.withLock { child }
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    /// Answers Ledge's terminal requests with this terminal: it starts on the first size, again on the next key
    /// after the program ends, tells Ledge the folder after each Return, and stops when the add-on is turned off.
    /// `start` makes the program; by default the login shell at home.
    public func connect(_ handlers: inout AddOnHandlers,
                        start: @escaping @Sendable (AddOnTerminal, TerminalSize) async throws -> Void = { try $0.start(size: $1) }) {
        handlers.onTerminalResize = { [self] size in
            bind()
            if isRunning {
                resize(size)
            } else {
                try? await start(self, size)
                reportFolder()
            }
        }
        handlers.onTerminalInput = { [self] data in
            bind()
            if !isRunning, let size {
                try? await start(self, size)
                reportFolder()
                return
            }
            write(data)
            // A command may change folder: look once the shell has had a moment to run it.
            if data.contains(13) {
                queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.reportFolder() }
            }
        }
        let deactivate = handlers.deactivate
        handlers.deactivate = { [self] in
            stop()
            await deactivate()
        }
    }

    /// Sends output, the folder and the end of the program to the session that's talking to this terminal. Called
    /// from its requests, where that session is known; output comes from another thread, where it isn't.
    private func bind() {
        guard let outbox = AddOnSession.currentOutbox() else { return }
        lock.withLock { session = outbox }
        onOutput = { AddOnSession.send(terminalOutput: $0, to: outbox) }
        onExit = { _ in AddOnSession.send(terminalState: TerminalState(folder: nil, running: false), to: outbox) }
    }

    /// Tells Ledge the folder, when it changed.
    public func reportFolder() {
        guard let now = folder else { return }
        let changed = lock.withLock { () -> Bool in
            defer { lastFolder = now }
            return lastFolder != now
        }
        guard changed else { return }
        let state = TerminalState(folder: now, running: true)
        if let outbox = lock.withLock({ session }) {
            AddOnSession.send(terminalState: state, to: outbox)
        } else {
            AddOnSession.show(terminal: state)
        }
    }

    private func watch(fd: Int32, pid: pid_t) {
        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        reader.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                self?.onOutput(Data(buffer[0..<count]))
            } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
                // End of output: the program and everything holding the terminal are gone.
                reader.cancel()
            }
        }
        reader.setCancelHandler { close(fd) }
        let exitWatch = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        exitWatch.setEventHandler { [weak self] in
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            exitWatch.cancel()
            // Output still in the terminal is read before it's closed.
            self?.queue.asyncAfter(deadline: .now() + 0.1) {
                guard let self else { return }
                self.lock.withLock {
                    if self.child == pid {
                        self.child = 0
                        self.master = -1
                    }
                }
                self.reader?.cancel()
                let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
                self.onExit(code)
            }
        }
        lock.withLock {
            self.reader = reader
            self.exitWatch = exitWatch
        }
        reader.resume()
        exitWatch.resume()
    }

    static func baseEnvironment(shell: String) -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        var env = [
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "TERM_PROGRAM": "Ledge",
            "LANG": current["LANG"] ?? "en_US.UTF-8",
            "HOME": NSHomeDirectory(),
            "SHELL": shell,
            "PATH": current["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        for key in ["USER", "LOGNAME", "TMPDIR"] { if let value = current[key] { env[key] = value } }
        return env
    }
}

private extension pid_t {
    /// Runs `body` in the child of a fork, which never returns from it; the parent gets the pid.
    func withChild(_ body: () -> Never) -> pid_t {
        if self == 0 { body() }
        return self
    }
}
#endif
