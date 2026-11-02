"""Report actual Dart runner events; never replace the runner exit status."""
import json
import os
from pathlib import Path

summaries = {}
for source in sorted(Path('.').glob('*-test-results.jsonl')):
    tests, results = {}, {}
    summary = {'completed': False, 'runner_success': False, 'error_events': 0,
               'passed': 0, 'failed': 0, 'skipped': 0, 'unfinished': 0, 'failures': []}
    for line in source.read_text(errors='replace').splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get('type') == 'testStart' and isinstance(event.get('test'), dict):
            test = event['test']
            tests[test['id']] = test.get('name', 'unnamed')
        if event.get('type') == 'testDone':
            results[event['testID']] = event
        if event.get('type') == 'error':
            summary['error_events'] += 1
        if event.get('type') == 'done':
            summary['completed'] = True
            summary['runner_success'] = event.get('success', False)
    for key, name in tests.items():
        result = results.get(key)
        if result is not None and result.get('hidden', False):
            continue
        if result is None:
            summary['unfinished'] += 1
        elif result.get('skipped', False):
            summary['skipped'] += 1
        elif result.get('result') == 'success':
            summary['passed'] += 1
        else:
            summary['failed'] += 1
            summary['failures'].append(name)
    summaries[source.name] = summary
text = json.dumps(summaries, indent=2, ensure_ascii=False)
Path('test-summary.json').write_text(text + '\n')
print(text)
if 'GITHUB_STEP_SUMMARY' in os.environ:
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as out:
        out.write('### Application test outcomes\n\n```json\n' + text + '\n```\n')
