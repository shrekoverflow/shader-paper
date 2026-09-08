#!/usr/bin/env python3
"""Install a rendered movie in macOS's private per-user aerial catalogue.

The manifest schema was checked against macOS 26 and CaveWall's
SystemAerialRegistrar (https://github.com/Vahsir7/cavewall). This registers our
own asset; it never substitutes media for Apple's assets or adds a background
process. Selecting the asset in System Settings lets macOS write its own linked
wallpaper/screensaver configuration.
"""
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile
import uuid

CATEGORY = 'DA08A18D-0F49-41DB-BFA7-1918351A2B25'
SUBCATEGORY = '9F146B47-16AB-4327-8D54-7DDD9443D3A1'
NAMESPACE = uuid.UUID('11a67906-2a47-47e2-894b-c81c15da485a')


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, path.stat().st_mode & 0o777 if path.exists() else 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def json_bytes(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode()


def read_manifest(path):
    result = json.loads(path.read_bytes())
    if not isinstance(result.get('assets'), list) or not isinstance(result.get('categories'), list):
        raise ValueError('Unrecognized aerial manifest; left unchanged.')
    return result


def validate_movie(path):
    validator = Path(__file__).resolve().parent.parent / 'build/aerial/validate-aerial'
    if not validator.is_file():
        raise ValueError('Build the aerial tools first; the temporal-metadata validator is missing.')
    result = subprocess.run([str(validator), str(path)], capture_output=True, text=True)
    if result.returncode != 0:
        raise ValueError('Movie is not compatible with the native unlock transition.\n' + result.stdout + result.stderr)


def add_asset(manifest, asset_id, video, thumbnail):
    result = copy.deepcopy(manifest)
    result['categories'] = [c for c in result['categories'] if c.get('id') != CATEGORY]
    result['assets'] = [a for a in result['assets'] if SUBCATEGORY not in a.get('subcategories', [])]
    result['categories'].append({
        'id': CATEGORY, 'localizedNameKey': 'Almost a Shape',
        'localizedDescriptionKey': 'A visual meditation by GPT6 Astra',
        'previewImage': thumbnail.as_uri(), 'representativeAssetID': asset_id,
        'preferredOrder': 99,
        'subcategories': [{
            'id': SUBCATEGORY, 'localizedNameKey': 'Almost a Shape',
            'localizedDescriptionKey': 'Ivory, graphite, and vermilion',
            'previewImage': thumbnail.as_uri(), 'representativeAssetID': asset_id,
            'preferredOrder': 0,
        }],
    })
    result['assets'].append({
        'id': asset_id, 'shotID': 'ALMOST_A_SHAPE_ASTRA_II',
        'localizedNameKey': 'Almost a Shape', 'accessibilityLabel': 'Almost a Shape',
        'previewImage': thumbnail.as_uri(), 'previewImage-900x580': thumbnail.as_uri(),
        'url-4K-SDR-240FPS': video.as_uri(),
        'categories': [CATEGORY], 'subcategories': [SUBCATEGORY],
        'includeInShuffle': False, 'showInTopLevel': True, 'preferredOrder': 0,
        'pointsOfInterest': {'0': 'Almost a Shape'},
    })
    return result


def selected_assets(value):
    result = set()
    if isinstance(value, dict):
        if value.get('Provider') == 'com.apple.wallpaper.choice.aerials':
            configuration = value.get('Configuration', b'')
            if configuration:
                asset = plistlib.loads(configuration).get('assetID')
                if asset:
                    result.add(asset)
        for child in value.values():
            result.update(selected_assets(child))
    elif isinstance(value, list):
        for child in value:
            result.update(selected_assets(child))
    return result


def refresh():
    # Only terminate this user's wallpaper processes. launchd restarts them;
    # neither WindowServer nor the user's other applications are touched.
    for name in ('WallpaperAgent', 'WallpaperAerialsExtension'):
        found = subprocess.run(['/usr/bin/pgrep', '-u', str(os.getuid()), '-x', name],
                               capture_output=True, text=True)
        for text in found.stdout.split():
            try:
                os.kill(int(text), signal.SIGTERM)
            except ProcessLookupError:
                pass


def install(args, root, support):
    movie = Path(args.movie).resolve(strict=True)
    poster = Path(args.poster).resolve(strict=True)
    manifest_path = root / 'aerials/manifest/entries.json'
    index_path = root / 'Store/Index.plist'
    original = manifest_path.read_bytes()
    manifest = read_manifest(manifest_path)
    plistlib.loads(index_path.read_bytes())
    validate_movie(movie)
    with movie.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    asset_id = str(uuid.uuid5(NAMESPACE, digest)).upper()
    video = root / f'aerials/videos/{asset_id}.mov'
    thumbnail = root / f'aerials/thumbnails/{asset_id}.png'
    receipt_path = support / 'receipt.json'
    if receipt_path.exists():
        receipt = json.loads(receipt_path.read_bytes())
        if receipt['assetID'] != asset_id:
            if not getattr(args, 'replace', False):
                raise ValueError('Use --replace to update the movie while retaining the original wallpaper backup.')
            atomic_write(support / 'history' / (receipt['assetID'] + '.json'), json_bytes(receipt))
            receipt = {**receipt, 'assetID': asset_id, 'sha256': digest,
                       'video': str(video), 'thumbnail': str(thumbnail)}
    else:
        backup = support / 'backups' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
        backup.mkdir(parents=True, exist_ok=False)
        shutil.copy2(manifest_path, backup / 'entries.json')
        shutil.copy2(index_path, backup / 'Index.plist')
        receipt = {'assetID': asset_id, 'sha256': digest, 'backup': str(backup),
                   'video': str(video), 'thumbnail': str(thumbnail)}
    video.parent.mkdir(parents=True, exist_ok=True)
    if video.exists():
        with video.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != digest:
                raise ValueError('Installed media differs from the receipt; left unchanged.')
    else:
        staging = video.with_suffix('.staging.mov')
        shutil.copy2(movie, staging)
        os.replace(staging, video)
    atomic_write(thumbnail, poster.read_bytes())
    # Refuse to overwrite an independently refreshed catalogue during copying.
    if manifest_path.read_bytes() != original:
        raise ValueError('macOS updated the catalogue during installation. Run install again to merge with its latest version.')
    updated = add_asset(manifest, asset_id, video, thumbnail)
    atomic_write(manifest_path, json_bytes(updated))
    atomic_write(receipt_path, json_bytes(receipt))
    refresh()
    print('Registered Almost a Shape as a native aerial.')
    print('Asset:', asset_id)
    print('Backup:', receipt['backup'])
    print('Choose Almost a Shape in System Settings → Wallpaper to activate it.')


def restore(args, root, support):
    receipt_path = support / 'receipt.json'
    receipt = json.loads(receipt_path.read_bytes())
    index_path = root / 'Store/Index.plist'
    current = plistlib.loads(index_path.read_bytes())
    if receipt['assetID'] in selected_assets(current):
        # Capture any subsequent selections too, before restoring the original.
        backup_current = support / 'before-restore.plist'
        atomic_write(backup_current, index_path.read_bytes())
        restore_settings(index_path, Path(receipt['backup']) / 'Index.plist', receipt['assetID'])
    manifest_path = root / 'aerials/manifest/entries.json'
    manifest = read_manifest(manifest_path)
    manifest['categories'] = [c for c in manifest['categories'] if c.get('id') != CATEGORY]
    manifest['assets'] = [a for a in manifest['assets'] if SUBCATEGORY not in a.get('subcategories', [])]
    atomic_write(manifest_path, json_bytes(manifest))
    refresh()
    # Keep the small receipt and media for recovery instead of deleting a file
    # that an aerial decoder might still have open. Remove the active receipt.
    receipt_path.rename(support / 'restored-receipt.json')
    print('Removed Almost a Shape from the catalogue; original settings restored if it was active.')
    print('Backup retained:', receipt['backup'])


def restore_settings(index_path, backup_path, asset_id):
    previous = plistlib.loads(backup_path.read_bytes())
    def transform(current):
        # Preserve selections on any displays/Spaces changed since installation.
        def restore_branch(now, before):
            if isinstance(now, dict):
                if now.get('Type') in ('linked', 'individual') and asset_id in selected_assets(now):
                    return copy.deepcopy(before)
                return {key: restore_branch(value, before.get(key, {}) if isinstance(before, dict) else {})
                        for key, value in now.items()}
            return now
        return restore_branch(current, previous)
    update_settings(index_path, transform)


def linked_settings(current, asset_id):
    result = copy.deepcopy(current)
    configuration = plistlib.dumps({'assetID': asset_id}, fmt=plistlib.FMT_BINARY)
    options = plistlib.dumps({'values': {'placement': {'picker': {'_0': {'id': 'FillScreen'}}}}},
                              fmt=plistlib.FMT_BINARY)
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    container = {'Type': 'linked', 'Linked': {'LastSet': now, 'LastUse': now, 'Content': {
        'Choices': [{'Provider': 'com.apple.wallpaper.choice.aerials', 'Files': [],
                     'Configuration': configuration}],
        'Shuffle': '$null', 'EncodedOptionValues': options}}}
    result['AllSpacesAndDisplays'] = copy.deepcopy(container)
    result['SystemDefault'] = copy.deepcopy(container)
    result['Displays'] = {}
    result['Spaces'] = {}
    return result


def activate(args, root, support):
    receipt = json.loads((support / 'receipt.json').read_bytes())
    manifest = read_manifest(root / 'aerials/manifest/entries.json')
    if not any(a.get('id') == receipt['assetID'] for a in manifest['assets']):
        raise ValueError('Aerial registration is missing; run install again first.')
    if not Path(receipt['video']).is_file():
        raise ValueError('The registered movie is missing.')
    index = root / 'Store/Index.plist'
    plistlib.loads(index.read_bytes())
    atomic_write(support / 'before-activate.plist', index.read_bytes())
    update_settings(index, lambda current: linked_settings(current, receipt['assetID']))
    refresh()
    print('Activated Almost a Shape for desktop and screen saver on all Spaces and displays.')


def update_settings(index_path, transform):
    # Suspend only this user's agent across the atomic edit, then restart it
    # without allowing its old in-memory settings to flush over the restored
    # file. If the write fails, resume it instead. No daemon remains suspended.
    found = subprocess.run(['/usr/bin/pgrep', '-u', str(os.getuid()), '-x', 'WallpaperAgent'],
                           capture_output=True, text=True)
    suspended = []
    committed = False
    try:
        for text in found.stdout.split():
            try:
                pid = int(text)
                os.kill(pid, signal.SIGSTOP)
                suspended.append(pid)
            except ProcessLookupError:
                pass
        current = plistlib.loads(index_path.read_bytes())
        restored = transform(current)
        atomic_write(index_path, plistlib.dumps(restored, fmt=plistlib.FMT_BINARY))
        committed = True
    finally:
        for pid in suspended:
            try:
                os.kill(pid, signal.SIGKILL if committed else signal.SIGCONT)
            except ProcessLookupError:
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    add = commands.add_parser('install')
    add.add_argument('movie')
    add.add_argument('poster')
    add.add_argument('--replace', action='store_true', help='Replace our movie, keeping the original settings backup')
    commands.add_parser('restore')
    commands.add_parser('activate')
    args = parser.parse_args()
    library = Path.home() / 'Library/Application Support'
    root = library / 'com.apple.wallpaper'
    support = library / 'Almost a Shape/Aerial'
    try:
        {'install': install, 'restore': restore, 'activate': activate}[args.command](args, root, support)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
