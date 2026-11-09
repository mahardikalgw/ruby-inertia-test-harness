# Inertia test harness

Author tests for a Rails + Inertia app the way its harness expects — minitest integration tests with inertia_rails/minitest assertions, domain builder objects instead of fixtures, service failure-branch tests, and Capybara system tests that survive Radix overlays. Use when adding tests, fixing a flaky system test, or adding a route that needs authentication coverage.

One skill, one repository. Part of a twelve-skill pack extracted from a production Rails 8 +
Inertia + React helpdesk monolith — the opinionated layer no public Rails or shadcn skill can know.
Version `2.0.0` tracks the source constitution.

## Install

```jsonc
// skills-lock.json
{
  "version": 1,
  "skills": {
    "inertia-test-harness": {
      "source": "mahardikalgw/inertia-test-harness",
      "sourceType": "github",
      "skillPath": "SKILL.md"
    }
  }
}
```

Or clone and symlink:

```bash
git clone git@github.com:mahardikalgw/inertia-test-harness.git
ln -s "$PWD/inertia-test-harness" .claude/skills/inertia-test-harness
```

## When to activate

- Writing a test for a new route, service, query, job or mailer.
- A system test flakes intermittently (usually a hydration or overlay race, never a product bug).
- A test passes locally but fails in CI (asset build, database, or seed state).
- Reviewing a PR whose tests parse HTML instead of asserting Inertia props.

## What's inside

```
inertia-test-harness/
  SKILL.md
  assets/support/domain_data.rb
  assets/support/session_test_helper.rb
  references/builders.md
  references/integration.md
  references/system-tests.md
```

`SKILL.md` is a router (kept under 250 lines) — the depth lives in `references/`, and the
copy-in code lives in `assets/`.

## Validate

```bash
./bin/check-skill
```

Checks frontmatter, the activation section, link resolution, orphaned references, script
executability, leftover placeholders, and — when the source app is checked out next to this
repository — that vendored scripts still match it byte for byte. Runs in CI on every push.

## Related skills

- [`inertia-vertical-slice`](https://github.com/mahardikalgw/inertia-vertical-slice) — route → skinny controller → query/service → typed props → Inertia page → test
- [`scoped-authorization`](https://github.com/mahardikalgw/scoped-authorization) — scopes, 404-not-403, explicit public opt-outs, isolation by construction
- [`rag-knowledge-loop`](https://github.com/mahardikalgw/rag-knowledge-loop) — approved corpus, fused retrieval, reply guardrails, offline test doubles

## Licence

MIT — see [LICENSE](LICENSE).
