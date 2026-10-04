import unittest
from unittest.mock import patch
import check_upstream


class UpstreamTests(unittest.TestCase):
    def asset(self, name, digest='sha256:' + 'a' * 64):
        return {'name': name, 'digest': digest, 'size': 123456,
                'browser_download_url': 'https://github.com/Sikarugir-App/Template/releases/download/v1.0/' + name}

    def releases(self, assets, **kwargs):
        return [{'draft': False, 'prerelease': False, 'assets': assets, **kwargs}]

    def test_versions_are_sorted_numerically_and_unrelated_files_excluded(self):
        payload = self.releases([self.asset('Template-1.0.9.tar.xz'), self.asset('Template-1.0.21.tar.xz'), self.asset('Other-9.0.tar.xz')])
        with patch.object(check_upstream, 'api', return_value=payload):
            value = check_upstream.latest_asset('Sikarugir-App/Template', r'Template-\d+\.\d+\.\d+\.tar\.xz')
        self.assertEqual(value['name'], 'Template-1.0.21.tar.xz')
        self.assertEqual(value['sha256'], 'a' * 64)

    def test_missing_digest_is_not_accepted(self):
        with patch.object(check_upstream, 'api', return_value=self.releases([self.asset('Template-1.0.21.tar.xz', None)])):
            with self.assertRaisesRegex(RuntimeError, 'No SHA-256'):
                check_upstream.latest_asset('Sikarugir-App/Template', r'Template-.*\.tar\.xz')

    def test_prerelease_is_not_selected(self):
        with patch.object(check_upstream, 'api', return_value=self.releases([self.asset('Template-9.0.tar.xz')], prerelease=True)):
            with self.assertRaisesRegex(RuntimeError, 'No supported'):
                check_upstream.latest_asset('Sikarugir-App/Template', r'Template-.*\.tar\.xz')

    def test_unexpected_asset_origin_is_rejected(self):
        item = self.asset('Template-1.0.21.tar.xz')
        item['browser_download_url'] = 'https://example.com/Template-1.0.21.tar.xz'
        with patch.object(check_upstream, 'api', return_value=self.releases([item])):
            with self.assertRaisesRegex(RuntimeError, 'Unexpected upstream URL'):
                check_upstream.latest_asset('Sikarugir-App/Template', r'Template-.*\.tar\.xz')


if __name__ == '__main__':
    unittest.main()
