# MANUAL-FILE-001 Evidence - 2026-06-14

Real local server API verification for file transfer interruption recovery.

- Source file: C:\Users\a2746\Desktop\calll260426\docs\test-governance\reports\manual-evidence\MANUAL-FILE-001-20260614\artifacts\manual-file-001-20260613195545.bin
- Downloaded file: C:\Users\a2746\Desktop\calll260426\docs\test-governance\reports\manual-evidence\MANUAL-FILE-001-20260614\artifacts\manual-file-001-20260613195545.downloaded.bin
- Source SHA-256: 5200dd6d4f2ad3817c6680629cf8dd07f5b7b034835e79dd7c80163604581e43
- Downloaded SHA-256: 5200dd6d4f2ad3817c6680629cf8dd07f5b7b034835e79dd7c80163604581e43
- Upload session: c53b713c-cc25-4d75-9570-49fa9cd40a11
- Storage object: 40d273a6-78eb-45a7-b729-95bcf1b686a5
- Download session: 9a951133-91ab-4478-bf9f-5e74aec49ac1
- Interruption method: chunk 1 intentionally skipped, missing-chunks returned [1], then chunk 1 was uploaded and missing-chunks returned [].
- Result JSON: C:\Users\a2746\Desktop\calll260426\docs\test-governance\reports\manual-evidence\MANUAL-FILE-001-20260614\logs\manual-file-001-20260613195545.json

Conclusion: upload interruption recovery, resume, server-hosted storage object creation, range download, and full-file hash verification passed against http://127.0.0.1:3202/api on 2026-06-14.
