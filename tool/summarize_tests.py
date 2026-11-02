"""Summarize Dart test machine events without changing the test command status."""
import json
import os
from pathlib import Path

source = Path('test-results.jsonl')
tests = {}
results = {}
complete = False
if source.exists():
    for line in source.read_text().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get('type') == 'testStart':
            test = event['test']
            if not test.get('hidden', False):
                tests[test['id']] = test['name']
        if event.get('type') == 'testDone':
            results[event['testID']] = event
        if event.get('type') == 'done':
            complete = True
summary = {'completed': complete, 'passed': 0, 'failed': 0, 'skipped': 0, 'unfinished': 0, 'failures': []}
for key, name in tests.items():
    result = results.get(key)
    if result is None:
        summary['unfinished'] += 1
    elif result.get('skipped', False):
        summary['skipped'] += 1
    elif result.get('result') == 'success':
        summary['passed'] += 1
    else:
        summary['failed'] += 1
        summary['failures'].append(name)
Path('test-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
if 'GITHUB_STEP_SUMMARY' in os.environ:
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as out:
        out.write('### Application test outcomes\n\n```json\n' + json.dumps(summary, indent=2) + '\n```\n')
