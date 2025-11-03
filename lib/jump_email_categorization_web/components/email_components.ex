defmodule JumpEmailCategorizationWeb.EmailComponents do
  @moduledoc """
  Provides email UI components.
  """
  use Phoenix.Component

  @doc """
  Renders the left sidebar with Gmail accounts.
  """
  attr :accounts, :list, default: []
  attr :selected_account, :string, default: "all"

  def sidebar(assigns) do
    ~H"""
    <div class="h-full flex flex-col border-r border-base-300 bg-base-100">
      <div class="flex-1 overflow-y-auto p-4">
        <h2 class="text-lg font-bold mb-4">Gmail accounts</h2>

        <div :if={@accounts == []} class="text-center py-8">
          <p class="text-base-content/70 mb-2">No accounts connected.</p>
          <a href="/auth/google" class="link link-primary">
            Connect your first account
          </a>
        </div>

        <ul :if={@accounts != []} class="menu menu-compact">
          <li>
            <a
              href="#"
              phx-click="select-account"
              phx-value-id="all"
              class={[
                "py-3",
                @selected_account == "all" && "font-bold underline"
              ]}
            >
              All accounts
            </a>
          </li>
          <li :for={account <- @accounts}>
            <div class={[
              "flex items-center justify-between gap-2 px-4 py-3 hover:bg-base-200 rounded-lg",
              @selected_account == to_string(account.id) && "bg-base-200"
            ]}>
              <a
                href="#"
                phx-click="select-account"
                phx-value-id={account.id}
                class={[
                  "flex-1 truncate",
                  @selected_account == to_string(account.id) && "font-bold underline"
                ]}
              >
                {account.email}
              </a>
              <button
                type="button"
                phx-click="show-delete-account-modal"
                phx-value-id={account.id}
                phx-value-email={account.email}
                class="btn btn-ghost btn-xs btn-square text-error hover:bg-error/10"
                title="Delete account"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="w-4 h-4"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0"
                  />
                </svg>
              </button>
            </div>
          </li>
        </ul>
      </div>
      <div class="p-4 border-t border-base-300">
        <a href="/auth/google" class="btn btn-primary w-full gap-2">
          <span class="text-lg">+</span> Add Gmail Account
        </a>
      </div>
    </div>
    """
  end

  @doc """
  Renders the central email list with category selector.
  """
  attr :emails, :list, default: []
  attr :categories, :list, default: []
  attr :selected_category, :string, default: ""
  attr :selected_email_id, :string, default: ""
  attr :selected_for_unsubscribe, :list, default: []
  attr :show_add_category_modal, :boolean, default: false
  attr :category_form, :map, default: nil
  attr :show_delete_category_modal, :boolean, default: false
  attr :category_to_delete, :string, default: ""
  attr :loading_message, :string, default: nil
  attr :pagination, :map, default: nil
  attr :categorizing_emails, :any, default: []
  attr :summarizing_emails, :any, default: []

  def email_list(assigns) do
    ~H"""
    <div class="h-full flex flex-col border-r border-base-300 bg-base-100 overflow-hidden">
      <div class="p-4 border-b border-base-300">
        <div class="flex gap-2">
          <form phx-change="select-category" class="flex-1">
            <select
              class="select select-bordered w-full"
              name="category"
            >
              <option value="" selected={@selected_category == ""}>
                All categories
              </option>
              <option
                :for={category <- @categories}
                value={category.name}
                selected={@selected_category == category.name}
              >
                {category.name}
              </option>
            </select>
          </form>
          <button
            type="button"
            class="btn btn-primary gap-2"
            phx-click="show-add-category-modal"
          >
            <span class="text-lg">+</span> Add
          </button>
        </div>
        <p class="text-sm mt-3 text-base-content/70">
          <%= if @selected_category != "" do %>
            Showing category: <span class="font-semibold">{@selected_category}</span>
            <a
              href="#"
              class="ml-2 text-error hover:underline"
              phx-click="show-delete-category-modal"
              phx-value-category={@selected_category}
            >
              (Delete)
            </a>
          <% else %>
            Showing all emails
          <% end %>
        </p>
      </div>
      <%!-- Select All Checkbox --%>
      <div
        :if={@emails != [] && !@loading_message}
        class="px-4 py-2 border-b border-base-300 bg-base-50"
      >
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            class="checkbox checkbox-sm"
            checked={
              length(@selected_for_unsubscribe) > 0 &&
                length(@selected_for_unsubscribe) == length(@emails)
            }
            phx-click="toggle-select-all"
          />
          <span class="text-sm font-medium">
            <%= if length(@selected_for_unsubscribe) > 0 do %>
              {length(@selected_for_unsubscribe)} selected
            <% else %>
              Select all
            <% end %>
          </span>
        </label>
      </div>
      <div class="flex-1 overflow-y-auto">
        <%= cond do %>
          <% @loading_message -> %>
            <div class="flex items-center justify-center h-full">
              <div class="text-center">
                <div class="loading loading-spinner loading-lg text-primary mb-4"></div>
                <p class="text-lg text-base-content/70">{@loading_message}</p>
              </div>
            </div>
          <% @emails == [] -> %>
            <div class="flex items-center justify-center h-full">
              <p class="text-lg text-base-content/50">No emails received yet</p>
            </div>
          <% true -> %>
            <div :for={email <- @emails} class="border-b border-base-300">
              <div class={[
                "p-4 hover:bg-base-200 transition-colors",
                @selected_email_id == email.id && "bg-base-200"
              ]}>
                <div class="flex gap-3">
                  <label class="cursor-pointer">
                    <input
                      type="checkbox"
                      class="checkbox checkbox-sm mt-1"
                      checked={to_string(email.id) in @selected_for_unsubscribe}
                      phx-click="toggle-email-selection"
                      phx-value-id={email.id}
                    />
                  </label>
                  <div
                    class="flex-1 cursor-pointer overflow-hidden"
                    phx-click="select-email"
                    phx-value-id={email.id}
                  >
                    <div class="flex items-baseline gap-2 mb-1">
                      <h3 class="font-bold text-base truncate flex-1">
                        {email.subject || "(No subject)"}
                      </h3>
                      <span
                        :if={email.received_at}
                        class="text-xs text-base-content/60 whitespace-nowrap"
                      >
                        {format_email_date(email.received_at)}
                      </span>
                    </div>

                    <%!-- Category info --%>
                    <div class="mb-2">
                      <%= if email.category do %>
                        <span class="text-xs bg-primary/10 text-primary px-2 py-1 rounded">
                          {email.category.name}
                        </span>
                      <% else %>
                        <%= if email.id in @categorizing_emails do %>
                          <span class="text-xs text-base-content/70">
                            <span class="loading loading-spinner loading-xs"></span> Categorizing...
                          </span>
                        <% else %>
                          <button
                            type="button"
                            class="text-xs text-primary hover:underline bg-transparent border-0 p-0 cursor-pointer"
                            phx-click="categorize-email"
                            phx-value-id={email.id}
                          >
                            Uncategorized. Click here to categorize now
                          </button>
                        <% end %>
                      <% end %>
                    </div>

                    <%!-- Summary info --%>
                    <%= if email.summary do %>
                      <p class="text-sm text-base-content/70 line-clamp-2 break-words">
                        {email.summary}
                      </p>
                    <% else %>
                      <%= if email.id in @summarizing_emails do %>
                        <p class="text-sm text-base-content/70">
                          <span class="loading loading-spinner loading-xs"></span> Summarizing...
                        </p>
                      <% else %>
                        <button
                          type="button"
                          class="text-sm text-primary hover:underline bg-transparent border-0 p-0 cursor-pointer"
                          phx-click="summarize-email"
                          phx-value-id={email.id}
                        >
                          Summary not available. Click here to summarize now.
                        </button>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
        <% end %>
      </div>

      <%!-- Pagination Controls --%>
      <%= if @pagination && @pagination.total_pages > 1 && !@loading_message do %>
        <div class="p-4 border-t border-base-300 bg-base-100">
          <div class="flex items-center justify-between">
            <div class="text-sm text-base-content/70">
              Page {@pagination.page} of {@pagination.total_pages}
              <span class="ml-2">
                ({@pagination.total_count} total emails)
              </span>
            </div>
            <div class="flex gap-2">
              <button
                type="button"
                class="btn btn-sm"
                phx-click="paginate"
                phx-value-page={@pagination.page - 1}
                disabled={!@pagination.has_prev}
              >
                ← Previous
              </button>
              <button
                type="button"
                class="btn btn-sm"
                phx-click="paginate"
                phx-value-page={@pagination.page + 1}
                disabled={!@pagination.has_next}
              >
                Next →
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Add Category Modal --%>
      <dialog :if={@show_add_category_modal} id="add_category_modal" class="modal modal-open">
        <div class="modal-box">
          <button
            type="button"
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
            phx-click="cancel-add-category"
          >
            ✕
          </button>
          <h3 class="font-bold text-lg mb-4">Add New Category</h3>
          <.form
            for={@category_form}
            id="category-form"
            phx-submit="create-category"
            phx-change="validate-category"
            class="space-y-4"
          >
            <div>
              <label class="label">
                <span class="label-text">Category Name</span>
              </label>
              <input
                type="text"
                name="category[name]"
                value={Phoenix.HTML.Form.input_value(@category_form, :name)}
                placeholder="Enter category name..."
                class="input input-bordered w-full"
                phx-debounce="300"
              />
              <label :if={@category_form.errors[:name]} class="label">
                <span class="label-text-alt text-error">
                  {translate_error(Keyword.get(@category_form.errors, :name))}
                </span>
              </label>
            </div>
            <div>
              <label class="label">
                <span class="label-text">Description</span>
              </label>
              <textarea
                name="category[description]"
                placeholder="Enter category description..."
                class="textarea textarea-bordered w-full h-24"
                phx-debounce="300"
              >{Phoenix.HTML.Form.input_value(@category_form, :description)}</textarea>
              <label :if={@category_form.errors[:description]} class="label">
                <span class="label-text-alt text-error">
                  {translate_error(Keyword.get(@category_form.errors, :description))}
                </span>
              </label>
            </div>
            <div class="modal-action">
              <button
                type="submit"
                class="btn btn-primary"
              >
                Create Category
              </button>
              <button
                type="button"
                class="btn"
                phx-click="cancel-add-category"
              >
                Cancel
              </button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop" phx-click="cancel-add-category"></div>
      </dialog>

      <%!-- Delete Category Modal --%>
      <dialog :if={@show_delete_category_modal} id="delete_category_modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-4">Delete Category</h3>
          <p class="py-4">
            Are you sure that you want to delete the category <span class="font-semibold">'{@category_to_delete}'</span>?
            Any email under this category will be re-categorized, or listed as "Uncategorized" if no match is found.
          </p>
          <div class="modal-action">
            <a
              style="margin-top: 5px;margin-right: 10px;"
              href="#"
              class="link link-hover"
              phx-click="cancel-delete-category"
            >
              Cancel
            </a>
            <button
              type="button"
              class="btn btn-error"
              phx-click="confirm-delete-category"
              phx-value-category={@category_to_delete}
            >
              Yes
            </button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="cancel-delete-category"></div>
      </dialog>
    </div>
    """
  end

  # Helper function to translate changeset errors
  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp translate_error(msg) when is_binary(msg), do: msg

  # Helper function to format email date (e.g., "Sun, Nov 2nd 2025")
  defp format_email_date(datetime) do
    day_suffix =
      case Calendar.strftime(datetime, "%d") |> String.to_integer() do
        d when d in [1, 21, 31] -> "st"
        d when d in [2, 22] -> "nd"
        d when d in [3, 23] -> "rd"
        _ -> "th"
      end

    day = Calendar.strftime(datetime, "%d") |> String.to_integer() |> to_string()

    Calendar.strftime(datetime, "%a, %b ") <>
      day <> day_suffix <> Calendar.strftime(datetime, " %Y")
  end

  @doc """
  Renders the email detail view on the right.
  """
  attr :email, :map, default: nil

  def email_detail(assigns) do
    ~H"""
    <div class="h-full flex flex-col bg-base-100 overflow-hidden">
      <div :if={@email} class="flex-1 overflow-y-auto">
        <div class="p-6">
          <h1 class="text-2xl font-bold mb-4 break-words">{@email.subject || "(No subject)"}</h1>

          <%!-- Email metadata --%>
          <div class="mb-6 text-sm text-base-content/70 space-y-1">
            <div :if={@email.from_name || @email.from_email} class="break-words">
              <span class="font-semibold">From:</span>
              {if @email.from_name, do: @email.from_name <> " <", else: ""}
              {@email.from_email || "Unknown"}
              {if @email.from_name, do: ">", else: ""}
            </div>
            <div :if={@email.received_at}>
              <span class="font-semibold">Date:</span>
              {Calendar.strftime(@email.received_at, "%B %d, %Y at %I:%M %p")}
            </div>
            <div :if={@email.summary} class="break-words">
              <span class="font-semibold">Summary:</span>
              {@email.summary}
            </div>

            <%!-- Unsubscribe Status --%>
            <div
              :if={@email.unsubscribe_status}
              class={[
                "mt-3 p-3 rounded-lg text-sm",
                @email.unsubscribe_status == "success" && "bg-success/10 text-success",
                @email.unsubscribe_status == "failed" && "bg-error/10 text-error",
                @email.unsubscribe_status == "processing" && "bg-info/10 text-info",
                @email.unsubscribe_status == "not_found" && "bg-warning/10 text-warning",
                @email.unsubscribe_status == "pending_confirmation" && "bg-warning/10 text-warning"
              ]}
            >
              <div class="font-semibold mb-1">Unsubscribe Status</div>

              <%= cond do %>
                <% @email.unsubscribe_status == "success" -> %>
                  <p>✓ Successfully unsubscribed</p>
                  <p :if={@email.unsubscribe_completed_at} class="text-xs mt-1 opacity-80">
                    Completed: {Calendar.strftime(
                      @email.unsubscribe_completed_at,
                      "%B %d, %Y at %I:%M %p"
                    )}
                  </p>
                <% @email.unsubscribe_status == "processing" -> %>
                  <p>
                    <span class="loading loading-spinner loading-xs"></span> Processing unsubscribe...
                  </p>
                <% @email.unsubscribe_status == "failed" -> %>
                  <p>✗ Unsubscribe failed</p>
                  <p :if={@email.unsubscribe_error} class="text-xs mt-1 opacity-80">
                    {@email.unsubscribe_error}
                  </p>
                <% @email.unsubscribe_status == "not_found" -> %>
                  <p>⚠ No unsubscribe link found in this email</p>
                <% @email.unsubscribe_status == "pending_confirmation" -> %>
                  <p>⏳ Pending manual confirmation</p>
                  <a
                    :if={@email.unsubscribe_link}
                    href={@email.unsubscribe_link}
                    target="_blank"
                    class="link text-xs mt-1 inline-block"
                  >
                    Complete unsubscribe manually →
                  </a>
                <% true -> %>
                  <p>Status: {@email.unsubscribe_status}</p>
              <% end %>

              <p :if={@email.unsubscribe_link} class="text-xs mt-2 opacity-70 break-all">
                Link:
                <a href={@email.unsubscribe_link} target="_blank" class="link">
                  {@email.unsubscribe_link}
                </a>
              </p>
            </div>
          </div>

          <%!-- Email body --%>
          <div class="border border-base-300 rounded-lg p-6 min-h-[400px]">
            <p class="text-base leading-relaxed whitespace-pre-wrap break-words overflow-wrap-anywhere">
              {@email.body || @email.snippet || "No content available"}
            </p>
          </div>
        </div>
      </div>
      <div :if={!@email} class="flex-1 flex items-center justify-center">
        <p class="text-base-content/50 text-lg">Select an email to view its content</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders the action toast that appears when emails are selected.
  """
  attr :selected_count, :integer, default: 0
  attr :show, :boolean, default: false

  def unsubscribe_toast(assigns) do
    ~H"""
    <div
      :if={@show && @selected_count > 0}
      class="fixed bottom-6 left-1/2 -translate-x-1/2 z-50 animate-in slide-in-from-bottom-4"
    >
      <div class="bg-base-100 shadow-2xl rounded-lg border border-base-300 px-6 py-4">
        <p class="text-base font-semibold mb-3">
          Additional actions on selected emails:
        </p>
        <div class="flex gap-3">
          <button
            type="button"
            class="btn btn-primary btn-sm"
            phx-click="confirm-unsubscribe"
          >
            Unsubscribe from {@selected_count} {if @selected_count == 1, do: "email", else: "emails"}
          </button>
          <button
            type="button"
            class="btn btn-error btn-sm text-white"
            phx-click="show-delete-emails-modal"
          >
            Delete {@selected_count} {if @selected_count == 1, do: "email", else: "emails"}
          </button>
          <button
            type="button"
            class="link link-hover text-sm self-center"
            phx-click="cancel-unsubscribe"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a confirmation modal for deleting a Gmail account.
  """
  attr :show, :boolean, default: false
  attr :account_email, :string, default: ""
  attr :account_id, :any, default: nil

  def delete_account_modal(assigns) do
    ~H"""
    <dialog :if={@show} id="delete_account_modal" class="modal modal-open">
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">Delete Gmail Account</h3>
        <p class="py-4">
          This will delete the account <span class="font-semibold">{@account_email}</span>.
          You can re-connect anytime later.
        </p>
        <div class="modal-action">
          <button
            type="button"
            class="btn btn-error"
            phx-click="confirm-delete-account"
            phx-value-id={@account_id}
          >
            Delete Account
          </button>
          <button type="button" class="btn" phx-click="cancel-delete-account">
            Cancel
          </button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel-delete-account">close</button>
      </form>
    </dialog>
    """
  end

  @doc """
  Renders a confirmation modal for deleting multiple emails.
  """
  attr :show, :boolean, default: false
  attr :selected_count, :integer, default: 0

  def delete_emails_modal(assigns) do
    ~H"""
    <dialog :if={@show} id="delete_emails_modal" class="modal modal-open">
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">Delete Emails</h3>
        <p class="py-4">
          Are you sure of deleting {@selected_count} {if @selected_count == 1,
            do: "email",
            else: "emails"}? <br />
          <span class="font-semibold text-error">
            This will also move the email to Gmail's Trash folder.
          </span>
        </p>
        <div class="modal-action">
          <button type="button" class="btn btn-error" phx-click="confirm-delete-emails">
            Yes, delete {@selected_count} {if @selected_count == 1, do: "email", else: "emails"}
          </button>
          <button type="button" class="link link-hover" phx-click="cancel-delete-emails">
            Cancel
          </button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel-delete-emails">close</button>
      </form>
    </dialog>
    """
  end
end
