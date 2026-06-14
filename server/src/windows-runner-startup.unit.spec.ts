import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

describe('Windows runner startup visibility', () => {
  it('shows the main window immediately unless startup-to-tray was requested', () => {
    const repoRoot = resolve(__dirname, '..', '..');
    const flutterWindow = readFileSync(
      resolve(repoRoot, 'client_flutter/windows/runner/flutter_window.cpp'),
      'utf8',
    );

    expect(flutterWindow).toContain('Show();');
    expect(flutterWindow).toContain('if (start_hidden_to_tray_) {');
    expect(flutterWindow).toContain('HideToTray();');

    const nextFrameBlock = flutterWindow.match(
      /SetNextFrameCallback\(\[this\]\(\) \{(?<body>[\s\S]*?)\n  \}\);/,
    );
    expect(nextFrameBlock?.groups?.body ?? '').not.toContain('Show();');
  });
});
