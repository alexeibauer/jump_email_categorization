defmodule JumpEmailCategorizationWeb.HomeLive do
  use JumpEmailCategorizationWeb, :live_view

  alias JumpEmailCategorizationWeb.EmailComponents
  alias JumpEmailCategorization.{Gmail, Categories, Emails}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    # Load Gmail accounts from database
    gmail_accounts = Gmail.list_gmail_accounts(user.id)

    # Subscribe to PubSub for each account to track fetching status
    Enum.each(gmail_accounts, fn account ->
      Phoenix.PubSub.subscribe(
        JumpEmailCategorization.PubSub,
        "gmail_account:#{account.id}"
      )
    end)

    # Subscribe to user emails for real-time updates
    Phoenix.PubSub.subscribe(
      JumpEmailCategorization.PubSub,
      "user_emails:#{user.id}"
    )

    # Load categories from database
    categories = Categories.list_categories(user.id)

    # Load paginated emails from database
    pagination = Emails.list_emails_paginated(user.id, page: 1, page_size: 30)

    # Select first email if any exist
    selected_email = List.first(pagination.emails)
    selected_email_id = if selected_email, do: selected_email.id, else: nil

    socket =
      socket
      |> assign(:emails, pagination.emails)
      |> assign(:pagination, pagination)
      |> assign(:gmail_accounts, gmail_accounts)
      |> assign(:categories, categories)
      |> assign(:selected_account, "all")
      |> assign(:selected_category, "")
      |> assign(:selected_email_id, selected_email_id)
      |> assign(:selected_email, selected_email)
      |> assign(:selected_for_unsubscribe, [])
      |> assign(:show_delete_modal, false)
      |> assign(:delete_account_email, "")
      |> assign(:delete_account_id, nil)
      |> assign(:show_add_category_modal, false)
      |> assign(:category_form, to_form(Categories.change_category(%Categories.Category{})))
      |> assign(:show_delete_category_modal, false)
      |> assign(:category_to_delete, "")
      |> assign(:fetching_accounts, MapSet.new())
      |> assign(:loading_message, nil)
      |> assign(:categorizing_emails, MapSet.new())
      |> assign(:summarizing_emails, MapSet.new())

    {:ok, socket}
  end

  @impl true
  def handle_info({:fetching_emails, account_id}, socket) do
    fetching_accounts = MapSet.put(socket.assigns.fetching_accounts, account_id)

    socket =
      socket
      |> assign(:fetching_accounts, fetching_accounts)
      |> maybe_update_loading_message()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:fetch_complete, account_id}, socket) do
    fetching_accounts = MapSet.delete(socket.assigns.fetching_accounts, account_id)

    socket =
      socket
      |> assign(:fetching_accounts, fetching_accounts)
      |> reload_emails()
      |> maybe_update_loading_message()
      |> put_flash(:info, "Emails loaded successfully")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_email, _email}, socket) do
    # Reload emails when a new email is created
    socket = reload_emails(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:email_updated, updated_email}, socket) do
    require Logger

    Logger.info(
      "LiveView received email_updated for email #{updated_email.id}, summary present: #{!!updated_email.summary}, category: #{inspect(updated_email.category)}"
    )

    # Update the email in the list
    emails =
      Enum.map(socket.assigns.emails, fn email ->
        if email.id == updated_email.id, do: updated_email, else: email
      end)

    # Also update selected_email if it's the one being updated
    selected_email =
      if socket.assigns.selected_email && socket.assigns.selected_email.id == updated_email.id do
        updated_email
      else
        socket.assigns.selected_email
      end

    # Remove from processing sets
    categorizing_emails = MapSet.delete(socket.assigns.categorizing_emails, updated_email.id)
    summarizing_emails = MapSet.delete(socket.assigns.summarizing_emails, updated_email.id)

    Logger.info(
      "Updated email list, removed from processing sets. Summarizing: #{MapSet.size(summarizing_emails)}, Categorizing: #{MapSet.size(categorizing_emails)}"
    )

    socket =
      socket
      |> assign(:emails, emails)
      |> assign(:selected_email, selected_email)
      |> assign(:categorizing_emails, categorizing_emails)
      |> assign(:summarizing_emails, summarizing_emails)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select-account", %{"id" => account_id}, socket) do
    # Reset to page 1 when switching accounts
    socket =
      socket
      |> assign(:selected_account, account_id)
      |> assign(:selected_category, "")
      |> update(:pagination, fn pagination -> %{pagination | page: 1} end)
      |> reload_emails()

    {:noreply, socket}
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
  def handle_event("select-email", %{"id" => email_id_str}, socket) do
    email_id = String.to_integer(email_id_str)
    email = Enum.find(socket.assigns.emails, &(&1.id == email_id))

    socket =
      socket
      |> assign(:selected_email_id, email_id)
      |> assign(:selected_email, email)

    {:noreply, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    user = socket.assigns.current_scope.user

    pagination = Emails.list_emails_paginated(user.id, page: page, page_size: 30)

    # If current selected email is not in new page, select first email
    selected_email_id = socket.assigns.selected_email_id
    email_ids = Enum.map(pagination.emails, & &1.id)

    {selected_email_id, selected_email} =
      if selected_email_id in email_ids do
        email = Enum.find(pagination.emails, &(&1.id == selected_email_id))
        {selected_email_id, email}
      else
        first_email = List.first(pagination.emails)
        {if(first_email, do: first_email.id, else: nil), first_email}
      end

    socket =
      socket
      |> assign(:emails, pagination.emails)
      |> assign(:pagination, pagination)
      |> assign(:selected_email_id, selected_email_id)
      |> assign(:selected_email, selected_email)

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
          # Delete account (this stops push notifications, revokes OAuth, and deletes from DB)
          case Gmail.delete_gmail_account(account) do
            {:ok, _} ->
              # Reload Gmail accounts
              gmail_accounts = Gmail.list_gmail_accounts(user.id)

              socket =
                socket
                |> assign(:gmail_accounts, gmail_accounts)
                |> reload_emails()
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
    # Reset to page 1 when switching categories
    socket =
      socket
      |> assign(:selected_category, category_name)
      |> update(:pagination, fn pagination -> %{pagination | page: 1} end)
      |> reload_emails()

    {:noreply, socket}
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
              |> reload_emails()
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
  def handle_event("categorize-email", %{"id" => email_id_str}, socket) do
    email_id = String.to_integer(email_id_str)

    # Add email to categorizing set
    categorizing_emails = MapSet.put(socket.assigns.categorizing_emails, email_id)

    # Enqueue job to categorize email
    case %{email_id: email_id, action: "categorize"}
         |> JumpEmailCategorization.Workers.EmailProcessorWorker.new()
         |> Oban.insert() do
      {:ok, _job} ->
        IO.puts("✓ Categorization job enqueued for email #{email_id}")

        socket =
          socket
          |> assign(:categorizing_emails, categorizing_emails)
          |> put_flash(:info, "Categorizing email...")

        {:noreply, socket}

      {:error, reason} ->
        IO.puts("✗ Failed to enqueue categorization job: #{inspect(reason)}")

        socket =
          socket
          |> put_flash(:error, "Failed to enqueue categorization job")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("summarize-email", %{"id" => email_id_str}, socket) do
    require Logger
    email_id = String.to_integer(email_id_str)

    Logger.info("Summarize-email event triggered for email #{email_id}")

    # Add email to summarizing set
    summarizing_emails = MapSet.put(socket.assigns.summarizing_emails, email_id)

    # Enqueue job to summarize email
    case %{email_id: email_id, action: "summarize"}
         |> JumpEmailCategorization.Workers.EmailProcessorWorker.new()
         |> Oban.insert() do
      {:ok, _job} ->
        Logger.info("✓ Summarization job enqueued for email #{email_id}")

        socket =
          socket
          |> assign(:summarizing_emails, summarizing_emails)
          |> put_flash(:info, "Summarizing email...")

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("✗ Failed to enqueue summarization job: #{inspect(reason)}")

        socket =
          socket
          |> put_flash(:error, "Failed to enqueue summarization job")

        {:noreply, socket}
    end
  end

  defp reload_emails(socket) do
    user = socket.assigns.current_scope.user
    current_page = socket.assigns.pagination.page
    selected_account = socket.assigns.selected_account
    selected_category = socket.assigns.selected_category

    # Build filter options
    filter_opts = [page: current_page, page_size: 30]

    filter_opts =
      if selected_account != "all" do
        case Integer.parse(selected_account) do
          {account_id, _} -> Keyword.put(filter_opts, :gmail_account_id, account_id)
          :error -> filter_opts
        end
      else
        filter_opts
      end

    # Add category filter if selected
    filter_opts =
      if selected_category != "" do
        Keyword.put(filter_opts, :category_name, selected_category)
      else
        filter_opts
      end

    pagination = Emails.list_emails_paginated(user.id, filter_opts)

    # If current selected email still exists, keep it selected
    selected_email_id = socket.assigns.selected_email_id
    email_ids = Enum.map(pagination.emails, & &1.id)

    {selected_email_id, selected_email} =
      if selected_email_id && selected_email_id in email_ids do
        email = Enum.find(pagination.emails, &(&1.id == selected_email_id))
        {selected_email_id, email}
      else
        first_email = List.first(pagination.emails)
        {if(first_email, do: first_email.id, else: nil), first_email}
      end

    socket
    |> assign(:emails, pagination.emails)
    |> assign(:pagination, pagination)
    |> assign(:selected_email_id, selected_email_id)
    |> assign(:selected_email, selected_email)
  end

  defp maybe_update_loading_message(socket) do
    cond do
      MapSet.size(socket.assigns.fetching_accounts) > 0 and
          socket.assigns.selected_account != "all" ->
        # Check if the selected account is being fetched
        selected_account_id =
          case Integer.parse(socket.assigns.selected_account) do
            {id, _} -> id
            :error -> nil
          end

        if selected_account_id &&
             MapSet.member?(socket.assigns.fetching_accounts, selected_account_id) do
          assign(socket, :loading_message, "Loading emails...")
        else
          assign(socket, :loading_message, nil)
        end

      MapSet.size(socket.assigns.fetching_accounts) > 0 ->
        assign(socket, :loading_message, "Loading emails...")

      true ->
        assign(socket, :loading_message, nil)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Three-column layout --%>
      <div class="h-full grid grid-cols-[290px_minmax(400px,1fr)_minmax(500px,2fr)] overflow-hidden">
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
          loading_message={@loading_message}
          pagination={@pagination}
          categorizing_emails={@categorizing_emails}
          summarizing_emails={@summarizing_emails}
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
