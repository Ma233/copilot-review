Triage the Copilot review for action, not display.

For each comment, choose exactly one:

- `apply`: correct and worth fixing now
- `verify`: plausible but needs inspection or tests
- `ignore`: stale, wrong, duplicate, or low-value

Keep one short sentence per item.

Output:

1. `Apply` - summary -> code change
2. `Verify` - summary -> check needed
3. `Ignore` - summary -> rejection reason

If the task is to improve code, do the `apply` items before replying.
