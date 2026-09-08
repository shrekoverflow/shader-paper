import argparse
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

import catalog


class CatalogueTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'wallpaper with spaces'
        self.support = self.base / 'support'
        self.manifest = self.root / 'aerials/manifest/entries.json'
        self.index = self.root / 'Store/Index.plist'
        self.original_manifest = {'version': 17, 'categories': [{'id': 'apple'}],
                                 'assets': [{'id': 'existing', 'categories': ['apple']}],
                                 'unrecognizedFutureKey': {'keep': True}}
        self.original_index = {'AllSpacesAndDisplays': {'Type': 'individual',
            'Desktop': {'Content': {'Choices': [{'Provider': 'com.apple.wallpaper.choice.image'}]}}},
            'Displays': {}, 'Spaces': {}}
        catalog.atomic_write(self.manifest, catalog.json_bytes(self.original_manifest))
        catalog.atomic_write(self.index, plistlib.dumps(self.original_index))
        self.movie = self.base / 'movie.mov'
        self.poster = self.base / 'poster.png'
        self.movie.write_bytes(b'fixture-video')
        self.poster.write_bytes(b'fixture-poster')
        self.args = argparse.Namespace(movie=str(self.movie), poster=str(self.poster))
        self.addCleanup(patch.stopall)
        patch('catalog.refresh').start()
        patch('catalog.validate_movie').start()
        patch('catalog.subprocess.run', return_value=argparse.Namespace(stdout='')).start()
        patch('sys.stdout', new_callable=io.StringIO).start()

    def install(self):
        catalog.install(self.args, self.root, self.support)
        return json.loads((self.support / 'receipt.json').read_bytes())

    def test_install_preserves_apple_assets_settings_and_initial_backup_on_repeat(self):
        before = self.index.read_bytes()
        receipt = self.install()
        self.install()
        manifest = json.loads(self.manifest.read_bytes())
        self.assertEqual(len(manifest['assets']), 2)
        self.assertEqual(manifest['assets'][0], self.original_manifest['assets'][0])
        self.assertEqual(manifest['unrecognizedFutureKey'], {'keep': True})
        self.assertEqual(self.index.read_bytes(), before)
        self.assertEqual((Path(receipt['backup']) / 'Index.plist').read_bytes(), before)
        self.assertIn('%20', manifest['assets'][1]['previewImage'])

    def test_restore_returns_original_selection_without_losing_new_catalogue_assets(self):
        receipt = self.install()
        current = {'AllSpacesAndDisplays': {'Type': 'linked', 'Linked': {'Content': {'Choices': [{
            'Provider': 'com.apple.wallpaper.choice.aerials',
            'Configuration': plistlib.dumps({'assetID': receipt['assetID']})}]}}},
            'Displays': {'new-monitor': {'Type': 'individual', 'Desktop': {'custom': True}}}, 'Spaces': {}}
        catalog.atomic_write(self.index, plistlib.dumps(current))
        manifest = json.loads(self.manifest.read_bytes())
        manifest['assets'].append({'id': 'new-apple-download'})
        catalog.atomic_write(self.manifest, catalog.json_bytes(manifest))
        catalog.restore(None, self.root, self.support)
        restored = plistlib.loads(self.index.read_bytes())
        self.assertEqual(restored['AllSpacesAndDisplays'], self.original_index['AllSpacesAndDisplays'])
        self.assertEqual(restored['Displays'], current['Displays'])
        self.assertEqual([a['id'] for a in json.loads(self.manifest.read_bytes())['assets']],
                         ['existing', 'new-apple-download'])

    def test_restore_leaves_later_wallpaper_selection_untouched(self):
        self.install()
        later = plistlib.dumps({'Type': 'individual', 'user-selected': 'different wallpaper'})
        catalog.atomic_write(self.index, later)
        catalog.restore(None, self.root, self.support)
        self.assertEqual(self.index.read_bytes(), later)

    def test_activation_links_both_surfaces_and_restore_round_trips(self):
        receipt = self.install()
        catalog.activate(None, self.root, self.support)
        active = plistlib.loads(self.index.read_bytes())
        for key in ('AllSpacesAndDisplays', 'SystemDefault'):
            self.assertEqual(active[key]['Type'], 'linked')
            self.assertEqual(catalog.selected_assets(active[key]), {receipt['assetID']})
        catalog.restore(None, self.root, self.support)
        restored = plistlib.loads(self.index.read_bytes())
        self.assertEqual(restored['AllSpacesAndDisplays'], self.original_index['AllSpacesAndDisplays'])
        self.assertFalse(catalog.selected_assets(restored))

    def test_replacement_keeps_original_backup_and_apple_assets(self):
        first = self.install()
        self.movie.write_bytes(b'corrected-temporal-video')
        self.args.replace = True
        corrected = self.install()
        self.assertNotEqual(corrected['assetID'], first['assetID'])
        self.assertEqual(corrected['backup'], first['backup'])
        self.assertTrue(Path(first['video']).exists())
        self.assertEqual(len(json.loads(self.manifest.read_bytes())['assets']), 2)
        self.assertEqual(plistlib.loads((Path(corrected['backup']) / 'Index.plist').read_bytes()), self.original_index)

    def test_incompatible_video_is_rejected_before_any_settings_change(self):
        before = self.manifest.read_bytes()
        with patch('catalog.validate_movie', side_effect=ValueError('missing temporal metadata')):
            with self.assertRaises(ValueError):
                self.install()
        self.assertEqual(self.manifest.read_bytes(), before)
        self.assertFalse((self.support / 'receipt.json').exists())

    def test_unknown_manifest_is_not_mutated(self):
        self.manifest.write_text('{"future": true}')
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual(self.manifest.read_text(), '{"future": true}')
        self.assertFalse((self.support / 'receipt.json').exists())


if __name__ == '__main__':
    unittest.main()
