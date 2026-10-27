# GitHub notifications for Omarchy

A bar widget for the [Omarchy](https://omarchy.org) Quattro shell that shows how
many GitHub notifications are unread, plus rules that clear out the ones you
never want to look at.

- The bar shows an unread count sourced from the GitHub CLI (`gh`). The bell
  and count only turn red once more than `alarmThreshold` (default 10) threads
  are unread.
- A popup lists the unread threads: **Enter** opens one, **x** marks it done,
  **r** refreshes, **a** opens github.com/notifications. Opening a thread goes
  to the pull request, issue, discussion, release or commit it is about — not
  the repository.
- **Rules** auto-dismiss noise. Each rule matches notifications and either
  *acks* them (marks the thread read on GitHub) or *ignores* them (hidden from
  the count, still unread on GitHub). Either way they stop counting.

## Requirements

- Omarchy with the Quattro shell (`omarchy-shell`).
- `gh` signed in for github.com: `gh auth login`. The token needs the `notifications`
  scope on top of `gh`'s defaults (gist, read:org, repo); organization threads
  also need SSO authorization if the org enforces it. Without the notifications
  scope the widget reports GitHub's 403 in the panel instead of a count.
- `jq` and `curl` on `PATH`. The helper also probes `~/.local/bin`,
  `~/.local/share/mise/shims`, and `~/.asdf/shims`, since the shell does not
  necessarily inherit your interactive `PATH`.

## Install

```bash
git clone https://github.com/renaudhager/github-notification-plugins \
  ~/.config/omarchy/plugins/renaudhager.github-notifications
omarchy-shell shell rescanPlugins
omarchy plugin enable renaudhager.github-notifications
```

The widget lands in the right side of the bar. Move it with `omarchy bar move`
or in the bar settings.

To keep working from a checkout instead of the plugin directory, symlink it:

```bash
ln -s ~/github/renaudhager/github-notification-plugins \
  ~/.config/omarchy/plugins/renaudhager.github-notifications
```

Saving any file under the plugin directory hot-reloads the widget.

## Settings

Configured per widget in `~/.config/omarchy/shell.json` (layout entry for
`renaudhager.github-notifications`), or through the plugin's settings form.

| Key                  | Default | Meaning                                        |
|----------------------|---------|------------------------------------------------|
| `refreshIntervalSec` | `300`   | Poll interval, 60–3600 seconds.                |
| `alarmThreshold`     | `10`    | The bar turns red only above this unread count. |
| `rules`              | `[]`    | JSON list of rules, see below.                 |

```json
{
  "id": "renaudhager.github-notifications",
  "refreshIntervalSec": 300,
  "alarmThreshold": 10,
  "rules": [
    { "pattern": "some-org/*", "action": "ignore" },
    { "pattern": "noisy-repo", "action": "ack" },
    { "pattern": "infra/repo#42", "action": "ack" }
  ]
}
```

From the command line, `omarchy bar set` takes the value as JSON already, so pass the whole list as one quoted argument:

```bash
omarchy bar set renaudhager.github-notifications refreshIntervalSec 300

omarchy bar set renaudhager.github-notifications alarmThreshold 10

omarchy bar set renaudhager.github-notifications rules \
  '[{"pattern":"some-org/*","action":"ignore"},{"pattern":"infra/repo","action":"ack"}]'
```

This replaces the whole rule list, and `shell.json` stores it as a JSON string,
which the widget accepts just like a list. Running the command again with an
updated list is the way to add or remove a rule.

### Rules

Rules are evaluated **top to bottom; the first match wins**.

| `action`  | Effect                                                          |
|-----------|-----------------------------------------------------------------|
| `"ack"`   | Matching unread threads are marked done on GitHub (they leave the inbox for the Done tab) and hidden from the count. |
| `"ignore"`| Matching threads are hidden from the count only; they stay unread on GitHub. |

| Pattern                 | Matches                                                     |
|-------------------------|-------------------------------------------------------------|
| `owner/repo`            | every notification in that repository                       |
| `owner/*`               | every repository of that owner                              |
| `owner/repo#pull`       | pull requests only (`#pr`, `#pullRequest` too)              |
| `owner/repo#issue`      | issues only                                                 |
| `owner/repo#discussion` | discussions only                                            |
| `owner/repo#release`    | releases only                                               |
| `owner/repo#123`        | the thread number 123 (PR or issue with that number)        |
| `owner/repo#any`        | same as `owner/repo`                                        |
| bare word               | matches a repository name, a subject type (`pullRequest`, `issue`, `release`, `commit`, `checkSuite`, …) or a notification reason (`review_requested`, `assign`, `comment`, `mention`, `subscribed`, …) |

Patterns are case-insensitive.

A thread marked `ack` counts as "acked" until GitHub drops it from the unread
inbox on the next poll; after that it is gone from the widget entirely. The
panel's "Hidden by your rules" line reports how many notifications the rules
are currently holding back.

## How it works

`github-notifications-fetch` (bash + `curl` + `jq`) reads the token from
`gh auth token`, pages through `GET /notifications` (GitHub caps that endpoint
at 50 per page, so the helper follows the `Link: rel="next"` header), shapes
every thread in a single `jq` pass, applies the rules, and prints one JSON
document. Each row's `url` is the page it opens: the subject API URL is mapped
onto its web page (`/pulls/7` becomes `/pull/7`), and a notification GitHub
files as an `Issue` is checked once to tell a real issue from a pull request.
`Service.qml` runs it on a timer and on demand; `Panel.qml` renders the bar
icon and the popup, and calls `--mark-done <id>` for the `x` action.

Nothing is cached: each poll is one request per 50 unread threads plus one for
each issue-numbered thread, well inside the 5,000/hour authenticated limit.

## License

MIT
