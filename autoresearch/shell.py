from __future__ import annotations

import os
import shlex
import shutil
import signal
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass(slots=True)
class CommandResult:
    returncode: int
    output: str


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def run_command(
    command: str | list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    timeout: int | None = None,
    shell: bool | None = None,
) -> CommandResult:
    use_shell = isinstance(command, str) if shell is None else shell
    completed = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        timeout=timeout,
        shell=use_shell,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        executable="/bin/bash" if use_shell else None,
    )
    return CommandResult(returncode=completed.returncode, output=completed.stdout or "")


def stream_command(
    command: str | list[str],
    *,
    cwd: Path,
    log_file: Path,
    env: dict[str, str] | None = None,
    timeout: int | None = None,
    shell: bool | None = None,
) -> CommandResult:
    use_shell = isinstance(command, str) if shell is None else shell
    log_file.parent.mkdir(parents=True, exist_ok=True)
    output_parts: list[str] = []
    start = time.monotonic()
    with log_file.open("w", encoding="utf-8") as handle:
        process = subprocess.Popen(
            command,
            cwd=cwd,
            env=env,
            shell=use_shell,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            executable="/bin/bash" if use_shell else None,
        )
        try:
            assert process.stdout is not None
            for line in process.stdout:
                print(line, end="")
                handle.write(line)
                handle.flush()
                output_parts.append(line)
                if timeout is not None and (time.monotonic() - start) > timeout:
                    raise subprocess.TimeoutExpired(command, timeout)
            returncode = process.wait()
        except subprocess.TimeoutExpired:
            terminate_process(process)
            timeout_output = "".join(output_parts)
            return CommandResult(returncode=124, output=timeout_output)
    return CommandResult(returncode=returncode, output="".join(output_parts))


def start_background_process(
    command: str,
    *,
    cwd: Path,
    output_file: Path,
    env: dict[str, str] | None = None,
) -> subprocess.Popen[str]:
    output_file.parent.mkdir(parents=True, exist_ok=True)
    handle = output_file.open("w", encoding="utf-8")
    return subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        shell=True,
        stdout=handle,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        start_new_session=True,
        executable="/bin/bash",
    )


def terminate_process(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            return
        process.wait(timeout=5)


def format_command(command: str | list[str]) -> str:
    if isinstance(command, str):
        return command
    return " ".join(shlex.quote(part) for part in command)
