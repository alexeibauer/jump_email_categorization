defmodule JumpEmailCategorizationWeb.HomeLive do
  use JumpEmailCategorizationWeb, :live_view

  alias JumpEmailCategorizationWeb.EmailComponents

  @impl true
  def mount(_params, _session, socket) do
    # Sample data - replace with actual data from your database later
    emails = [
      %{
        id: "1",
        subject: "Subject 1",
        summary: "Summary of email 1 with a brief description of the email contents",
        content: "Email actual content text for Subject 1.\n\nThis is the full body of the email message that will be displayed when the user clicks on this email in the list."
      },
      %{
        id: "2",
        subject: "Subject 2",
        summary: "Summary of email 1 with a brief description of the email contents",
        content: "Email actual content text for Subject 2.\n\nThis is the full body of the email message that will be displayed when the user clicks on this email in the list."
      },
      %{
        id: "3",
        subject: "Subject 3",
        summary: "Summary of email 1 with a brief description of the email contents",
        content: "Email actual content text for Subject 3.\n\nThis is the full body of the email message that will be displayed when the user clicks on this email in the list."
      }
    ]

    accounts = [
      %{id: "account1", name: "Account 1"},
      %{id: "account2", name: "Account 2"}
    ]

    socket =
      socket
      |> assign(:emails, emails)
      |> assign(:accounts, accounts)
      |> assign(:selected_account, "all")
      |> assign(:selected_category, "")
      |> assign(:selected_email_id, "1")
      |> assign(:selected_email, Enum.find(emails, &(&1.id == "1")))
      |> assign(:selected_for_unsubscribe, [])

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle-email-selection", %{"id" => email_id}, socket) do
    selected = socket.assigns.selected_for_unsubscribe

    new_selected =
      if email_id in selected do
        List.delete(selected, email_id)
      else
        [email_id | selected]
      end

    {:noreply, assign(socket, :selected_for_unsubscribe, new_selected)}
  end

  @impl true
  def handle_event("select-email", %{"id" => email_id}, socket) do
    email = Enum.find(socket.assigns.emails, &(&1.id == email_id))

    socket =
      socket
      |> assign(:selected_email_id, email_id)
      |> assign(:selected_email, email)

    {:noreply, socket}
  end

  @impl true
  def handle_event("confirm-unsubscribe", _params, socket) do
    selected_ids = socket.assigns.selected_for_unsubscribe

    # TODO: Add your unsubscribe logic here
    # For now, just log the selected IDs
    IO.inspect(selected_ids, label: "Unsubscribing from emails")

    # Clear selection after processing
    socket =
      socket
      |> assign(:selected_for_unsubscribe, [])
      |> put_flash(:info, "Unsubscribed from #{length(selected_ids)} email(s)")

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-unsubscribe", _params, socket) do
    {:noreply, assign(socket, :selected_for_unsubscribe, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Three-column layout --%>
      <div class="h-full grid grid-cols-[250px_1fr_2fr] overflow-hidden">
        <%!-- Left Sidebar: Gmail accounts --%>
        <EmailComponents.sidebar accounts={@accounts} selected_account={@selected_account} />

        <%!-- Middle Column: Email list --%>
        <EmailComponents.email_list
          emails={@emails}
          selected_category={@selected_category}
          selected_email_id={@selected_email_id}
          selected_for_unsubscribe={@selected_for_unsubscribe}
        />

        <%!-- Right Column: Email detail --%>
        <EmailComponents.email_detail email={@selected_email} />
      </div>

      <%!-- Unsubscribe Toast --%>
      <EmailComponents.unsubscribe_toast
        show={length(@selected_for_unsubscribe) > 0}
        selected_count={length(@selected_for_unsubscribe)}
      />
    </Layouts.app>
    """
  end
end
