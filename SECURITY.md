# Security

Fenn Focus runs on your Mac and stores everything locally (Markdown files in a folder you choose, settings in
`UserDefaults`, API keys in the macOS Keychain). It has no server and sends no telemetry.

Network traffic happens only when you choose it:

- an AI provider you configured yourself (your own key, or a local server such as Ollama or LM Studio),
- a model download from Hugging Face when you pick a built-in local model,
- the optional MCP server, which listens on `127.0.0.1` only.

Please report vulnerabilities privately through GitHub's **Security › Report a vulnerability** on this repository
instead of opening a public issue.
