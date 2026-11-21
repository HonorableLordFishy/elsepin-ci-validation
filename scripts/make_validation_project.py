"""Generate a disposable simulator-only project; never alter the device spec/engine."""
import json
from pathlib import Path
import subprocess
import yaml
from validation_sdk_compatibility import compatibility_sources

ROOT = Path(__file__).resolve().parents[1]
spec = yaml.safe_load((ROOT / "project.yml").read_text(encoding="utf-8"))
spec["name"] = "ElsepinValidation"
app = spec["targets"]["Locus"]
sdk_major = int(subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).split('.')[0])
compatibility_excludes, compatibility_files = compatibility_sources(ROOT, sdk_major)
excluded = ["App/LocusApp.swift", "Engine/LocationEngine.swift", "Engine/PairingStore.swift",
            "Engine/PairOnDeviceService.swift", "Support/PlaceSearchRequest.swift",
            "Support/PlaceSearchCompleter.swift"]
app["sources"][0]["excludes"] += excluded + compatibility_excludes
app["sources"] = [s for s in app["sources"] if not s["path"].startswith("Vendor/")]
app["sources"] += [{"path": "Validation/Support"}, {"path": ".build/validation/EngineTypes.swift"}]
app["sources"] += compatibility_files
base = app["settings"]["base"]
for key in list(base):
    if key.startswith(("OTHER_LDFLAGS", "LIBRARY_SEARCH_PATHS", "SWIFT_INCLUDE_PATHS", "HEADER_SEARCH_PATHS")):
        del base[key]
base.update(PRODUCT_BUNDLE_IDENTIFIER="com.n3mostudio.elsepin.validation", PRODUCT_NAME="ElsepinValidation",
            CODE_SIGN_ENTITLEMENTS="", SWIFT_ACTIVE_COMPILATION_CONDITIONS="$(inherited) ELSEPIN_UI_TESTING",
            SUPPORTED_PLATFORMS="iphonesimulator", SUPPORTS_MACCATALYST=False)
extension = spec["targets"]["LocusActivity"]["settings"]["base"]
extension.update(PRODUCT_BUNDLE_IDENTIFIER="com.n3mostudio.elsepin.validation.activity", CODE_SIGN_ENTITLEMENTS="")
spec["targets"]["LocusValidationUITests"] = {
    "type": "bundle.ui-testing", "platform": "iOS", "sources": ["Validation/UITests"],
    "dependencies": [{"target": "Locus"}],
    "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "com.n3mostudio.elsepin.validation.tests",
                            "GENERATE_INFOPLIST_FILE": True, "TEST_TARGET_NAME": "Locus"}}
}
app["scheme"]["testTargets"] = ["LocusValidationUITests"]
# Reuse the unmodified engine's public error/cancellation declarations. None of
# its FFI implementation or imports are linked into the simulator executable.
engine = (ROOT / "Locus/Engine/LocationEngine.swift").read_text(encoding="utf-8")
types = engine[:engine.index("/// Thin Swift wrapper")].replace("import idevice\n", "")
generated = ROOT / ".build/validation"
generated.mkdir(parents=True, exist_ok=True)
(generated / "EngineTypes.swift").write_text(types, encoding="utf-8")
(ROOT / "project.validation.json").write_text(json.dumps(spec, indent=2), encoding="utf-8")
print("Generated simulator-only project. Production project and location engine unchanged.")
