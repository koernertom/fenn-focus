# Choosing a model

Fenn Focus works without any AI. With a model it can tidy notes, turn a sentence into tasks with dates, plan your day
around your calendar and act as an agent (create a task, move a block, start a focus session …).

**Local first.** Everything below runs on your Mac – no account, no key, nothing leaves the machine. Cloud models are
optional and use your own key.

_Last checked: October 2026. Sizes are download sizes of the 4-bit builds; RAM figures are estimates (weights plus
context), not measurements._

## Quick pick

| Your Mac (unified memory) | Built-in (MLX, downloads in the app) | Ollama | Download | Why |
|---|---|---|---|---|
| **8 GB** | `mlx-community/Qwen3.5-4B-MLX-4bit` | `qwen3.5:4b` | ~3 GB | Best tool calling under 4 GB, 201 languages incl. German. |
| 8 GB, tight on memory | `mlx-community/Qwen3.5-2B-MLX-4bit` | `qwen3.5:2b` | ~1.7 GB | Fast for notes and short answers; noticeably weaker as an agent. |
| **16 GB** | `mlx-community/Qwen3.5-9B-MLX-4bit` | `qwen3.5:9b` | ~6 GB | Best small model for tools and the strongest multilingual results of the small Qwens. |
| **24–32 GB** | `mlx-community/gemma-4-26b-a4b-it-4bit` | `gemma4:26b` | ~15 GB | Mixture-of-experts with ~4B active parameters: big-model quality at small-model speed. Tight on 24 GB. |
| 32 GB, alternative | `mlx-community/Qwen3.6-35B-A3B-4bit` | `qwen3.6:35b-a3b` | ~20 GB | Qwen's fast MoE. |
| **48 GB+** | `mlx-community/Qwen3.8-27B-4bit` | `qwen3.8:27b` | ~16 GB | Newest dense Qwen, long context. Slower than the MoE models. |

**Default:** Fenn Focus never picks a cloud model. It marks **Qwen3.5 4B** as recommended, or **Qwen3.5 9B** on Macs with
16 GB or more. If Ollama or LM Studio is already running, Fenn Focus says so and picks the best of the models you
already have.

Benchmarks behind the picks (from the model cards): Qwen3.5-4B scores BFCL-V4 50.3 / τ²-Bench 79.9, Qwen3.5-9B
66.1 / 79.1, Qwen3.5-2B 43.6 / 48.8. Gemma 4 E4B, the closest small rival, reaches τ²-Bench 42.2 – fine for text,
weaker as an agent. There is no public German-specific benchmark for these models; multilingual scores (MMMLU,
WMT24++) are the closest proxy.

## The runtimes

### Built-in (MLX)

Runs inside Fenn Focus on Apple Silicon via [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm). Pick a model
under **Connections › AI model** and it downloads from Hugging Face into the app's own folder
(`~/Library/Containers/app.fennfocus/Data/Library/Application Support/FennFocus/Models`). Delete it there with one click. Tool calls are parsed natively for Qwen 3.5/3.6/3.8 and Gemma 4.

### Ollama

```bash
brew install ollama
ollama pull qwen3.5:4b
```

Fenn Focus talks to `http://localhost:11434` and lists your installed models. Tools go through Ollama's native
`tools` API; thinking is switched off and the model stays loaded for 30 minutes.

### LM Studio

Load a model, start the local server (default `http://localhost:1234/v1`), then choose **LM Studio** in Fenn Focus.
Qwen models get LM Studio's native tool calling; other families fall back to a prompt-based format.

### Apple (on device)

macOS 26 or later with Apple Intelligence turned on. No download and very fast, but the context window is small
(about 4,000 tokens on macOS 26), so Fenn Focus uses it for short jobs – tidying a note, a summary – and hands the
agent to a downloaded built-in model when there is one. Apple's model answers in German when told to.

### Your own key (optional)

Claude (Anthropic), OpenRouter or any OpenAI-compatible endpoint. The key is stored in your macOS Keychain and only
sent to the provider you chose. Nothing in this repository contains a key.

## Tips for small models

- **Thinking off.** Qwen 3.5 4B/9B and Qwen 3.8 "think" by default; Fenn Focus turns thinking off (faster, fewer loops)
  and uses Qwen's recommended non-thinking sampling: temperature 0.7, top_p 0.8, top_k 20.
- **Fewer tools.** With a local model Fenn Focus sends only the tools that fit the request (tasks, day, focus,
  routines, ideas …) – small models choose better from a short list.
- **Keep it loaded.** The built-in model stays in memory after first use (on Macs under 24 GB only one at a time);
  with Ollama, Fenn Focus asks it to keep the model warm for 30 minutes.
- **Measured on an M-series Mac with 48 GB:** Qwen3.5 4B (built-in) answered a German question in 16 s including
  loading the model, then made a correct tool call in under 4 s.

## Licenses

All models recommended here are Apache-2.0 (Qwen 3.5, 3.6, 3.8-27B; Gemma 4). Downloading one means accepting its
license; the model is not part of Fenn Focus. Avoid models with custom "community" licenses unless you have read them.

## Sources

- Qwen model cards: [Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B), [Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B),
  [Qwen3.5-9B](https://huggingface.co/Qwen/Qwen3.5-9B), [Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B)
- [Gemma 4 E4B](https://huggingface.co/google/gemma-4-E4B-it)
- Ollama: [qwen3.5](https://ollama.com/library/qwen3.5/tags), [qwen3.6](https://ollama.com/library/qwen3.6/tags),
  [qwen3.8](https://ollama.com/library/qwen3.8/tags), [gemma4](https://ollama.com/library/gemma4/tags),
  [tool calling](https://docs.ollama.com/capabilities/tool-calling)
- [LM Studio tool use](https://lmstudio.ai/docs/developer/openai-compat/tools)
- [mlx-swift-lm tool call formats](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLMCommon/Tool/ToolCallFormat.swift)
- Apple Foundation Models: [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
