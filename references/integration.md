# Integration tests

`ActionDispatch::IntegrationTest` is the workhorse: it exercises the real route, the real controller,
the real authorization, and the real props, in milliseconds.

## Assertions

```ruby
get ticket_path(ticket.ticket_number)
assert_response :success
assert_inertia_component "tickets/show"
assert_inertia_props do |props|
  assert_equal ticket.ticket_number, props[:ticket][:ticket_number]
  assert_equal 3, props[:comments].size
end
```

- `assert_inertia_component` pins the page a route renders. A typo in the component path is a runtime
  500 in production and a passing test in CI if nobody asserts it.
- `assert_inertia_props` (block form) hashes the props, so symbol keys are the norm.
- Assert the *shape* the client depends on, not the whole payload: `props[:comments].first` keys,
  `props[:pagination][:total]`. A test that pins every field fails on every cosmetic change and
  teaches the team to update expectations blindly.

## Status codes carry the decision

```ruby
test "a foreign ticket is 404, a forbidden action is 403" do
  sign_in_as @agent

  get ticket_path(@other_workspace_ticket.ticket_number)
  assert_response :not_found            # existence is never confirmed

  get new_ticket_path
  assert_response :forbidden            # the role may not do this at all
end
```

Two different statuses for two different refusals. Asserting `assert_response :success` with a flash
message instead would hide the authorization boundary behind copy.

## Redirects, flash and caching

```ruby
post tickets_path, params: { title: "…", description: "…", category_id: @category.id, form_token: SecureRandom.uuid }

assert_redirected_to ticket_path(Ticket.order(:id).last.ticket_number)
assert_equal "created", flash[:notice] ? "created" : nil
assert_turbo_or_see_other_redirect   # see below
```

A write redirect uses `status: :see_other` so a refresh does not re-post. Assert it:

```ruby
assert_response :see_other
```

For a per-user page, assert the cache header:

```ruby
get queue_path
assert_equal "no-store", response.headers["Cache-Control"]
```

## Form tokens and duplicate submits

```ruby
test "the same form token never creates a second ticket" do
  sign_in_as @requester
  token = SecureRandom.uuid

  2.times { post tickets_path, params: { title: "…", description: "…", category_id: @category.id, form_token: token } }

  assert_equal 1, Ticket.count
end
```

## Uploads

```ruby
file = Rack::Test::UploadedFile.new(StringIO.new("bukti"), "text/plain", original_filename: "bukti.txt")
post tickets_path, params: { …, files: [ file ] }

assert_equal 1, Ticket.order(:id).last.files.count
```

A file validation test asserts the refusal, not only the accept:

```ruby
post tickets_path, params: { …, files: [ Rack::Test::UploadedFile.new(StringIO.new("x" * 20.megabytes), "application/pdf", original_filename: "big.pdf") ] }
assert_redirected_to new_ticket_path
assert_equal 0, Ticket.count
```

## Jobs and mail

```ruby
assert_enqueued_with(job: NotificationDeliveryJob) do
  post ticket_comments_path(ticket.ticket_number), params: { body: "Terima kasih" }
end

assert_emails 1 do
  Tickets::Notify.call(ticket: @ticket, kind: "ticket_reply", actor: @agent)
end
```

Never assert on a rendered mail body when the assertion is really about the ledger row; assert the
`Notification` record and let the mailer test cover the template.

## What each layer owns

| Layer | Owns | Does not own |
|---|---|---|
| Model test | validations, scopes, derived attributes, label methods | HTTP, props |
| Service test | every branch of the operation, transaction outcome, typed errors | routes, rendering |
| Query test | filtering, ordering, scoping, pagination bounds | authorization decisions (policy test does) |
| Integration test | route + auth + component + props shape | visual layout |
| System test | the single critical journey | every edge case (too slow) |

## Anti-patterns

- `sleep` anywhere. Wait for a state (`assert_selector`, `assert_no_selector`, `perform_enqueued_jobs`).
- Asserting on `response.body.include?("Open")` to check a label — assert the prop, which is where the
  label came from.
- Building the world inside the test body instead of `setup` — the failure message then points at the
  assertion, not at the fixture.
- `assert_equal Ticket.count, 1` after a request that enqueues work; run the queue first or assert the
  enqueued job.
