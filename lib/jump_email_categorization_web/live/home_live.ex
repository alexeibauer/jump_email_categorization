defmodule JumpEmailCategorizationWeb.HomeLive do
  use JumpEmailCategorizationWeb, :live_view

  alias JumpEmailCategorizationWeb.EmailComponents
  alias JumpEmailCategorization.Gmail
  alias JumpEmailCategorization.Categories

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    # Load Gmail accounts from database
    gmail_accounts = Gmail.list_gmail_accounts(user.id)

    # Load categories from database
    categories = Categories.list_categories(user.id)

    # Sample data - replace with actual data from Gmail API later
    emails = [
      %{
        id: "1",
        subject: "Subject 1",
        summary: "Summary of email 1 with a brief description of the email contents",
        content:
          "Email actual content text for Subject 1.\n\nThis is the full body of the email message that will be displayed when the user clicks on this email in the list."
      },
      %{
        id: "2",
        subject: "Subject 2",
        summary: "Summary of email 1 with a brief description of the email contents",
        content:
          "Email actual content text for Subject 2.\n\nThis is the full body of the email message that will be displayed when the user clicks on this email in the list."
      },
      %{
        id: "3",
        subject: "Subject 3",
        summary: "Summary of email 1 with a brief description of the email contents",
        content:
          "Email actual content text for Subject 3.\n\nThis is the full body of the email message that will be displayed when the user clicks on this email in the list."
      }
    ]

    socket =
      socket
      |> assign(:emails, emails)
      |> assign(:gmail_accounts, gmail_accounts)
      |> assign(:categories, categories)
      |> assign(:selected_account, "all")
      |> assign(:selected_category, "")
      |> assign(:selected_email_id, "1")
      |> assign(:selected_email, Enum.find(emails, &(&1.id == "1")))
      |> assign(:selected_for_unsubscribe, [])
      |> assign(:show_delete_modal, false)
      |> assign(:delete_account_email, "")
      |> assign(:delete_account_id, nil)
      |> assign(:show_add_category_modal, false)
      |> assign(:category_form, to_form(Categories.change_category(%Categories.Category{})))
      |> assign(:show_delete_category_modal, false)
      |> assign(:category_to_delete, "")

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
  def handle_event("show-delete-account-modal", %{"id" => account_id, "email" => email}, socket) do
    socket =
      socket
      |> assign(:show_delete_modal, true)
      |> assign(:delete_account_email, email)
      |> assign(:delete_account_id, account_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-delete-account", _params, socket) do
    socket =
      socket
      |> assign(:show_delete_modal, false)
      |> assign(:delete_account_email, "")
      |> assign(:delete_account_id, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("confirm-delete-account", %{"id" => account_id}, socket) do
    user = socket.assigns.current_scope.user

    # Parse the account_id (it comes as a string from phx-value)
    account_id = String.to_integer(account_id)

    case Gmail.get_gmail_account!(account_id) do
      nil ->
        socket =
          socket
          |> put_flash(:error, "Account not found")
          |> assign(:show_delete_modal, false)

        {:noreply, socket}

      account ->
        # Verify the account belongs to the current user
        if account.user_id == user.id do
          # Revoke OAuth access from Google
          Gmail.revoke_oauth_access(account)

          # Delete from database
          case Gmail.delete_gmail_account(account) do
            {:ok, _} ->
              # Reload Gmail accounts
              gmail_accounts = Gmail.list_gmail_accounts(user.id)

              socket =
                socket
                |> assign(:gmail_accounts, gmail_accounts)
                |> assign(:show_delete_modal, false)
                |> assign(:delete_account_email, "")
                |> assign(:delete_account_id, nil)
                |> put_flash(:info, "Gmail account disconnected successfully")

              {:noreply, socket}

            {:error, _changeset} ->
              socket =
                socket
                |> put_flash(:error, "Failed to delete account")
                |> assign(:show_delete_modal, false)

              {:noreply, socket}
          end
        else
          socket =
            socket
            |> put_flash(:error, "Unauthorized")
            |> assign(:show_delete_modal, false)

          {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("select-category", %{"category" => category_name}, socket) do
    {:noreply, assign(socket, :selected_category, category_name)}
  end

  @impl true
  def handle_event("show-delete-category-modal", %{"category" => category_name}, socket) do
    socket =
      socket
      |> assign(:show_delete_category_modal, true)
      |> assign(:category_to_delete, category_name)

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-delete-category", _params, socket) do
    socket =
      socket
      |> assign(:show_delete_category_modal, false)
      |> assign(:category_to_delete, "")

    {:noreply, socket}
  end

  @impl true
  def handle_event("confirm-delete-category", %{"category" => category_name}, socket) do
    user = socket.assigns.current_scope.user

    # Find the category by name and user_id
    case Enum.find(socket.assigns.categories, &(&1.name == category_name)) do
      nil ->
        socket =
          socket
          |> put_flash(:error, "Category not found")
          |> assign(:show_delete_category_modal, false)

        {:noreply, socket}

      category ->
        case Categories.delete_category(category) do
          {:ok, _} ->
            # Reload categories
            categories = Categories.list_categories(user.id)

            socket =
              socket
              |> assign(:categories, categories)
              |> assign(:selected_category, "")
              |> assign(:show_delete_category_modal, false)
              |> assign(:category_to_delete, "")
              |> put_flash(:info, "Category deleted successfully")

            {:noreply, socket}

          {:error, _changeset} ->
            socket =
              socket
              |> put_flash(:error, "Failed to delete category")
              |> assign(:show_delete_category_modal, false)

            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("show-add-category-modal", _params, socket) do
    changeset = Categories.change_category(%Categories.Category{})

    socket =
      socket
      |> assign(:show_add_category_modal, true)
      |> assign(:category_form, to_form(changeset))

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-add-category", _params, socket) do
    socket =
      socket
      |> assign(:show_add_category_modal, false)
      |> assign(:category_form, to_form(Categories.change_category(%Categories.Category{})))

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate-category", %{"category" => category_params}, socket) do
    user = socket.assigns.current_scope.user

    changeset =
      %Categories.Category{}
      |> Categories.change_category(Map.put(category_params, "user_id", user.id))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :category_form, to_form(changeset))}
  end

  @impl true
  def handle_event("create-category", %{"category" => category_params}, socket) do
    user = socket.assigns.current_scope.user

    case Categories.create_category(Map.put(category_params, "user_id", user.id)) do
      {:ok, _category} ->
        # Reload categories
        categories = Categories.list_categories(user.id)

        socket =
          socket
          |> assign(:categories, categories)
          |> assign(:show_add_category_modal, false)
          |> assign(:category_form, to_form(Categories.change_category(%Categories.Category{})))
          |> put_flash(:info, "Category created successfully")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :category_form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Three-column layout --%>
      <div class="h-full grid grid-cols-[290px_1fr_2fr] overflow-hidden">
        <%!-- Left Sidebar: Gmail accounts --%>
        <EmailComponents.sidebar accounts={@gmail_accounts} selected_account={@selected_account} />

        <%!-- Middle Column: Email list --%>
        <EmailComponents.email_list
          emails={@emails}
          categories={@categories}
          selected_category={@selected_category}
          selected_email_id={@selected_email_id}
          selected_for_unsubscribe={@selected_for_unsubscribe}
          show_add_category_modal={@show_add_category_modal}
          category_form={@category_form}
          show_delete_category_modal={@show_delete_category_modal}
          category_to_delete={@category_to_delete}
        />

        <%!-- Right Column: Email detail --%>
        <EmailComponents.email_detail email={@selected_email} />
      </div>

      <%!-- Unsubscribe Toast --%>
      <EmailComponents.unsubscribe_toast
        show={length(@selected_for_unsubscribe) > 0}
        selected_count={length(@selected_for_unsubscribe)}
      />

      <%!-- Delete Account Confirmation Modal --%>
      <EmailComponents.delete_account_modal
        show={@show_delete_modal}
        account_email={@delete_account_email}
        account_id={@delete_account_id}
      />
    </Layouts.app>
    """
  end
end
