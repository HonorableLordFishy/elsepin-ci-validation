import plistlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INFO_PLIST = ROOT / "Locus" / "Resources" / "Info.plist"


class DocumentTypeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with INFO_PLIST.open("rb") as handle:
            cls.info = plistlib.load(handle)

    def document_type(self, name):
        for item in self.info.get("CFBundleDocumentTypes", []):
            if item.get("CFBundleTypeName") == name:
                return item
        self.fail(f"missing document type {name}")

    def imported_type(self, identifier):
        for item in self.info.get("UTImportedTypeDeclarations", []):
            if item.get("UTTypeIdentifier") == identifier:
                return item
        self.fail(f"missing imported type {identifier}")

    def test_gpx_document_type_uses_the_standard_identifier(self):
        gpx = self.document_type("GPX Track")
        self.assertIn("com.topografix.gpx", gpx["LSItemContentTypes"])
        self.assertIn("public.xml", gpx["LSItemContentTypes"])
        self.assertNotIn("com.topografixix.gpx", gpx["LSItemContentTypes"])

    def test_gpx_imported_type_declares_extension_and_mime_type(self):
        gpx = self.imported_type("com.topografix.gpx")
        self.assertEqual(gpx["UTTypeConformsTo"], ["public.xml"])
        tags = gpx["UTTypeTagSpecification"]
        self.assertIn("gpx", tags["public.filename-extension"])
        self.assertEqual(tags["public.mime-type"], "application/gpx+xml")

    def test_pairing_and_in_place_file_paths_remain_declared(self):
        pairing = self.document_type("Pairing File")
        self.assertIn("com.apple.property-list", pairing["LSItemContentTypes"])
        self.assertIn("public.data", pairing["LSItemContentTypes"])
        self.assertTrue(self.info.get("LSSupportsOpeningDocumentsInPlace"))
        self.assertTrue(self.info.get("UIFileSharingEnabled"))
        self.assertIn("com.n3mostudio.shift.rppairing",
                      [item["UTTypeIdentifier"] for item in self.info["UTImportedTypeDeclarations"]])


if __name__ == "__main__":
    unittest.main()
