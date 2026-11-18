# Locally available shared Codex skills

**Source:** [Game-Dev-Toolkit](https://github.com/dbattaglia0823-design/Game-Dev-Toolkit/tree/a579824f00e7d81b5e055deea31e285f134bc545/.agents/skills) at commit `a579824f00e7d81b5e055deea31e285f134bc545`.

These are **selected snapshots** in the game checkout. Codex may read them without loading the entire shared vault. They do not automatically stay synchronized with the toolkit.

- [`godot-change-verification`](../.agents/skills/godot-change-verification/SKILL.md) — use only when the task matches its description
- [`knowledge-maintenance`](../.agents/skills/knowledge-maintenance/SKILL.md) — use only when the task matches its description
- [`racing-ai-audit`](../.agents/skills/racing-ai-audit/SKILL.md) — use only when the task matches its description

To check local copies using a checkout of the central toolkit, run:

```bash
python3 /path/to/Game-Dev-Toolkit/tools/install_project_skills.py --project-root . --skills godot-change-verification knowledge-maintenance racing-ai-audit --verify
```

That tool reports missing or differing snapshots, **never overwrites** them. Review changes before copying newer versions. Game source and local project instructions take priority over generic advice. No external scripts, Obsidian plugin or MCP service is required.
