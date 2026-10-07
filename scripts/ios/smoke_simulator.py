#!/usr/bin/env python3
"""Check iPad startup and retain a screenshot for human inspection."""
import json
from pathlib import Path
import subprocess
import time


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    data = json.loads(command('xcrun', 'simctl', 'list', 'devices',
                              'available', '--json'))
    candidates = [device for devices in data['devices'].values()
                  for device in devices if 'iPad' in device['name']]
    if not candidates:
        raise RuntimeError('No available iPad simulator on the runner')
    device = candidates[0]
    udid = device['udid']
    if device['state'] != 'Booted':
        subprocess.run(['xcrun', 'simctl', 'boot', udid], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], check=True)
    subprocess.run(['xcrun', 'simctl', 'install', udid,
                    'build/ios/iphonesimulator/Runner.app'], check=True)
    launch = command('xcrun', 'simctl', 'launch', udid, 'com.lxyveex.zaix')
    pid = launch.rsplit(':', 1)[1].strip()
    time.sleep(15)
    # Simulator applications are processes on the macOS host. A zero exit code
    # from simctl launch alone does not establish that startup succeeded.
    running = command('ps', '-p', pid, '-o', 'command=')
    if 'Runner.app/Runner' not in running:
        raise RuntimeError('The iPad app exited during startup')
    out = Path('dist/ios')
    out.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'simctl', 'io', udid, 'screenshot',
                    str(out / 'ipad-startup.png')], check=True)
    (out / 'simulator-check.json').write_text(json.dumps({
        'device': device['name'], 'launch': launch,
        'alive_after_seconds': 15,
        'scope': 'Startup only. Login, real-device reading, notifications and '
                 'photo permission still require device verification.'}, indent=2))
    print('iPad simulator stayed running; screenshot saved for inspection.')


if __name__ == '__main__':
    main()
