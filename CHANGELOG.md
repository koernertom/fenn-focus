# Changelog

## 1.1.0

- **Progress.** A new view with your total focus hours and the next milestone (1 h, 5 h, 10 h, 25 h …), focus,
  tasks and Pomodoros this week compared with last week, your streak, focus per day, week or month, a 20-week
  heatmap, tasks done over time, where the time went and your best time of day. Everything comes from your own
  files; nothing is counted anywhere else.
- **Fenn is glad with you.** When a Pomodoro or a task is done, Fenn hops in the island's corner with a line about
  your day ("Done! That's 3 today.", "Pomodoro done! 1:40 h of focus today.", "10 hours of focus in total!"). With the
  island closed, the notch notice shows him hopping instead of an icon.
- **Put Fenn anywhere.** Drag the open island by the small handle at its top edge, or the closed pill, to any spot on
  the screen; it stays there. Drop it at the top centre to send it back to the notch, at a side to dock it there,
  or double-click the handle.
- **Easier to fold back.** A swipe up over the pill or the island's header folds it away, a click elsewhere closes an
  island that only the mouse opened, and it closes sooner when the mouse leaves.
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
