# SPDX-License-Identifier: AGPL-3.0-only
defmodule ValueFlows.Observe.Observation.Observations do
  import Bonfire.Common.Utils, only: [maybe_put: 3, attr_get_id: 2, maybe: 2, maybe_append: 2, map_key_replace: 3]

  import Bonfire.Common.Config, only: [repo: 0]

  # alias Bonfire.GraphQL
  alias Bonfire.GraphQL.{Fields, Page}

  @user Bonfire.Common.Config.get!(:user_schema)

  alias ValueFlows.Observe.Observation
  alias ValueFlows.Observe.EconomicResource.EconomicResources
  alias ValueFlows.Observe.Observation.Queries
  alias ValueFlows.Observe.Observation.EventSideEffects

  alias ValueFlows.Observe.Process.Processes

  import Bonfire.Fail.Error

  require Logger

  def cursor(), do: &[&1.id]
  def test_cursor(), do: &[&1["id"]]

  @doc """
  Retrieves a single one by arbitrary filters.
  Used by:
  * GraphQL Item queries
  * ActivityPub integration
  * Various parts of the codebase that need to query for this (inc. tests)
  """
  def one(filters), do: repo().single(Queries.query(Observation, filters))

  @doc """
  Retrieves a list of them by arbitrary filters.
  Used by:
  * Various parts of the codebase that need to query for this (inc. tests)
  """
  def many(filters \\ []), do: {:ok, repo().all(Queries.query(Observation, filters))}

  def fields(group_fn, filters \\ [])
      when is_function(group_fn, 1) do
    {:ok, fields} = many(filters)
    {:ok, Fields.new(fields, group_fn)}
  end

  @doc """
  Retrieves an Page of events according to various filters

  Used by:
  * GraphQL resolver single-parent resolution
  """
  def page(cursor_fn, page_opts, base_filters \\ [], data_filters \\ [], count_filters \\ [])

  def page(cursor_fn, %{} = page_opts, base_filters, data_filters, count_filters) do
    base_q = Queries.query(Observation, base_filters)
    data_q = Queries.filter(base_q, data_filters)
    count_q = Queries.filter(base_q, count_filters)

    with {:ok, [data, counts]} <- repo().transact_many(all: data_q, count: count_q) do
      {:ok, Page.new(data, counts, cursor_fn, page_opts)}
    end
  end

  @doc """
  Retrieves an Pages of events according to various filters

  Used by:
  * GraphQL resolver bulk resolution
  """
  def pages(
        cursor_fn,
        group_fn,
        page_opts,
        base_filters \\ [],
        data_filters \\ [],
        count_filters \\ []
      )

  def pages(cursor_fn, group_fn, page_opts, base_filters, data_filters, count_filters) do
    Bonfire.GraphQL.Pagination.pages(
      Queries,
      Observation,
      cursor_fn,
      group_fn,
      page_opts,
      base_filters,
      data_filters,
      count_filters
    )
  end

  def preload_all(%Observation{} = event) do
    {:ok, event} = one(id: event.id, preload: :all)
    preload_action(event)
  end

  def preload_action(event) do
    event |> Map.put(:action, ValueFlows.Knowledge.Action.Actions.action!(event.action_id))
  end

  # processes is actually only one, so we can use [process | resources]
  def track(event) do
    with {:ok, resources} <- track_resource_output(event),
         {:ok, to_resource} <- track_to_resource_output(event),
         {:ok, process} <- track_process_input(event) do
      {
        :ok,
        resources
        |> maybe_append(process)
        |> maybe_append(to_resource)
      }
    end
  end

  defp track_to_resource_output(
         %{action_id: action_id, to_resource_inventoried_as_id: to_resource_inventoried_as_id} =
           _event
       )
       when action_id in ["transfer", "move"] and not is_nil(to_resource_inventoried_as_id) do
    EconomicResources.one([:default, id: to_resource_inventoried_as_id])
  end

  defp track_to_resource_output(_) do
    {:ok, nil}
  end

  defp track_resource_output(%{output_of_id: output_of_id}) when not is_nil(output_of_id) do
    EconomicResources.many([:default, join: [event_output: output_of_id]])
  end

  defp track_resource_output(_) do
    {:ok, []}
  end

  defp track_process_input(%{input_of_id: input_of_id}) when not is_nil(input_of_id) do
    Processes.one([:default, id: input_of_id])
  end

  defp track_process_input(_) do
    {:ok, nil}
  end

  def trace(event) do
    with {:ok, resource_inventoried_as} <- trace_resource_inventoried_as(event),
         {:ok, process} <- trace_process_output(event),
         {:ok, resources} <- trace_resource_input(event) do
      {
        :ok,
        resources
        |> maybe_append(resource_inventoried_as)
        |> maybe_append(process)
      }
    end
  end

  defp trace_resource_inventoried_as(
         %{action_id: action_id, resource_inventoried_as_id: resource_inventoried_as_id} = _event
       )
       when action_id in ["transfer", "move"] and not is_nil(resource_inventoried_as_id) do
    EconomicResources.one([:default, id: resource_inventoried_as_id])
  end

  defp trace_resource_inventoried_as(_) do
    {:ok, nil}
  end

  defp trace_process_output(%{output_of_id: output_of_id}) when not is_nil(output_of_id) do
    Processes.one([:default, id: output_of_id])
  end

  defp trace_process_output(_) do
    {:ok, nil}
  end

  defp trace_resource_input(%{input_of_id: input_of_id}) when not is_nil(input_of_id) do
    # with {:ok, events} <- many([:default, input_of_id: input_of_id]),
    #      resource_ids = Enum.map(events, & &1.resource_inventoried_as_id) do
    #   EconomicResources.many([:default, id: resource_ids])
    # end

    EconomicResources.many([:default, [join: [event_input: input_of_id]]])
  end

  defp trace_resource_input(_) do
    {:ok, []}
  end

  ## mutations

  def create(
        _creator,
        %{
          resource_inventoried_as: from_existing_resource,
          to_resource_inventoried_as: to_existing_resource
        },
        %{
          new_inventoried_resource: _new_inventoried_resource
        }
      )
      when not is_nil(from_existing_resource) and not is_nil(to_existing_resource) do
    {:error, "Oops, you cannot act on three resources in one event."}
  end

  def create(
        creator,
        %{
          to_resource_inventoried_as: to_existing_resource
        } = event_attrs,
        %{
          new_inventoried_resource: new_inventoried_resource
        }
      )
      when not is_nil(to_existing_resource) do
    Logger.info("create a new FROM resource to go with an existing TO resource")

    new_resource_attrs =
      new_inventoried_resource
      |> Map.put_new(:primary_accountable, Map.get(event_attrs, :provider, creator))

    create_resource_and_event(
      creator,
      event_attrs,
      new_resource_attrs,
      :resource_inventoried_as
    )
  end

  def create(
        creator,
        %{
          resource_inventoried_as: from_existing_resource
        } = event_attrs,
        %{
          new_inventoried_resource: new_inventoried_resource
        }
      )
      when not is_nil(from_existing_resource) do
    Logger.info("creates a new TO resource to go with an existing FROM resource")

    new_resource_attrs =
      new_inventoried_resource
      |> Map.put_new(:primary_accountable, Map.get(event_attrs, :receiver, creator))

    create_resource_and_event(
      creator,
      event_attrs,
      new_resource_attrs,
      :to_resource_inventoried_as
    )
  end

  def create(creator, event_attrs, %{
        new_inventoried_resource: new_inventoried_resource
      }) do
    Logger.info("creates only a new resource")

    new_resource_attrs =
      new_inventoried_resource
      |> Map.put_new(:primary_accountable, Map.get(event_attrs, :provider, creator))

    create_resource_and_event(
      creator,
      event_attrs,
      new_resource_attrs,
      :resource_inventoried_as
    )
  end

  def create(creator, event_attrs, _) do
    with {:ok, event} <- create(creator, event_attrs) do
      {:ok, event, nil}
    end
  end

  @doc """
  Create an Event (with preexisting resources)
  """
  def create(%{} = creator, event_attrs) do
    new_event_attrs =
      event_attrs
      # fallback if none indicated
      |> Map.put_new(:provider, creator)
      |> Map.put_new(:receiver, creator)
      |> prepare_attrs()

    cs = Observation.create_changeset(creator, new_event_attrs)

    # IO.inspect(creator: creator)
    # IO.inspect(new_event_attrs: new_event_attrs)

    repo().transact_with(fn ->
      with :ok <- validate_user_involvement(creator, new_event_attrs),
           :ok <- validate_provider_is_primary_accountable(new_event_attrs),
           :ok <- validate_receiver_is_primary_accountable(new_event_attrs),
           {:ok, event} <- repo().insert(cs |> Observation.create_changeset_validate()),
           {:ok, event} <- ValueFlows.Util.try_tag_thing(creator, event, new_event_attrs),
           event = preload_all(event),
           {:ok, event} <- maybe_transfer_resource(event),
           {:ok, event} <- EventSideEffects.event_side_effects(event),
           act_attrs = %{verb: "created", is_local: true},
           # FIXME
           {:ok, activity} <- ValueFlows.Util.activity_create(creator, event, act_attrs),
           :ok <- ValueFlows.Util.publish(creator, event, activity, :created) do
        indexing_object_format(event) |> ValueFlows.Util.index_for_search()
        {:ok, event}
      end
    end)
  end

  defp create_resource_and_event(creator, event_attrs, new_inventoried_resource, field_name) do
    new_resource_attrs =
      new_inventoried_resource
      |> Map.put_new(:is_public, true)

    with {:ok, new_resource} <-
           ValueFlows.Observe.EconomicResource.EconomicResources.create(
             creator,
             new_resource_attrs
           ) do
      event_attrs = Map.merge(event_attrs, %{field_name => new_resource.id})

      with {:ok, event} <- create(creator, event_attrs) do
        {:ok, event, new_resource}
      else
        e ->
          # TODO: maybe we need to delete the created resource?
          e
      end
    end
  end

  # TODO: take the user who is performing the update
  # @spec update(%Observation{}, attrs :: map) :: {:ok, Observation.t()} | {:error, Changeset.t()}
  def update(user, %Observation{} = event, attrs) do
    repo().transact_with(fn ->
      event = preload_all(event)
      attrs = prepare_attrs(attrs)

      with :ok <- validate_user_involvement(user, event),
           {:ok, event} <- repo().update(Observation.update_changeset(event, attrs)),
           {:ok, event} <- maybe_transfer_resource(event),
           {:ok, event} <- ValueFlows.Util.try_tag_thing(nil, event, attrs),
           :ok <- ValueFlows.Util.publish(event, :updated) do
        {:ok, event}
      end
    end)
  end

  defp maybe_transfer_resource(
         %Observation{
           to_resource_inventoried_as_id: to_resource_id,
           provider_id: provider_id,
           receiver_id: receiver_id,
           action_id: action_id
         } = event
       )
       when action_id in ["transfer", "transfer-all-rights"] and not is_nil(to_resource_id) and
              not is_nil(provider_id) and not is_nil(receiver_id) and
              provider_id != receiver_id do
    with {:ok, to_resource} <- EconomicResources.one([:default, id: to_resource_id]),
         :ok <- validate_provider_is_primary_accountable(event),
         {:ok, to_resource} <-
           EconomicResources.update(to_resource, %{primary_accountable: receiver_id}) do
      {:ok, %{event | to_resource_inventoried_as: to_resource}}
    end
  end

  defp maybe_transfer_resource(event) do
    {:ok, event}
  end

  defp validate_user_involvement(
         %{id: creator_id},
         %{provider_id: provider_id, receiver_id: receiver_id} = _event
       )
       when provider_id == creator_id or receiver_id == creator_id do
    # TODO add more complex rules once we have agent roles/relationships
    :ok
  end

  defp validate_user_involvement(
         %{id: creator_id},
         %{provider: provider, receiver: receiver} = _event
       )
       when (is_binary(provider) and is_binary(receiver) and provider == creator_id) or
              receiver == creator_id do
    :ok
  end

  defp validate_user_involvement(
         creator,
         %{provider: provider, receiver: receiver} = _event
       )
       when provider == creator or
              receiver == creator do
    :ok
  end

  defp validate_user_involvement(_creator, _event) do
   {:error, error(403, "You cannot do this if you are not receiver or provider.")}
  end

  defp validate_provider_is_primary_accountable(
         %{resource_inventoried_as_id: resource_id, provider_id: provider_id} = _event
       )
       when not is_nil(resource_id) and not is_nil(provider_id) do
    with {:ok, resource} <- EconomicResources.one([:default, id: resource_id]) do
      validate_provider_is_primary_accountable(%{
        resource_inventoried_as: resource,
        provider_id: provider_id
      })
    end
  end

  defp validate_provider_is_primary_accountable(
         %{resource_inventoried_as: resource, provider_id: provider_id} = _event
       )
       when is_struct(resource) and not is_nil(provider_id) do
    if is_nil(resource.primary_accountable_id) or provider_id == resource.primary_accountable_id do
      :ok
    else
      {:error, error(403, "You cannot do this since the provider is not accountable for the resource.")}
    end
  end

  defp validate_provider_is_primary_accountable(_event) do
    :ok
  end

  defp validate_receiver_is_primary_accountable(
         %{to_resource_inventoried_as_id: resource_id, receiver_id: receiver_id} = _event
       )
       when not is_nil(resource_id) do
    with {:ok, resource} <- EconomicResources.one([:default, id: resource_id]) do
      if is_nil(resource.primary_accountable_id) or
           receiver_id == resource.primary_accountable_id do
        :ok
      else
        {:error, error(403, "You cannot do this since the receiver is not accountable for the target resource.")}
      end
    end
  end

  defp validate_receiver_is_primary_accountable(_event) do
    :ok
  end

  defp prepare_attrs(attrs) do
    attrs
    |> maybe_put(:action_id, attr_get_id(attrs, :action))
    |> maybe_put(
      :context_id,
      attrs |> Map.get(:in_scope_of) |> maybe(&List.first/1)
    )
    |> maybe_put(:provider_id, attr_get_id(attrs, :provider))
    |> maybe_put(:receiver_id, attr_get_id(attrs, :receiver))
    |> maybe_put(:input_of_id, attr_get_id(attrs, :observed_during))
    |> maybe_put(:output_of_id, attr_get_id(attrs, :output_of))
    |> maybe_put(:resource_conforms_to_id, attr_get_id(attrs, :resource_conforms_to))
    |> maybe_put(:resource_inventoried_as_id, attr_get_id(attrs, :resource_inventoried_as))
    |> maybe_put(:to_resource_inventoried_as_id, attr_get_id(attrs, :to_resource_inventoried_as))
    |> maybe_put(:triggered_by_id, attr_get_id(attrs, :triggered_by))
    |> maybe_put(:at_location_id, attr_get_id(attrs, :at_location))
    |> parse_observable_phenomenonment_attrs()
  end

  defp parse_observable_phenomenonment_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn {k, v}, acc ->
      if is_map(v) and Map.has_key?(v, :has_observation) do
        v = map_key_replace(v, :has_observation, :unit_id)
        # I have no idea why the numerical value isn't auto converted
        Map.put(acc, k, v)
      else
        Map.put(acc, k, v)
      end
    end)
  end

  def soft_delete(%Observation{} = event) do
    repo().transact_with(fn ->
      with {:ok, event} <- Bonfire.Repo.Delete.soft_delete(event),
           :ok <- ValueFlows.Util.publish(event, :deleted) do
        {:ok, event}
      end
    end)
  end

  def indexing_object_format(obj) do
    %{
      "index_type" => "Observation",
      "id" => obj.id,
      # "canonicalUrl" => obj.character.canonical_url,
      # "icon" => icon,
      "summary" => Map.get(obj, :note),
      "published_at" => obj.published_at,
      "creator" => ValueFlows.Util.indexing_format_creator(obj)
      # "index_instance" => URI.parse(obj.character.canonical_url).host, # home instance of object
    }
  end


end
