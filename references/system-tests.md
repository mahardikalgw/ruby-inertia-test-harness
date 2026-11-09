# System tests with Radix overlays

System tests are the most expensive tests you own and the only ones that prove a human can complete a
journey. Keep exactly one per critical path, and keep the driver quirks in a helper so the test reads
as intent.

## Base class

```ruby
require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 900 ]

  def sign_in_as(user)
    # No sign-in form exists in this product; the session is posted directly.
    page.driver.post session_path, params: { email_address: user.email_address, password: "helpdesk123" }
    visit root_path
  end
end
```

Posting the session instead of driving a form is deliberate: the product's only entry point is Google
SSO, which cannot be automated, and a fake sign-in form in the test would be testing a page that does
not exist.

## The three driver quirks that cause every flake

### 1. A listbox opens on a real pointer event

Selenium's synthetic click does not produce the pointer sequence Radix listens for. Open with the
keyboard, which is also the path the product must support for accessibility:

```ruby
def choose_option(label, option)
  field_id = find("label", text: label, exact_text: true)[:for]
  wait_for_react_handler("##{field_id}", "onKeyDown")   # a key sent before React commits is lost

  3.times do
    find("##{field_id}").send_keys(:down)
    break if page.has_selector?("[role='option']", wait: 1)
  end

  assert_selector "[role='option']", text: option
  find("[role='option']", text: option, exact_text: true).click
  assert_selector "##{field_id}", text: option
  close_listbox
  wait_for_pointer_events
end
```

### 2. An open overlay blocks the next click

While a listbox or dialog is mounted, the library sets `pointer-events: none` on `body`. The next
click is swallowed and the following keystroke goes nowhere — which is how a form once submitted with
an empty description. Close deterministically (Escape) and wait for the guard to clear:

```ruby
def close_listbox
  Timeout.timeout(Capybara.default_max_wait_time) do
    sleep 0.05 until page.evaluate_script("!document.querySelector('[role=listbox]')")
  end
rescue Timeout::Error
  find("body").send_keys(:escape)
end

def wait_for_pointer_events
  Timeout.timeout(Capybara.default_max_wait_time) do
    sleep 0.05 until page.evaluate_script("getComputedStyle(document.body).pointerEvents !== 'none'")
  end
end
```

### 3. A cell can re-render between find and click

A calendar day cell is often replaced by React between the finder and the click. Drive the live element
in one script instead of two round trips:

```ruby
page.execute_script(<<~JS)
  const cell = document.querySelector('[data-day="2026-11-09"]')
  cell.dispatchEvent(new MouseEvent('click', { bubbles: true }))
JS
```

## Waiting, never sleeping

```ruby
assert_selector "[data-testid='ticket-row']", count: 3
assert_no_selector "[role='dialog']"
assert_text "Tiket dibuat"
```

Anything that needs a fixed `sleep` is a missing wait on a state that the DOM does expose. `sleep`
turns a race into a slower race.

## What a system test should cover

One journey, start to finish, through the product's own chrome:

```ruby
test "a requester raises a ticket and reads the reply" do
  sign_in_as @requester
  click_on "Buat permintaan"

  fill_in "Judul", with: "Tidak bisa masuk email kampus"
  choose_option "Kategori", "Akun & Kata Sandi"
  fill_in "Deskripsi", with: "Sejak pagi muncul pesan kata sandi salah."
  click_on "Kirim"

  assert_text "permintaan berhasil dibuat"
  assert_text "Tidak bisa masuk email kampus"
end
```

What it must not cover: every filter, every status transition, every validation message. Those are
integration tests, where they cost milliseconds instead of seconds.

## CI

- Headless Chrome only; the job installs Chrome and uploads `tmp/screenshots` when a test fails.
- Screenshots plus `page.html` on failure is the difference between a five-minute diagnosis and an
  hour of guessing.
- A system test that needs the asset build must run after `npm install`; the Vite manifest is the
  single most common cause of a red system-test job in a fresh environment.
