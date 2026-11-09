# Builders instead of fixtures

A fixture is a row that exists before the test starts and cannot be reasoned about locally. A builder
is a function call at the top of `setup` where the reader can see exactly what the world contains.

## The rule

- `test/fixtures/*.yml` holds only what the framework needs to boot (a user for session tests).
- Everything with a sequence, a counter, an aggregate or a scope is built.
- Builders are plain modules in `test/support/`, auto-required and mixed into `ActiveSupport::TestCase`.
- Every builder has defaults that produce a *valid* record, and keyword arguments for anything a test
  needs to vary.

## Shape

```ruby
module HelpdeskData
  def create_helpdesk_workspace(name: "Test Workspace")
    workspace = create_workspace(name: name)
    HelpdeskSetting.for(workspace)      # a workspace without settings cannot create a ticket
    workspace
  end

  def create_helpdesk_user(workspace:, role: "requester", name: nil, email_address: nil, **attrs)
    n = (Thread.current[:user_seq] = Thread.current[:user_seq].to_i + 1)
    User.create!(
      name: name || "#{role.capitalize} #{n}",
      email_address: email_address || "#{role}#{n}@example.test",
      password: "password123", role: role, workspace: workspace, **attrs
    )
  end

  def create_team(workspace:, name: "Jaringan", **attrs)
    SupportTeam.create!(workspace: workspace, name: name, **attrs)
  end

  def create_ticket(workspace:, requester:, status: "open", priority: "normal", **attrs)
    seq = (Thread.current[:ticket_seq] = Thread.current[:ticket_seq].to_i + 1)
    Ticket.create!(
      workspace: workspace, requester: requester, created_by: requester,
      ticket_number: format("CMP-2026-%06d", seq), status: status, priority: priority,
      category: attrs.delete(:category) || create_category(workspace: workspace, name: "Kategori #{seq}"),
      **attrs
    )
  end
end

ActiveSupport.on_load(:active_support_test_case) { include HelpdeskData }
```

Three details that matter:

1. **`Thread.current` for the sequence**, not a class variable. A class variable survives across
   tests and makes numbering order-dependent the moment parallelism is switched on.
2. **A unique default per call.** `User.create!(email_address: "agent@example.test")` in two builders
   raises a uniqueness error; the counter makes every default unique.
3. **Dependencies filled in, not required.** `create_ticket` builds its own category so a test that
   does not care about categories says nothing about them; a test that does care passes one.

## The corpus and its exclusions

A builder module can hold two layers:

- **Structural builders** (`create_ticket`, `create_comment`, `create_team`) — the shapes every test
  needs.
- **Corpus builders** (`create_campus_it_corpus`, `create_conversation_corpus`) — a realistic dataset
  for a retrieval or reporting test, kept in a constant so a test can assert against known values.

Keep the whole module under ~100 lines. Past that it is a fixture file with extra steps, and the next
person will not read it.

## Session helper

```ruby
module SessionTestHelper
  def sign_in_as(user)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |jar|
      jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = jar[:session_id]
    end
  end

  def sign_out
    Current.session&.destroy!
    cookies.delete("session_id")
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
```

Signing in by inserting a session row (rather than posting to the session route) keeps every
integration test independent of the authentication UI. One test per project should still cover the
real sign-in route.

## Scripted collaborators

Anything that reaches the network in production gets a scripted double in `test/support/`, injected
through the same seam the production code uses:

```ruby
class AiFake
  attr_reader :calls

  def initialize(triage: {}, answer: "", error: nil)
    @triage = triage
    @answer = answer
    @error = error
    @calls = []
  end

  def available? = @error.nil?

  def complete(messages:, json: false, **)
    @calls << { messages: messages, json: json }
    raise @error if @error

    json && !chooser_prompt?(messages) ? JSON.generate(@triage) : @answer
  end

  def last_prompt = @calls.last&.dig(:messages)&.map { |m| m[:content] }&.join("\n").to_s

  private
    def chooser_prompt?(messages)
      Array(messages).any? { |message| message[:content].to_s.include?("<KNOWLEDGE>\n") }
    end
end
```

Rules for doubles:

- A double belongs in `test/support/`, never under `app/`. Production code must never be able to
  answer a real user with canned text.
- The double stands in at the *boundary* (`Ai.client`), not at the caller, so the rules above the
  boundary are still exercised.
- `calls` is recorded so a test can assert what was sent — that is how "no ticket, comment or user row
  reaches the prompt" becomes a test rather than a comment.
