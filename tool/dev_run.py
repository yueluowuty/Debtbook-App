"""本地调试回路：改 lib/ 下的 Dart 代码，自动热重载到安卓设备。

为什么需要这个脚本，而不是直接敲 `flutter run`：

1. 项目目录含中文，安卓侧 NDK/CMake 构建会失败，所以构建必须在 ASCII 镜像目录
   （默认 D:\\projects\\debtbook）里做。镜像的 lib 是一个目录联接，指向本仓库的
   lib，所以改这里就是改那边，不需要任何同步步骤。
2. `flutter run` 的热重载靠按键盘 r，非交互环境下拿不到 TTY；这里走
   `flutter run --machine` 协议，用 app.restart 触发同样的重载。
   注意协议帧格式：每行是一个 JSON **数组**，发裸对象不会有任何回包。

用法：
    D:/apps/flutter_windows_3.47.2-stable/flutter/bin/dart.bat --version  # 确认 SDK 在
    python tool/dev_run.py                    # 默认设备 emulator-5554
    python tool/dev_run.py --device <serial>  # 指定设备
    python tool/dev_run.py --once             # 只启动，不驻留监听

日志实时写到 tool/dev_run.log。Ctrl+C 退出。
"""

import argparse
import json
import os
import socket
import subprocess
import sys
import threading
import time

FLUTTER_BAT = r"D:\apps\flutter_windows_3.47.2-stable\flutter\bin\flutter.bat"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIRROR = os.environ.get("DEBTBOOK_MIRROR", r"D:\projects\debtbook")
WATCH_DIRS = ["lib", "pubspec.yaml"]
POLL_SECONDS = 0.4


class Log:
    def __init__(self, path):
        self.f = open(path, "a", encoding="utf-8", buffering=1)

    def __call__(self, msg):
        stamp = time.strftime("%H:%M:%S")
        line = "[%s] %s" % (stamp, msg)
        print(line, flush=True)
        self.f.write(line + "\n")


def snapshot_mtime():
    """被监视文件的最新修改时间。改一处就足以触发重载。"""
    newest = 0
    for entry in WATCH_DIRS:
        root = os.path.join(REPO, entry)
        if os.path.isfile(root):
            newest = max(newest, os.path.getmtime(root))
            continue
        for dirpath, _, filenames in os.walk(root):
            for name in filenames:
                if name.endswith(".dart"):
                    newest = max(newest, os.path.getmtime(os.path.join(dirpath, name)))
    return newest


class FlutterMachine:
    """`flutter run --machine` 的一个会话：自动启动 App，之后按需热重载。"""

    def __init__(self, device, log):
        self.log = log
        self.proc = subprocess.Popen(
            [FLUTTER_BAT, "run", "--machine", "-d", device],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            cwd=MIRROR,
        )
        self.app_id = None
        self.started = threading.Event()
        self._next_id = 0
        threading.Thread(target=self._read_loop, daemon=True).start()

    def _read_loop(self):
        for raw in self.proc.stdout:
            raw = raw.strip()
            if not raw:
                continue
            try:
                messages = json.loads(raw)
            except ValueError:
                # 构建输出、logcat 之类都是纯文本，原样转出去。
                self.log(raw)
                continue
            if isinstance(messages, dict):
                messages = [messages]
            for m in messages:
                if not isinstance(m, dict):
                    continue
                self._dispatch(m)
        code = self.proc.poll()
        self.log("flutter 进程已结束 rc=%s" % code)
        self.started.set()

    def _dispatch(self, m):
        event = m.get("event")
        params = m.get("params") or {}
        if event == "app.started":
            self.app_id = params.get("appId")
            self.log("App 已启动，appId=%s（改 lib/*.dart 即热重载）" % self.app_id)
            self.started.set()
        elif event == "app.log":
            self.log(params.get("log", "").rstrip())
        elif event == "app.stop":
            self.log("App 已停止：%s" % params.get("error", ""))
        elif event and event.startswith("app.progress"):
            msg = params.get("message", "")
            if msg:
                self.log("… %s" % msg)
        elif "result" in m or "error" in m:
            self.log("RESP %s" % json.dumps(m)[:300])

    def _send(self, method, params):
        self._next_id += 1
        frame = json.dumps([{"id": self._next_id, "method": method, "params": params}])
        try:
            self.proc.stdin.write(frame + "\n")
            self.proc.stdin.flush()
        except (BrokenPipeError, ValueError):
            self.log("管道已断，无法发送 %s" % method)
            return False
        return True

    def restart(self, full=False):
        if not self.app_id:
            self.log("还没有 appId，跳过热重载")
            return False
        kind = "hot-reset" if full else "hot-reload"
        self._send(
            "app.restart",
            {
                "appId": self.app_id,
                "fullRestart": full,
                "quiet": False,
                "reason": kind,
            },
        )
        return True

    def stop(self):
        if self.app_id:
            self._send("app.stop", {"appId": self.app_id})
        time.sleep(2)
        self.proc.kill()


def port_open(serial):
    """emulator-5554 -> 检查 5555 控制台端口，判断设备是否在跑。"""
    try:
        port = int(serial.split("-")[1]) + 1
    except (IndexError, ValueError):
        return True  # 真机序列号没有这个规律，交给 flutter 自己判断
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex(("127.0.0.1", port)) == 0


def main():
    global MIRROR
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default="emulator-5554")
    ap.add_argument("--mirror", default=MIRROR)
    ap.add_argument("--once", action="store_true", help="只启动，不驻留监听")
    ap.add_argument("--full", action="store_true", help="改动后用 hot restart 而非 hot reload")
    args = ap.parse_args()

    MIRROR = args.mirror
    log = Log(os.path.join(REPO, "tool", "dev_run.log"))

    if not os.path.isdir(os.path.join(MIRROR, "android")):
        log("镜像目录不对：%s 下没有 android/" % MIRROR)
        return 2
    if not port_open(args.device):
        log("设备 %s 没在跑。先启动模拟器：\n  %s" % (
            args.device,
            r"D:\Android\sdk\emulator\emulator.exe -avd debtbook -gpu host -no-snapshot-save"))
        return 2

    log("仓库=%s  构建目录=%s  设备=%s" % (REPO, MIRROR, args.device))
    session = FlutterMachine(args.device, log)
    if not session.started.wait(timeout=600):
        log("10 分钟内没等到 app.started，看上面的构建输出")
        session.stop()
        return 1
    if args.once:
        session.stop()
        return 0

    stamp = snapshot_mtime()
    log("开始监听 lib/ 与 pubspec.yaml（Ctrl+C 退出）")
    try:
        while True:
            time.sleep(POLL_SECONDS)
            now = snapshot_mtime()
            if now == stamp:
                continue
            stamp = now
            time.sleep(0.3)  # 编辑器常常连着写好几次，稍等再重载
            log("检测到改动 → %s" % ("hot restart" if args.full else "hot reload"))
            session.restart(full=args.full)
            stamp = snapshot_mtime()
    except KeyboardInterrupt:
        log("收到 Ctrl+C，收尾")
    finally:
        session.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
