# Changelog

## 1.0.1

- **Fenn understands combined requests with a local model.** "Remind me about the offer tomorrow and start 25 minutes
  on the pitch deck" now creates the task and starts the timer. Before, words like "tomorrow" or "Monday" only offered
  the calendar tools to small models, so the task and the timer were missing.
- **Dates for small models.** Fenn now tells the model the dates of the next seven days, so "next Tuesday" lands on the
  right day.
- **Timer and task in one sentence.** "Start 45 minutes focus and add the task …" is no longer cut down to the timer
  when a model is set up; the agent handles all of it. Without a model the timer still starts locally.
- "45 minute" (singular) is understood as a length.
- Fenn retries when a small model says it moved or created something without actually doing it.
- Website: [koernertom.github.io/fenn-focus](https://koernertom.github.io/fenn-focus/).

## 1.0.0

First open-source release.
