# Changelog

## 1.2.0

- **Goals.** A new "Goals" view in Tasks: one card per goal with its symbol, why it matters, the deadline
  ("12 days left"), a ring with this week's focus hours against the weekly target, steps done and the next step with
  ▶. Unfold a goal to see all its steps and add one inline. Goals can be edited, marked as reached, archived or
  deleted (their tasks stay). Task rows show the goal, the task editor has a goal picker, and typing `@goal` in any
  task capture attaches it. Goals live in `tasks/tasks.json` next to the tasks; older files read as before.
- **Goal hours.** Today shows the hours that went into goals today and this week; Progress has a "Goals this week"
  card; the review in Tasks gets a "This week" section per goal (hours, steps done, what slipped).
- **Week plan.** A "Week" view from Monday to Sunday with a week switcher: each day's tasks, planned time against the
  free working time from the day planner, an "Unplanned" tray, drag and drop between days, and "+" per day.
- **First today.** Pick the one task that matters most today; Fenn suggests the next step of the goal that is
  furthest behind its weekly hours. "Reserve time" gives it today's first free gap that fits its estimate.
- **Task focus.** ▶ (or F) opens a full-panel view of one task with the running Pomodoro. "Complete" (⌘⏎) ticks it
  off and the next task follows straight away in the same Pomodoro: the goal's next step, otherwise the next task.
  The minutes so far stay with the finished task.
- **Keys in Tasks** (when no text field is being edited): N new task, F focus, L today, W week, G goals, ↑/↓ select, Space
  tick off, ⌘K a command palette for tasks, goals, areas and actions.
- **Close the week.** Writes a short "Wochen-Check" into today's journal and opens next week for planning.
- **Log time.** The task editor can log minutes worked without the timer; they count for the day and the goal.
- **Agent.** New tools `add_goal` and `list_goals`; `add_tasks` and `update_task` take a `goal` by name.
- **A calmer Tasks screen** (following Apple's HIG): three views as text segments (Today, Week, Goals, keys L/W/G)
  and one … menu for the day view, timeline, review, grouping, topic filter and the calendar; rows show the title
  and one quiet line (goal or topic, date, estimate); no topic chips and no storage line at the bottom; the task
  editor shows goal, date and estimate first and the rest under "More"; likely appointments fold into one line.
- Demo mode keeps its own Pomodoro, so screenshots never touch a running real one.

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
