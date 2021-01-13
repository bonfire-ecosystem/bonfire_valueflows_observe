# # SPDX-License-Identifier: AGPL-3.0-only
defmodule ValueFlows.Observe.Test.Faking do
  @moduledoc false

  import ValueFlows.Observe.Simulate

  # import ExUnit.Assertions
  import Bonfire.GraphQL.Test.GraphQLAssertions
  import Bonfire.GraphQL.Test.GraphQLFields
  # import CommonsPub.Utils.Trendy

  import Grumble

  alias ValueFlows.Observe.{ObservablePhenomenon, Observation}
  alias ValueFlows.Observe.Observations

  ## Observation

  ### Graphql fields

  def observation_subquery(options \\ []) do
    gen_subquery(:id, :observation, &observation_fields/1, options)
  end

  def observation_query(options \\ []) do
    options = Keyword.put_new(options, :id_type, :id)
    gen_query(:id, &observation_subquery/1, options)
  end

  def observation_fields(extra \\ []) do
    extra ++ ~w(id note)a
  end


  def observations_query(options \\ []) do
    params =
      [
        after: list_type(:cursor),
        before: list_type(:cursor),
        limit: :int
      ] ++ Keyword.get(options, :params, [])

    gen_query(&observations_subquery/1, [{:params, params} | options])
  end

  def observations_subquery(options \\ []) do
    args = [
      after: var(:after),
      before: var(:before),
      limit: var(:limit)
    ]

    page_subquery(
      :observations_pages,
      &observation_fields/1,
      [{:args, args} | options]
    )
  end

  def create_observation_mutation(options \\ []) do
    [observation: type!(:observation_create_params)]
    |> gen_mutation(&create_observation_submutation/1, options)
  end

  def create_observation_submutation(options \\ []) do
    [observation: var(:observation)]
    |> gen_submutation(:create_observation, &observation_fields/1, options)
  end

  def update_observation_mutation(options \\ []) do
    [observation: type!(:observation_update_params)]
    |> gen_mutation(&update_observation_submutation/1, options)
  end

  def update_observation_submutation(options \\ []) do
    [observation: var(:observation)]
    |> gen_submutation(:update_observation, &observation_fields/1, options)
  end

  def delete_observation_mutation(options \\ []) do
    [id: type!(:id)]
    |> gen_mutation(&delete_observation_submutation/1, options)
  end

  def delete_observation_submutation(_options \\ []) do
    field(:delete_observation, args: [id: var(:id)])
  end

  ### Observation assertion

  def assert_observation(observation) do
    assert_object(observation, :assert_observation,
      [id: &assert_ulid/1],
      [note: &assert_binary/1]
      # has_result_id: &assert_ulid/1
    )
  end

  def assert_observation(%Observation{} = observation, %{id: _} = obs2) do
    assert_observations_eq(observation, obs2)
  end

  def assert_observation(%Observation{} = observation, %{} = obs2) do
    assert_observations_eq(observation, assert_observation(obs2))
  end

  def assert_observations_eq(%Observation{} = observation, %{} = obs2) do
    assert_maps_eq(observation, obs2, :assert_observation, [:id, :note])
    obs2
  end

  ## Measures

  def observable_phenomenon_fields(extra \\ []) do
    extra ++ ~w(id has_numerical_value)a
  end

  @doc """
  Same as `observable_phenomenon_fields/1`, but with the parameter being nested inside of
  another type.
  """
  def observable_phenomenon_response_fields(extra \\ []) do
    [observable_phenomenon: observable_phenomenon_fields(extra)]
  end

  def observable_phenomenon_subquery(options \\ []) do
    gen_subquery(:id, :observable_phenomenon, &observable_phenomenon_fields/1, options)
  end

  def observable_phenomenon_query(options \\ []) do
    options = Keyword.put_new(options, :id_type, :id)
    gen_query(:id, &observable_phenomenon_subquery/1, options)
  end

  def observable_phenomenons_pages_query(options \\ []) do
    params =
      [
        after: list_type(:cursor),
        before: list_type(:cursor),
        limit: :int
      ] ++ Keyword.get(options, :params, [])

    gen_query(&observable_phenomenons_pages_subquery/1, [{:params, params} | options])
  end

  def observable_phenomenons_pages_subquery(options \\ []) do
    args = [
      after: var(:after),
      before: var(:before),
      limit: var(:limit)
    ]

    page_subquery(
      :observable_phenomenons_pages,
      &observable_phenomenon_fields/1,
      [{:args, args} | options]
    )
  end


  def create_observable_phenomenon_mutation(options \\ []) do
    [observable_phenomenon: type!(:observable_phenomenon_create_params)]
    |> gen_mutation(&create_observable_phenomenon_submutation/1, options)
  end

  def create_observable_phenomenon_submutation(options \\ []) do
    [observable_phenomenon: var(:observable_phenomenon)]
    |> gen_submutation(:create_observable_phenomenon, &observable_phenomenon_response_fields/1, options)
  end

  def create_observable_phenomenon_with_observation_mutation(options \\ []) do
    [observable_phenomenon: type!(:observable_phenomenon_create_params), has_observation: type!(:id)]
    |> gen_mutation(&create_observable_phenomenon_with_observation_submutation/1, options)
  end

  def create_observable_phenomenon_with_observation_submutation(options \\ []) do
    [observable_phenomenon: var(:observable_phenomenon), has_observation: var(:has_observation)]
    |> gen_submutation(:create_observable_phenomenon, &observable_phenomenon_response_fields/1, options)
  end

  def update_observable_phenomenon_mutation(options \\ []) do
    [observable_phenomenon: type!(:observable_phenomenon_update_params)]
    |> gen_mutation(&update_observable_phenomenon_submutation/1, options)
  end

  def update_observable_phenomenon_submutation(options \\ []) do
    [observable_phenomenon: var(:observable_phenomenon)]
    |> gen_submutation(:update_observable_phenomenon, &observable_phenomenon_response_fields/1, options)
  end

  def assert_observable_phenomenon(%ObservablePhenomenon{} = observable_phenomenon) do
    assert_observable_phenomenon(Map.from_struct(observable_phenomenon))
  end

  def assert_observable_phenomenon(observable_phenomenon) do
    assert_object(observable_phenomenon, :assert_observable_phenomenon, has_numerical_value: &assert_float/1)
  end

  def assert_observable_phenomenon(%ObservablePhenomenon{} = observable_phenomenon, %{} = observable_phenomenon2) do
    assert_observable_phenomenons_eq(observable_phenomenon, assert_observable_phenomenon(observable_phenomenon2))
  end

  def assert_observable_phenomenons_eq(%ObservablePhenomenon{} = observable_phenomenon, %{} = observable_phenomenon2) do
    assert_maps_eq(observable_phenomenon, observable_phenomenon2, :assert_observable_phenomenon, [
      :formula_quantifier,
      :published_at,
      :disabled_at
    ])
  end
end
