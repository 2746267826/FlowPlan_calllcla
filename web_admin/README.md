# FlowPlanV2 Web Admin

Independent Vite React management panel for FlowPlanV2 P9.

Current P9 scope:

- API login and saved admin context
- server overview
- schedule and task object management
- actual record management
- tracking object summary
- file metadata management
- sync health and device status
- conflict review and server-version resolution
- Outlook mapping status
- audit log review
- report and push delivery review
- AI operation draft review
- server job state management
- remote config management

Run the stable admin server with:

```powershell
npm run dev
```

This serves the built `dist` directory with a small Node server and avoids Vite's Windows `net use` path probe, which can fail with `spawn EPERM` in restricted environments.

Use Vite hot reload only when the environment allows it:

```powershell
npm run vite:dev
```

Build with:

```powershell
npm run build
```
