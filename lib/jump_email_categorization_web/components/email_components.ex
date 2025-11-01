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
              class={[
                "py-3",
                @selected_account == "all" && "active"
              ]}
            >
              All accounts
            </a>
          </li>
          <li :for={account <- @accounts}>
            <div class={[
              "flex items-center justify-between gap-2 px-4 py-3 hover:bg-base-200 rounded-lg",
              @selected_account == account.id && "bg-base-200"
            ]}>
              <a
                href="#"
                class="flex-1 truncate"
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
          <span class="text-lg">+</span>
          Add Gmail Account
        </a>
      </div>
    </div>
    """
  end

  @doc """
  Renders the central email list with category selector.
  """
  attr :emails, :list, default: []
  attr :selected_category, :string, default: ""
  attr :selected_email_id, :string, default: ""
  attr :selected_for_unsubscribe, :list, default: []

  def email_list(assigns) do
    ~H"""
    <div class="h-full flex flex-col border-r border-base-300 bg-base-100">
      <div class="p-4 border-b border-base-300">
        <div class="flex gap-2">
          <select class="select select-bordered flex-1">
            <option disabled selected>Choose a category...</option>
            <option>Work</option>
            <option>Personal</option>
            <option>Promotions</option>
            <option>Social</option>
          </select>
          <button class="btn btn-primary gap-2" onclick="add_category_modal.showModal()">
            <span class="text-lg">+</span>
            Add
          </button>
        </div>
        <p class="text-sm mt-3 text-base-content/70">
          Showing category <%= if @selected_category != "", do: "<#{@selected_category}>", else: "<Category selected>" %>
        </p>
      </div>
      <div class="flex-1 overflow-y-auto">
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
                  checked={email.id in @selected_for_unsubscribe}
                  phx-click="toggle-email-selection"
                  phx-value-id={email.id}
                />
              </label>
              <div
                class="flex-1 cursor-pointer"
                phx-click="select-email"
                phx-value-id={email.id}
              >
                <h3 class="font-bold text-base mb-2">{email.subject}</h3>
                <p class="text-sm text-base-content/70 line-clamp-2">
                  {email.summary}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Add Category Modal --%>
      <dialog id="add_category_modal" class="modal">
        <div class="modal-box">
          <form method="dialog">
            <button class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2">✕</button>
          </form>
          <h3 class="font-bold text-lg mb-4">Add New Category</h3>
          <div class="space-y-4">
            <div>
              <label class="label">
                <span class="label-text">Category Name</span>
              </label>
              <input
                type="text"
                placeholder="Enter category name..."
                class="input input-bordered w-full"
                id="category-name-input"
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text">Description</span>
              </label>
              <textarea
                placeholder="Enter category description..."
                class="textarea textarea-bordered w-full h-24"
                id="category-description-input"
              ></textarea>
            </div>
          </div>
          <div class="modal-action">
            <form method="dialog">
              <button class="btn btn-primary">Create Category</button>
            </form>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button>close</button>
        </form>
      </dialog>
    </div>
    """
  end

  @doc """
  Renders the email detail view on the right.
  """
  attr :email, :map, default: nil

  def email_detail(assigns) do
    ~H"""
    <div class="h-full flex flex-col bg-base-100">
      <div :if={@email} class="flex-1 overflow-y-auto">
        <div class="p-6">
          <h1 class="text-2xl font-bold mb-6">{@email.subject}</h1>
          <div class="border border-base-300 rounded-lg p-6 min-h-[400px]">
            <p class="text-base leading-relaxed whitespace-pre-wrap">
              {Map.get(@email, :content, "No content available")}
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
  Renders the unsubscribe toast that appears when emails are selected.
  """
  attr :selected_count, :integer, default: 0
  attr :show, :boolean, default: false

  def unsubscribe_toast(assigns) do
    ~H"""
    <div
      :if={@show && @selected_count > 0}
      class="fixed bottom-6 left-1/2 -translate-x-1/2 z-50 animate-in slide-in-from-bottom-4"
    >
      <div class="bg-base-100 shadow-2xl rounded-lg border border-base-300 px-6 py-4 flex items-center gap-6">
        <p class="text-base font-medium">
          Unsubscribe from {@selected_count} {if @selected_count == 1, do: "email", else: "emails"}?
        </p>
        <div class="flex gap-3">
          <button
            type="button"
            class="btn btn-primary btn-sm"
            phx-click="confirm-unsubscribe"
          >
            Yes
          </button>
          <button
            type="button"
            class="link link-hover text-sm"
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
end
