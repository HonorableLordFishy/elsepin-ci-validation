"""Create a fresh CI-only simulator, retaining toolchain inventory as evidence."""
import json
import os
from pathlib import Path
import subprocess

def run(*args):
    return subprocess.check_output(args, text=True).strip()

def choose_destination(data, sdk_version, requested_version=None):
    candidates = []
    for runtime in data['runtimes']:
        if not runtime.get('isAvailable') or '.iOS-' not in runtime['identifier']:
            continue
        if requested_version and runtime['version'] != requested_version:
            continue
        supported = [t for t in runtime.get('supportedDeviceTypes', [])
                     if t.get('productFamily') == 'iPhone']
        if not supported:
            continue
        # Prefer a small portrait phone over a device-specific Duo runtime.
        # SDK and runtime minor versions need not match for this iOS 18+ app.
        preferred = ['iPhone 17', 'iPhone SE (3rd generation)', 'iPhone 13 mini']
        device_type = next((t for name in preferred for t in supported if t['name'] == name), supported[0])
        version = tuple(int(v) for v in runtime['version'].split('.'))
        portrait = device_type['name'] in preferred
        # Use the newest general-purpose runtime. The older 27.0 image stalled
        # during boot on fresh runners; a newer runtime can run this SDK's app.
        # Still avoid a device-specific runtime when a regular iPhone exists.
        candidates.append(((portrait, version), runtime, device_type))
    if not candidates:
        raise RuntimeError('No available iOS runtime with a supported iPhone device type'
                           + (f' for requested version {requested_version}' if requested_version else ''))
    _, runtime, device_type = max(candidates, key=lambda candidate: candidate[0])
    return runtime, device_type

def main():
    evidence = Path('.build/simulator-evidence')
    evidence.mkdir(parents=True, exist_ok=True)
    inventory = run('xcrun', 'simctl', 'list', '--json')
    (evidence / 'simulator-inventory.json').write_text(inventory)
    sdk = run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version')
    runtime, device_type = choose_destination(json.loads(inventory), sdk,
                                             os.environ.get('VALIDATION_RUNTIME_VERSION'))
    device = run('xcrun', 'simctl', 'create', 'Elsepin disposable validation', device_type['identifier'], runtime['identifier'])
    with open(os.environ['GITHUB_ENV'], 'a') as env:
        env.write('VALIDATION_SIMULATOR=' + device + '\n')
    # Compile before boot so the simulator does not compete for compiler memory.
    print(f"Validation simulator: {device_type['name']}, {runtime['name']}, SDK {sdk}; disposable data only")

if __name__ == '__main__':
    main()
