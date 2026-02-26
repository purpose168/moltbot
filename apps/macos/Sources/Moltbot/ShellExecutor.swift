import MoltbotIPC
import Foundation

/// Shell 命令执行器
/// 提供执行 Shell 命令并捕获输出的功能
enum ShellExecutor {
    /// Shell 执行结果
    struct ShellResult {
        var stdout: String           // 标准输出
        var stderr: String           // 标准错误
        var exitCode: Int?          // 退出码
        var timedOut: Bool           // 是否超时
        var success: Bool            // 是否成功
        var errorMessage: String?     // 错误消息
    }

    /// 详细运行 Shell 命令
    /// - Parameters:
    ///   - command: 命令及其参数
    ///   - cwd: 工作目录
    ///   - env: 环境变量
    ///   - timeout: 超时时间（秒）
    /// - Returns: Shell 执行结果
    static func runDetailed(
        command: [String],
        cwd: String?,
        env: [String: String]?,
        timeout: Double?) async -> ShellResult
    {
        guard !command.isEmpty else {
            return ShellResult(
                stdout: "",
                stderr: "",
                exitCode: nil,
                timedOut: false,
                success: false,
                errorMessage: "空命令")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        if let env { process.environment = env }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ShellResult(
                stdout: "",
                stderr: "",
                exitCode: nil,
                timedOut: false,
                success: false,
                errorMessage: "failed to start: \(error.localizedDescription)")
        }

        let outTask = Task { stdoutPipe.fileHandleForReading.readToEndSafely() }
        let errTask = Task { stderrPipe.fileHandleForReading.readToEndSafely() }

        let waitTask = Task { () -> ShellResult in
            process.waitUntilExit()
            let out = await outTask.value
            let err = await errTask.value
            let status = Int(process.terminationStatus)
            return ShellResult(
                stdout: String(bytes: out, encoding: .utf8) ?? "",
                stderr: String(bytes: err, encoding: .utf8) ?? "",
                exitCode: status,
                timedOut: false,
                success: status == 0,
                errorMessage: status == 0 ? nil : "退出 \(status)")
        }

        if let timeout, timeout > 0 {
            let nanos = UInt64(timeout * 1_000_000_000)
            let result = await withTaskGroup(of: ShellResult.self) { group in
                group.addTask { await waitTask.value }
                group.addTask {
                    try? await Task.sleep(nanoseconds: nanos)
                    if process.isRunning { process.terminate() }
                    _ = await waitTask.value // drain pipes after termination
                    return ShellResult(
                        stdout: "",
                        stderr: "",
                        exitCode: nil,
                        timedOut: true,
                        success: false,
                        errorMessage: "超时")
                }
                let first = await group.next()!
                group.cancelAll()
                return first
            }
            return result
        }

        return await waitTask.value
    }

    /// 运行 Shell 命令并返回响应
    /// - Parameters:
    ///   - command: 命令及其参数
    ///   - cwd: 工作目录
    ///   - env: 环境变量
    ///   - timeout: 超时时间（秒）
    /// - Returns: IPC 响应
    static func run(command: [String], cwd: String?, env: [String: String]?, timeout: Double?) async -> Response {
        let result = await self.runDetailed(command: command, cwd: cwd, env: env, timeout: timeout)
        let combined = result.stdout.isEmpty ? result.stderr : result.stdout
        let payload = combined.isEmpty ? nil : Data(combined.utf8)
        return Response(ok: result.success, message: result.errorMessage, payload: payload)
    }
}
