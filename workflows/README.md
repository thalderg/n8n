# n8n workflows

Automation systems I design and build with [n8n](https://n8n.io). Each system lives in its own folder with everything you need to understand it, import it and run it.

## What is in this repository

| Folder | What it holds |
|---|---|
| `workflows/` | Documented systems, one folder per system (this page). |
| `workflows2025/` | Automatic monthly backups of my n8n cloud instance. Raw exports, not documented. |

## Systems

| System | What it does | Services |
|---|---|---|
| [Vacancy Outreach](vacancy-outreach/) | Finds companies with open job vacancies, writes a personal email that offers matching candidates, asks you to approve it in Telegram, sends it, follows up and handles the replies. | Google Sheets, Gmail, Telegram, Venice (LLM), Hunter, SerpApi |

## What every system folder contains

```
<system-name>/
├── README.md          what it does, flowcharts, setup steps
├── wf1-....json       the n8n workflows, ready to import
├── wf2-....json
├── sample-sheet/      sample data (a Google Sheet to import), when the system uses one
└── images/            screenshots
```

## How to import a workflow

1. In n8n, open **Workflows → Create workflow → ⋯ → Import from file**, and pick the `.json` file.
2. Open every node that shows a warning and select your own credential. The files contain no credentials and no personal IDs.
3. Replace the placeholders. They are always written in capitals and start with `YOUR_`, for example `YOUR_SPREADSHEET_ID`.
4. Read the sticky notes on the canvas: each section says what it does and what it calls.
5. Test it by hand first, then publish it.

## Conventions

- **Names:** `System | WF1 — Action`. Every node name says what the node does, for example `Send Follow-up In Thread`.
- **No secrets in the files:** credentials, API keys and personal IDs are removed before upload.
- **Human in the loop:** systems that write to people (email, chat) ask for approval by default.
