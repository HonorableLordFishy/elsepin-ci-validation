import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_validation_simulator import choose_destination


class ValidationSimulatorTests(unittest.TestCase):
    def runtime(self, version, model, available=True):
        return dict(identifier='com.apple.CoreSimulator.SimRuntime.iOS-' + version,
                    version=version, isAvailable=available,
                    supportedDeviceTypes=[dict(name=model, identifier=model, productFamily='iPhone')])

    def test_prefers_sdk_match_over_newer_device_specific_runtime(self):
        stable = self.runtime('27.1', 'iPhone 17')
        special = self.runtime('27.2', 'iPhone 19')
        runtime, model = choose_destination({'runtimes': [special, stable]}, '27.1')
        self.assertEqual(runtime, stable)
        self.assertEqual(model['name'], 'iPhone 17')

    def test_fallback_selects_only_a_supported_model(self):
        special = self.runtime('27.2', 'iPhone 19')
        runtime, model = choose_destination({'runtimes': [special]}, '27.1')
        self.assertIn(model, runtime['supportedDeviceTypes'])
        self.assertEqual(model['name'], 'iPhone 19')

    def test_unavailable_runtime_is_not_selected(self):
        with self.assertRaisesRegex(RuntimeError, 'No available iOS runtime'):
            choose_destination({'runtimes': [self.runtime('27.1', 'iPhone 17', False)]}, '27.1')

    def test_portrait_phone_preferred_over_duo_sdk_match(self):
        phone = self.runtime('27.0', 'iPhone SE (3rd generation)')
        duo = self.runtime('27.1', 'iPhone Duo')
        runtime, _ = choose_destination({'runtimes': [duo, phone]}, '27.1')
        self.assertEqual(runtime, phone)

    def test_newest_portrait_runtime_preferred_even_above_sdk(self):
        phone = self.runtime('27.0', 'iPhone SE (3rd generation)')
        newer = self.runtime('27.2', 'iPhone SE (3rd generation)')
        runtime, _ = choose_destination({'runtimes': [newer, phone]}, '27.1')
        self.assertEqual(runtime, newer)

    def test_explicit_runtime_comparison_uses_requested_version(self):
        requested = self.runtime('27.1', 'iPhone 17')
        newer = self.runtime('27.2', 'iPhone 17')
        runtime, _ = choose_destination({'runtimes': [requested, newer]}, '27.1', '27.1')
        self.assertEqual(runtime, requested)

    def test_missing_requested_runtime_does_not_silently_test_another_version(self):
        with self.assertRaisesRegex(RuntimeError, 'requested version 27.1'):
            choose_destination({'runtimes': [self.runtime('27.2', 'iPhone 17')]}, '27.1', '27.1')
