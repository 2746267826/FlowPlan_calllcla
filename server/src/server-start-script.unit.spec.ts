import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

describe('server production start script', () => {
  it('points npm start at the built NestJS entrypoint', () => {
    const serverRoot = resolve(__dirname, '..');
    const packageJson = JSON.parse(
      readFileSync(resolve(serverRoot, 'package.json'), 'utf8'),
    ) as { scripts?: { start?: string } };

    expect(packageJson.scripts?.start).toBe('node dist/src/main.js');
    expect(existsSync(resolve(serverRoot, 'src/main.ts'))).toBe(true);

    const dockerfile = readFileSync(resolve(serverRoot, 'Dockerfile'), 'utf8');
    expect(dockerfile).toContain('node dist/src/main.js');
  });
});

describe('FlowPlanV2 all-in-one launcher script', () => {
  it('does not probe or advertise localhost:0 for automatic Flutter web ports', () => {
    const repoRoot = resolve(__dirname, '..', '..');
    const script = readFileSync(
      resolve(repoRoot, 'scripts/start-flowplanv2-all.ps1'),
      'utf8',
    );

    const automaticBranchStart = script.indexOf('if ($flutterWebUsesAutomaticPort) {');
    const automaticBranchEnd = script.indexOf('\n    } else {', automaticBranchStart);
    const automaticBranch =
      automaticBranchStart >= 0 && automaticBranchEnd > automaticBranchStart
        ? script.slice(automaticBranchStart, automaticBranchEnd)
        : '';

    expect(script).toContain('$flutterWebUsesAutomaticPort = $FlutterWebPort -le 0');
    expect(automaticBranch).toContain("Flutter will choose an available local port automatically.");
    expect(automaticBranch).toContain('Flutter Web will ask Flutter to choose an available local port automatically.');
    expect(automaticBranch).not.toContain('Test-PortBeforeStart');
    expect(automaticBranch).not.toContain('localhost:0');
    expect(automaticBranch).not.toContain('$flutterWebUrl = "http://localhost:$FlutterWebPort"');

    const copyableCommandsStart = script.indexOf('function Write-CopyableCommands');
    const copyableCommandsEnd = script.indexOf('\nfunction Invoke-Step', copyableCommandsStart);
    const copyableCommands =
      copyableCommandsStart >= 0 && copyableCommandsEnd > copyableCommandsStart
        ? script.slice(copyableCommandsStart, copyableCommandsEnd)
        : '';

    expect(copyableCommands).toContain('$flutterWebRunCommand');
    expect(copyableCommands).toContain('if ($FlutterWebPort -le 0)');
    expect(copyableCommands).toContain('"flutter run -d chrome $FlutterModeArg"');
    expect(copyableCommands).toContain('$flutterWebRunCommand');
  });

  it('captures long-running native process stderr without PowerShell NativeCommandError wrappers', () => {
    const repoRoot = resolve(__dirname, '..', '..');
    const script = readFileSync(
      resolve(repoRoot, 'scripts/start-flowplanv2-all.ps1'),
      'utf8',
    );

    const longRunningStart = script.indexOf('function Start-LongRunningProcess');
    const longRunningEnd = script.indexOf('\ntry {', longRunningStart);
    const longRunningBlock =
      longRunningStart >= 0 && longRunningEnd > longRunningStart
        ? script.slice(longRunningStart, longRunningEnd)
        : '';

    expect(longRunningBlock).toContain('-EncodedCommand');
    expect(longRunningBlock).toContain('& `$env:ComSpec /d /c');
    expect(longRunningBlock).not.toContain("$Command + ' 2>&1 | Tee-Object");
    expect(longRunningBlock).not.toContain('-Command "& {');
  });
});
