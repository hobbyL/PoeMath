"""DNS 选择和模拟器重启范围的回归检查，不启动真实设备。"""

from pathlib import Path
import unittest
from unittest.mock import patch

if __package__:
    from . import start_android_emulator as launcher
else:
    import start_android_emulator as launcher


class EmulatorTest(unittest.TestCase):
    def test_default_dns_excludes_split_domains_and_scoped_resolvers(self):
        output = """DNS configuration
resolver #1
  domain : internal.example
  nameserver[0] : 10.8.0.1
resolver #2
  search domain[0] : lan
  nameserver[0] : 192.168.110.1
  nameserver[1] : 192.168.110.1
  nameserver[2] : 192.168.110.2
DNS configuration (for scoped queries)
resolver #1
  nameserver[0] : 10.9.0.1
"""
        self.assertEqual(launcher.mac_dns(output),
                         ["192.168.110.1", "192.168.110.2"])

    def test_unusable_host_addresses_are_not_given_to_guest(self):
        self.assertEqual(launcher.dns_addresses(
            ["127.0.0.53", "::1", "fe80::1%en0", "0.0.0.0", "224.0.0.1",
             "not-an-ip", "192.168.110.1"]), ["192.168.110.1"])
        self.assertEqual(launcher.mac_dns("DNS configuration\nresolver #1\n"
                                         " domain : local\n nameserver[0] : 10.0.0.1"), [])

    def test_running_lookup_ignores_different_avd(self):
        with patch.object(launcher, "connected_emulators", return_value=[
                ("emulator-5554", "device"), ("emulator-5556", "device")]), \
                patch.object(launcher.subprocess, "check_output", side_effect=[
                    "Other_AVD\nOK\n", "Target_AVD\nOK\n"]):
            self.assertEqual(launcher.running_avd(Path("adb"), "Target_AVD"),
                             "emulator-5556")

    def test_restart_only_stops_target_without_wiping_data(self):
        with patch.object(launcher.subprocess, "run") as run, \
                patch.object(launcher, "connected_emulators",
                             return_value=[("emulator-5554", "device")]):
            launcher.restart_avd(Path("adb"), "emulator-5556")
            self.assertEqual(run.call_args.args[0],
                             ["adb", "-s", "emulator-5556", "emu", "kill"])


if __name__ == "__main__":
    unittest.main()
