"""Exercise the CI install/attach boundary without a real emulator."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().with_name("run_android_integration.sh")
FAKE_TOOL = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path

name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open('commands.jsonl', 'a') as log:
    log.write(json.dumps([name, *args]) + '\n')
scenario = os.environ['SCENARIO']
if name == 'timeout':
    args = args[2:]
    if scenario == 'install_timeout' and 'install' in args:
        sys.exit(124)
    if scenario == 'driver_timeout' and args[0] == 'flutter':
        sys.exit(124)
    os.execvp(args[0], args)
if name == 'adb':
    if args[:2] == ['-s', 'emulator-5560']:
        args = args[2:]
    if args == ['shell', 'pm', 'path', 'android']:
        print('package:/system/framework/framework-res.apk')
    elif args and args[0] == 'install':
        if '--no-streaming' not in args:
            sys.exit('Streamed installation must never be used')
        print('Failure [INSTALL_FAILED_INVALID_APK]' if scenario == 'install_rejected' else 'Success')
        sys.exit(7 if scenario == 'install_failed' else 0)
    elif args[:3] == ['shell', 'am', 'start']:
        print('Error type 3' if scenario == 'launch_failed' else 'Status: ok')
    elif args[:2] == ['logcat', '-d'] and '-s' in args:
        print('I/flutter (123): The Dart VM service is listening on http://127.0.0.1:39123/test-token=/')
    elif args == ['forward', 'tcp:0', 'tcp:39123']:
        print('not-a-port' if scenario == 'bad_forward' else '45678')
    elif scenario == 'diagnostic_failed' and 'getprop' in args:
        sys.exit(9)
    else:
        print('diagnostic')
elif name == 'flutter':
    assert args[0] == 'drive', args
    assert '--use-existing-app=http://127.0.0.1:45678/test-token=/' in args, args
    assert '--driver=test_driver/app_journeys_driver.dart' in args, args
    assert args[args.index('-d') + 1] == 'emulator-5560', args
    print('Driver result')
    sys.exit(8 if scenario in ('driver_failed', 'diagnostic_failed') else 0)
'''


class AndroidIntegrationCiTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        for name in ('timeout', 'adb', 'flutter', 'free'):
            command = bin_dir / name
            command.write_text(FAKE_TOOL, encoding='utf-8')
            command.chmod(0o700)
        self.env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                        ANDROID_SERIAL='emulator-5560')
        apk = self.root / 'build/app/outputs/flutter-apk/app-debug.apk'
        apk.parent.mkdir(parents=True)
        apk.write_bytes(b'fixture')

    def run_scenario(self, scenario):
        (self.root / 'commands.jsonl').write_text('', encoding='utf-8')
        result = subprocess.run(['bash', str(SCRIPT)], cwd=self.root,
                                env=dict(self.env, SCENARIO=scenario),
                                capture_output=True, text=True, timeout=15)
        calls = [json.loads(line) for line in
                 (self.root / 'commands.jsonl').read_text().splitlines()]
        self.assertTrue((self.root / 'build/test-results/android-integration/logcat.txt').exists())
        return result, calls

    def test_installs_once_then_attaches_with_auth_token_and_cleans_forward(self):
        result, calls = self.run_scenario('success')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        installs = [call for call in calls if call[0] == 'adb' and 'install' in call]
        self.assertEqual(installs, [[
            'adb', '-s', 'emulator-5560', 'install', '--no-streaming', '-t', '-r',
            'build/app/outputs/flutter-apk/app-debug.apk',
        ]])
        driver = next(i for i, call in enumerate(calls) if call[0] == 'flutter')
        install = calls.index(installs[0])
        launch = next(i for i, call in enumerate(calls) if call[:5] ==
                      ['adb', '-s', 'emulator-5560', 'shell', 'am'] and 'start' in call)
        self.assertLess(install, launch)
        self.assertLess(launch, driver)
        self.assertIn(['adb', '-s', 'emulator-5560', 'forward', '--remove', 'tcp:45678'], calls)
        self.assertNotIn('disable-service-auth-codes', str(calls))
        self.assertFalse(any('uninstall' in call for call in calls))

    def test_install_failure_or_timeout_never_launches_app(self):
        for scenario, expected in [('install_failed', 7), ('install_rejected', 1),
                                   ('install_timeout', 124)]:
            with self.subTest(scenario=scenario):
                result, calls = self.run_scenario(scenario)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assertFalse(any(call[0] == 'flutter' for call in calls))
                self.assertFalse(any(call[0] == 'adb' and 'start' in call for call in calls))

    def test_launch_or_port_failure_never_runs_driver(self):
        for scenario in ['launch_failed', 'bad_forward']:
            with self.subTest(scenario=scenario):
                result, calls = self.run_scenario(scenario)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertFalse(any(call[0] == 'flutter' for call in calls))

    def test_driver_failure_and_timeout_survive_diagnostics(self):
        for scenario, expected in [('driver_failed', 8), ('driver_timeout', 124),
                                   ('diagnostic_failed', 8)]:
            with self.subTest(scenario=scenario):
                result, calls = self.run_scenario(scenario)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assertIn(['adb', '-s', 'emulator-5560', 'forward', '--remove', 'tcp:45678'], calls)


if __name__ == '__main__':
    unittest.main()
