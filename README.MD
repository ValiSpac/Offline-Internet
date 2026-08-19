# Offline Internet: Wikipedia + Local LLM RAG

A fully offline knowledge stack for a single machine: a local copy of Wikipedia served by [Kiwix](https://www.kiwix.org/en/), a local LLM running on [Ollama](https://ollama.com/), and [Open WebUI](https://openwebui.com/) as the chat interface wired together so the model can search and cite the offline Wikipedia via a custom Tool, instead of relying only on what it memorized during training.

No internet connection is required after the initial setup and downloads.

## What's in this repo

| File | Purpose |
|---|---|
| `setup_offline_internet.sh` | One-shot installer. Installs Kiwix, Docker, Ollama, downloads a Wikipedia ZIM, and stands up Open WebUI fully configured (Ollama connection + admin account) with no manual clicking required. |
| `kiwix_search_tool.py` | An Open WebUI Tool that lets the model search the local Kiwix server and fetch article text mid-conversation. |

## Architecture

```
 ┌─────────────┐      ┌───────────────┐      ┌─────────────────┐
 │   Browser    │ ───▶ │   Open WebUI   │ ───▶ │  Ollama (LLM)    │
 │ localhost:3000│      │ (Docker,3000)│      │ localhost:11434  │
 └─────────────┘      └───────┬───────┘      └─────────────────┘
                               │ tool call
                               ▼
                       ┌───────────────┐
                       │  kiwix-serve   │
                       │ localhost:8080 │
                       │ (Wikipedia ZIM)│
                       └───────────────┘
```

When you ask a factual question, the model can call the `search_offline_wikipedia` tool, which queries kiwix-serve's full-text index, then `get_offline_article` to pull the matching article's text into context before answering a simple retrieval-augmented-generation (RAG) loop that needs no vector database, since kiwix already indexes the whole ZIM.

## Requirements

- Ubuntu (or another Debian-based distro) with `sudo` access
- ~10–20 GB free disk space, depending on which Wikipedia ZIM you choose
- A machine that can run a small LLM on CPU reasonably (see [Performance notes](#performance-notes) below) a GPU is optional and not required (but recommended as the local AI needs a lot of search power even for a really small prompt)

## Setup

```bash
git clone <this-repo>
cd <this-repo>
chmod +x setup_offline_internet.sh
sudo ./setup_offline_internet.sh
```

This will:

1. Install `kiwix-tools`, Docker, and Ollama
2. Pull the `qwen3.5:0.8b` model
3. Download a Wikipedia ZIM into `~/Desktop/Kiwix-zims/`
4. Start `kiwix-serve` on port **8080** as a systemd service
5. Start Open WebUI (Docker) on port **3000**, pre-connected to Ollama
6. Auto-create the Open WebUI admin account and save its credentials to `~/Desktop/open-webui-admin-credentials.txt`

When it finishes, open **http://localhost:3000** you should land in a logged-in, model-ready chat.

## Adding the offline-search Tool

1. In Open WebUI, go to **Workspace → Tools → Create New Tool**.
2. Paste in the contents of `kiwix_search_tool.py`.
3. Save.
4. Under **Workspace → Models**, create (or edit) a model preset using `qwen3.5:0.8b` and attach the tool to it, or enable it per-chat with the 🔧 icon in the message box.
5. Optionally set a system prompt on the model along the lines of:
   > "You have no internet access. For factual questions, call `search_offline_wikipedia` first and base your answer on what it returns."
   Small models are more reliable at using tools when told to explicitly.

The tool's settings (Kiwix URL, which ZIM to search, result limits) are exposed as **Valves** in the tool's settings panel no code changes needed to point it at a different ZIM.

## Testing it

1. **Kiwix is reachable:**
   ```bash
   curl -s "http://localhost:8080/search?pattern=octopus" | head -50
   ```
2. **The Open WebUI container can reach Kiwix** (this is the URL the tool actually uses):
   ```bash
   docker exec open-webui curl -s "http://host.docker.internal:8080/search?pattern=octopus"
   ```
3. **Ollama is reachable from the container:**
   ```bash
   docker exec open-webui curl -s http://host.docker.internal:11434/api/tags
   ```
4. In a chat, ask something obscure enough that a small model couldn't know it from memory, e.g. *"What does the offline Wikipedia say about the Trevi Fountain's construction date?"* and check for an expandable tool-call block above the reply confirming the tool actually ran.

## Troubleshooting

- **kiwix-serve won't start / port 8080 unreachable:** check `systemctl status kiwix.service` and `journalctl -u kiwix.service -n 50`.
- **Ollama shows `/api/api/tags` 404 errors in Open WebUI logs:** a connection URL in Admin Panel → Settings → Connections has a trailing `/api` remove it, the URL should just be `http://host.docker.internal:11434`.
- **Tool never seems to run:** confirm it's toggled on for the model/chat, and check `docker logs open-webui` for Python errors from the tool (e.g. a missing dependency).

## License

MIT
