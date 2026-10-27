# Working agreement (SaaS template, built to present to the company)

The owner is building this backend template as a project to present, and wants to understand every step.

- **Claude does the setup, one step at a time, and explains each step**: what it does, why it is needed, and the Node/Express comparison when it helps. Do exactly the step asked and nothing extra. Wait for the owner before starting the next step.
- **Keep the gem list small.** Add a gem only when the current step needs it. Say why, and name the alternative of not adding it.
- Do not run migrations unless asked. Write the migration and say how to run it.
- Before a task of 3 or more steps, make a todo list.
- Keep answers short, in simple English. **Mark anything not run or not verified.** Never claim a test passed without running it.
- After a step, say what to check by hand, and ask the follow-up that matters (edge cases, related places), briefly.
- Read the relevant file in `.claude/rules/` before writing code in that area. When a rule and existing code disagree, follow the rule for new code and flag the old code, do not silently rewrite it.
