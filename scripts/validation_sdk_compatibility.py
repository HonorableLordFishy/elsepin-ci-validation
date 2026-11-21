"""Use existing pre-iOS-27 fallbacks only in the disposable SDK 26 UI target."""
from pathlib import Path


GUARD = '''#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("SDK compatibility sources are simulator validation only")
#endif
'''


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise ValueError('Production fallback changed; review the simulator adapter')
    return source.replace(before, after, 1)


def compatibility_sources(root: Path, sdk_major: int):
    if sdk_major >= 27:
        return [], []
    if sdk_major != 26:
        raise ValueError(f'Unsupported validation SDK: {sdk_major}')
    paths = ['Support/ResourceUsageEnvironment.swift', 'Support/SystemDiagnosticCollector.swift']
    output = root / '.build/validation/SDK26'
    output.mkdir(parents=True, exist_ok=True)

    resource = (root / 'Locus' / paths[0]).read_text(encoding='utf-8')
    resource = replace_once(resource,
        '        if #available(iOS 27, *) { content.modifier(SystemResourceUsage()) }\n        else { content }',
        '        content')
    resource = resource[:resource.index('@available(iOS 27, *)')]

    diagnostics = (root / 'Locus' / paths[1]).read_text(encoding='utf-8')
    diagnostics = replace_once(diagnostics,
        '        if #available(iOS 27.0, *) { owner = ModernSystemDiagnostics() }\n        else { owner = LegacySystemDiagnostics() }',
        '        owner = LegacySystemDiagnostics()')
    start = diagnostics.index('@available(iOS 27.0, *)')
    end = diagnostics.index('@available(iOS, introduced: 14.0, obsoleted: 27.0)')
    diagnostics = diagnostics[:start] + diagnostics[end:]

    for path, source in zip(paths, [resource, diagnostics]):
        (output / Path(path).name).write_text(GUARD + source, encoding='utf-8')
    print('SDK 26 UI validation uses existing legacy resource/MetricKit fallbacks; iOS 27 diagnostics are not tested here.')
    return paths, [{'path': str(output.relative_to(root)).replace('\\', '/')}]
