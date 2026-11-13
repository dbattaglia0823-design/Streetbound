import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from project_asset_catalog import catalog,asset_id,building_file
from morrow_editor_import import _authoring_props
import morrow_editor_import as importer


class ProjectAssetTests(unittest.TestCase):
    def test_catalog_rescans_nested_files_and_skips_sidecars_and_broken_images(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            folder=root/'assets/Buildings/New Folder'
            folder.mkdir(parents=True)
            self.assertEqual(catalog(root),[])
            image=folder/'CornerShop.png'
            image.write_bytes(b'\x89PNG\r\n\x1a\n'+b'\x00'*8+struct.pack('>II',800,400))
            (folder/'CornerShop.png.import').write_text('ignored')
            (folder/'broken.png').write_text('broken')
            first=catalog(root)
            self.assertEqual(len(first),1)
            self.assertEqual(first[0]['name'],'Corner Shop')
            self.assertEqual(first[0]['width'],800)
            (folder/'NewHouse.svg').write_text('<svg viewBox="0 0 120 180"/>')
            self.assertEqual(len(catalog(root)),2)
            self.assertEqual(catalog(root)[0]['id'],first[0]['id'])
            image.unlink()
            self.assertEqual(len(catalog(root)),1)

    def test_baked_props_keep_file_artwork_and_matching_collision_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            image=root/'assets/Buildings/New Shop.svg'
            image.parent.mkdir(parents=True)
            image.write_text('<svg viewBox="0 0 200 100"/>')
            relative='Buildings/New Shop.svg'
            doc={'props':[dict(id='prop-1',name='New shop',type='building',x=500,y=500,
                scale=1.5,rotation=45,assetId=asset_id(relative),assetPath=relative,assetSize=[22,11])]}
            with patch.object(importer,'ROOT',root):
                result=_authoring_props(doc)[0]
                self.assertEqual(result['asset_path'],relative)
                self.assertEqual(result['size'],[33,16.5])
                self.assertTrue(result['solid'])
                image.unlink()
                with self.assertRaisesRegex(ValueError,'missing'):_authoring_props(doc)

    def test_paths_stay_inside_the_building_library(self):
        for path in ['../secret.png','Buildings/../secret.png','Buildings\\x.png',
            'Buildings/x.txt','Vehicles/car.png','Buildings/http://x.png']:
            with self.assertRaises(ValueError):building_file(path)


if __name__=='__main__':unittest.main()
