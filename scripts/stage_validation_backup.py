"""Copy the actual UI export into disposable Simulator Files storage.

iOS 27.2's simulator can fail to enumerate FILocalAppContainerNode with nilError.
Use Files' general storage for the import source, without replacing file-picker
selection, the exporter, its bytes, the importer, or any review/apply action.
"""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import time


def container(device, bundle, kind):
    return Path(subprocess.check_output(
        ['xcrun', 'simctl', 'get_app_container', device, bundle, kind],
        text=True, stderr=subprocess.PIPE, timeout=15).strip())


def files_storage_group(device, app):
    # On some runtimes this group belongs to the LocalStorage provider rather
    # than DocumentsApp, so get_app_container's specific-group lookup rejects
    # it. Resolve only that exact group's metadata inside our owned simulator.
    data = next((parent for parent in app.parents
                if parent.name == 'data' and parent.parent.name == device), None)
    if data is None:
        raise ValueError(f'App container {app} is outside simulator {device}')
    groups = data / 'Containers/Shared/AppGroup'
    identifiers = []
    for metadata in groups.glob('*/.com.apple.mobile_container_manager.metadata.plist'):
        with metadata.open('rb') as stream:
            identifier = plistlib.load(stream).get('MCMMetadataIdentifier', '')
        if 'FileProvider' in identifier or 'Documents' in identifier:
            identifiers.append(identifier)
        if identifier == 'group.com.apple.FileProvider.LocalStorage':
            return metadata.parent
    raise FileNotFoundError(f'LocalStorage group not initialized; document groups: {identifiers}')


def main():
    device = os.environ['VALIDATION_SIMULATOR']
    evidence = Path('.build/simulator-evidence')
    deadline = time.monotonic() + 1800
    last_error = None
    while time.monotonic() < deadline:
        try:
            app = container(device, 'com.n3mostudio.elsepin.validation', 'data')
            files = list((app / 'Documents').rglob('Elsepin-Settings*.json'))
            if not files:
                time.sleep(1)
                continue
            source = files[0]
            payload = source.read_bytes()
            backup = json.loads(payload)
            if backup.get('categories') != ['settings'] or backup.get('places') or backup.get('trips'):
                raise ValueError('Expected only the disposable settings export')
            group = files_storage_group(device, app)
            # Refuse any path outside this owned, disposable simulator.
            if device not in group.parts or 'AppGroup' not in group.parts:
                raise ValueError('Files group is outside the disposable simulator')
            destination = group / 'File Provider Storage' / 'Elsepin-Settings.json'
            destination.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['rsync', '-a', '--', str(source), str(destination)], check=True, timeout=20)
            if destination.read_bytes() != payload:
                raise ValueError('Transferred export bytes differ')
            receipt = {'actualUIExport': True, 'identicalBytes': True, 'bytes': len(payload),
                       'source': 'validation app Documents', 'destination': 'On My iPhone/Elsepin-Settings.json'}
            (evidence / 'files-staging.json').write_text(json.dumps(receipt, indent=2))
            (evidence / 'staged-settings-export.json').write_bytes(payload)
            (app / 'Documents/.validation-files-ready').write_text('ready')
            print('Actual settings export copied to disposable Files storage; bytes verified.', flush=True)
            return
        except (subprocess.SubprocessError, OSError, ValueError) as error:
            # Files' group may not exist until its first native presentation.
            message = str(error)
            if isinstance(error, subprocess.CalledProcessError):
                message += ': ' + (error.stderr or '')[:500]
            if message != last_error:
                print(message, flush=True)
            last_error = message
            time.sleep(5)
    raise RuntimeError(f'Timed out staging the actual UI export: {last_error}')


if __name__ == '__main__':
    main()
