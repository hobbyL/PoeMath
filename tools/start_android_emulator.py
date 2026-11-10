#!/usr/bin/env python3
"""使用当前网络的 DNS 冷启动开发模拟器，保留 App 和用户数据。"""

import argparse
import ipaddress
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time


def dns_addresses(values):
    result = []
    for value in values:
        try:
            address = ipaddress.ip_address(value.strip())
        except ValueError:
            continue
        if (address.is_loopback or address.is_unspecified
                or address.is_multicast or address.is_link_local):
            continue
        normalized = str(address)
        if normalized not in result:
            result.append(normalized)
    return result[:4]


def mac_dns(output):
    # scoped/supplemental resolver 属于特定网卡或域名，不能作为全局 DNS。
    default = output.split("DNS configuration (for scoped queries)", 1)[0]
    for resolver in re.split(r"(?m)^resolver #\d+", default)[1:]:
        if re.search(r"(?m)^\s*(domain\s*:|flags\s*:.*Supplemental)", resolver):
            continue
        addresses = dns_addresses(re.findall(
            r"(?m)^\s*nameserver\[\d+\]\s*:\s*(\S+)", resolver))
        if addresses:
            return addresses
    return []


def system_dns():
    if sys.platform == "darwin":
        output = subprocess.check_output(
            ["scutil", "--dns"], text=True, timeout=10)
        return mac_dns(output)
    return dns_addresses(re.findall(
        r"(?m)^nameserver\s+(\S+)", Path("/etc/resolv.conf").read_text()))


def sdk_directory():
    candidates = [os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT"),
                  str(Path.home() / "Library/Android/sdk"),
                  str(Path.home() / "Android/Sdk")]
    for candidate in candidates:
        if candidate and (Path(candidate) / "emulator/emulator").is_file():
            return Path(candidate)
    raise RuntimeError("找不到 Android SDK，请通过 ANDROID_HOME 指定 SDK 路径")


def connected_emulators(adb):
    output = subprocess.check_output([str(adb), "devices"], text=True, timeout=10)
    return [line.split() for line in output.splitlines()
            if line.startswith("emulator-") and len(line.split()) == 2]


def running_avd(adb, name):
    for serial, state in connected_emulators(adb):
        if state != "device":
            raise RuntimeError("有模拟器处于离线状态，请等开机完成后重试")
        output = subprocess.check_output(
            [str(adb), "-s", serial, "emu", "avd", "name"], text=True, timeout=10)
        if output.splitlines()[0].strip() == name:
            return serial
    return None


def restart_avd(adb, serial):
    subprocess.run([str(adb), "-s", serial, "emu", "kill"],
                   check=True, timeout=10, capture_output=True)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if not any(device == serial for device, _ in connected_emulators(adb)):
            return
        time.sleep(0.5)
    raise RuntimeError("模拟器尚未退出，请稍后重试；未启动新进程")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--avd", default="Medium_Phone_API_37.0")
    parser.add_argument("--dns", help="指定当前网络可用的 DNS IP，逗号分隔，最多 4 个")
    parser.add_argument("--restart", action="store_true", help="重启同名的现有模拟器")
    parser.add_argument("--dry-run", action="store_true", help="只显示启动命令")
    args = parser.parse_args()
    try:
        sdk = sdk_directory()
        if args.dns is not None:
            entries = args.dns.split(",")
            addresses = dns_addresses(entries)
            if not 1 <= len(entries) <= 4 or len(addresses) != len(entries):
                raise RuntimeError("--dns 需要 1–4 个不重复的可访问 DNS IP，不能使用回环地址")
        else:
            addresses = system_dns()
        if not addresses:
            raise RuntimeError("未找到可供模拟器访问的 DNS，请用 --dns 指定当前网络的 DNS IP")
        command = [str(sdk / "emulator/emulator"), "-avd", args.avd,
                   "-dns-server", ",".join(addresses),
                   "-no-snapshot-load", "-no-snapshot-save",
                   "-gpu", "host", "-cores", "4", "-memory", "4096"]
        print(shlex.join(command), flush=True)
        if args.dry_run:
            return 0
        adb = sdk / "platform-tools/adb"
        serial = running_avd(adb, args.avd)
        if serial:
            if not args.restart:
                print(f"{args.avd} 已运行；应用新的 DNS 请添加 --restart。")
                return 0
            print(f"正在重启 {args.avd}，保留应用数据…", flush=True)
            restart_avd(adb, serial)
        log = Path(__file__).resolve().parent.parent / "build/android-emulator.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                       start_new_session=True)
        time.sleep(1)
        if process.poll() is not None:
            raise RuntimeError(f"模拟器启动失败，请查看 {log}")
        print(f"模拟器已启动（PID {process.pid}），日志：{log}")
        print("等待 adb shell getprop sys.boot_completed 返回 1 后，再运行 Flutter。")
        return 0
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        print(f"启动失败：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
