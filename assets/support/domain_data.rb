# Copy into test/support/domain_data.rb. Explicit rows beat fixtures here because numbering is a
# sequence and aggregates need known values. Keep callers free of setup they do not care about.
module DomainData
  def create_domain_workspace(name: "Test Workspace")
    workspace = Workspace.create!(name: "#{name} #{next_seq(:workspace)}", plan: "standard", currency: "IDR")
    HelpdeskSetting.for(workspace)
    workspace
  end

  def create_domain_user(workspace:, role: "requester", name: nil, email_address: nil, active: true, **attrs)
    n = next_seq(:user)
    User.create!(
      name: name || "#{role.capitalize} #{n}",
      email_address: email_address || "#{role}#{n}@example.test",
      password: "password123", role: role, active: active, workspace: workspace, **attrs
    )
  end

  def create_team(workspace:, name: nil, **attrs)
    SupportTeam.create!(workspace: workspace, name: name || "Tim #{next_seq(:team)}", **attrs)
  end

  def create_category(workspace:, name: nil, security_sensitive: false, **attrs)
    Category.create!(
      workspace: workspace, name: name || "Kategori #{next_seq(:category)}",
      security_sensitive: security_sensitive, **attrs
    )
  end

  def create_service(workspace:, name: nil, **attrs)
    Service.create!(workspace: workspace, name: name || "Layanan #{next_seq(:service)}", **attrs)
  end

  def create_ticket(workspace:, requester:, status: "open", priority: "normal", **attrs)
    seq = next_seq(:ticket)
    Ticket.create!(
      workspace: workspace,
      requester: requester,
      created_by: attrs.delete(:created_by) || requester,
      category: attrs.delete(:category) || create_category(workspace: workspace),
      ticket_number: format("CMP-2026-%06d", seq),
      title: attrs.delete(:title) || "Tidak bisa masuk email #{seq}",
      description: attrs.delete(:description) || "Sejak pagi tidak bisa masuk email kampus.",
      status: status,
      priority: priority,
      last_activity_at: attrs.delete(:last_activity_at) || Time.current,
      **attrs
    )
  end

  def create_comment(ticket:, author:, visibility: "public", body: "Mohon dibantu, terima kasih.")
    TicketComment.create!(workspace: ticket.workspace, ticket: ticket, author: author,
                          visibility: visibility, body: body)
  end

  def create_event(ticket:, event_type: "ticket_created", actor: nil, **attrs)
    TicketEvent.create!(workspace: ticket.workspace, ticket: ticket, actor: actor,
                        event_type: event_type, **attrs)
  end

  def create_notification(ticket:, user:, kind: "ticket_created", **attrs)
    Notification.create!(workspace: ticket.workspace, ticket: ticket, user: user, kind: kind, **attrs)
  end

  private
    # Thread-local, not a class variable: a class variable survives across tests and makes numbering
    # order-dependent the moment parallelism is enabled.
    def next_seq(key)
      Thread.current[key] = Thread.current[key].to_i + 1
    end
end

ActiveSupport.on_load(:active_support_test_case) { include DomainData }
