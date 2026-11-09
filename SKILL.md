---
name: inertia-test-harness
description: Author tests for a Rails + Inertia app the way its harness expects — minitest integration tests with inertia_rails/minitest assertions, domain builder objects instead of fixtures, service failure-branch tests, and Capybara system tests that survive Radix overlays. Use when adding tests, fixing a flaky system test, or adding a route that needs authentication coverage.
version: 2.0.0
---

# Inertia test harness

Three layers, three jobs: **models/services** prove rules, **integration** proves routes and props,
**system** proves the one journey a human must complete. The harness below is what keeps those three
from becoming five different testing styles.

## When to activate

- Writing a test for a new route, service, query, job or mailer.
- A system test flakes intermittently (usually a hydration or overlay race, never a product bug).
- A test passes locally but fails in CI (asset build, database, or seed state).
- Reviewing a PR whose tests parse HTML instead of asserting Inertia props.

## The rules that are not optional

### 1. Inertia responses are asserted as Inertia, not as HTML

```ruby
require "inertia_rails/minitest"   # once, in test_helper.rb

test "the queue renders the staff page with the filters echoed back" do
  sign_in_as @agent

  get queue_path(status: "open")

  assert_inertia_component "queue/index"
  assert_inertia_props do |props|
    assert_equal "open", props[:filters][:status]
    assert props[:tickets].all? { |ticket| ticket[:status] == "open" }
  end
end
```

Parsing `response.body` for markup couples the test to Tailwind classes and to the component tree. The
one exception is a *leak* test, where the assertion is that a string is **absent** from the body —
that is deliberately body-level (see `scoped-authorization`).

### 2. Every new route gets two tests: the happy path and the anonymous path

```ruby
test "anonymous visitors are redirected and the deep link is stored" do
  get teams_path
  assert_redirected_to root_path

  get team_path("T-1")
  assert_redirected_to root_path
end
```

A route that is public opts out explicitly with `allow_unauthenticated_access`; the test then asserts
200 **and** that the page renders for an anonymous visitor. "It works when signed in" is half a test.

### 3. Fixtures are for users; builders are for everything else

Aggregates with sequences, counters and natural keys are built, not fixtured. Ticket numbering is a
sequence, totals must be known, and a YAML fixture cannot express "a team leader who leads exactly
two teams". Builders live in `test/support/` and are auto-included.

### 4. One worker

```ruby
class ActiveSupport::TestCase
  parallelize(workers: 1)
end
```

With a Vite test build the workers race on `public/vite-test/.vite/manifest.json` and a loser reads an
empty file — roughly one run in six fails for reasons unrelated to the code. Either keep one worker, or
pre-build the assets once and disable `autoBuild` in the Vite test config. Do not "fix" a flake by
retrying.

### 5. Service tests cover the failure branches, not just the happy path

For a multi-step operation, the table of branches is the test list:

```
happy                 -> state + side effects + event row
not permitted         -> raises the typed error, nothing persisted
missing required data -> raises the typed error naming the missing field
already in target     -> no-op or refusal, never a duplicate event row
side effect fails     -> record still committed, error surfaced not swallowed
```

## Anatomy of one integration test

```ruby
require "test_helper"

class TeamsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = create_helpdesk_workspace
    @requester = create_helpdesk_user(workspace: @workspace)
    @agent = create_helpdesk_user(workspace: @workspace, role: "agent")
    @team = create_team(workspace: @workspace)
  end

  test "an agent sees only their own teams" do
    SupportTeamMembership.create!(support_team: @team, user: @agent)
    create_team(workspace: @workspace, name: "Tim Lain")
    sign_in_as @agent

    get teams_path

    assert_inertia_props do |props|
      assert_equal [ @team.name ], props[:teams].map { |team| team[:name] }
    end
  end
end
```

`setup` builds the smallest world that can fail. No shared mutable state between tests, no `let`, no
ordering assumptions.

## CI reality

- `npm install` is required **before** `bin/rails test` — the Vite test build needs it.
- Tests run against PostgreSQL, not SQLite; `db:test:prepare` before `test` in a fresh job.
- Replanting seeds in the test environment leaves committed rows behind, so the seeds step must end
  with `db:test:prepare` or the next run fails fixture FK validation.
- A system test needs Chrome; the CI job installs it and uploads `tmp/screenshots` on failure.

## References

- [references/integration.md](references/integration.md) — assertions, redirects, flash, uploads, jobs, mail
- [references/system-tests.md](references/system-tests.md) — Capybara with Radix selects, overlays, hydration
- [references/builders.md](references/builders.md) — the builder pattern and the helpers to copy in
- [assets/support/domain_data.rb](assets/support/domain_data.rb) — builder module to copy into `test/support/`
- [assets/support/session_test_helper.rb](assets/support/session_test_helper.rb) — `sign_in_as` / `sign_out`
