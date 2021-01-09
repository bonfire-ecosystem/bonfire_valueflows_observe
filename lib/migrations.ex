defmodule ValueFlows.Observe.Migrations do
  use Ecto.Migration
  # alias Pointers.ULID
  import Pointers.Migration

  alias ValueFlows.Knowledge.ResourceSpecification
  alias ValueFlows.Observe.Observation
  alias ValueFlows.Observe.EconomicResource
  alias ValueFlows.Observe.Process

  # defp event_table(), do: Observation.__schema__(:source)

  def up do
    create_pointable_table(ValueFlows.Observe.Observation) do
      # add(:name, :string)
      add(:note, :text)

      # add(:image_id, weak_pointer(ValueFlows.Util.image_schema()), null: true)

      add(:action_id, :string)

      add(:input_of_id, weak_pointer(Process), null: true)
      add(:output_of_id, weak_pointer(Process), null: true)

      add(:provider_id, weak_pointer(), null: true)
      add(:receiver_id, weak_pointer(), null: true)

      add(:resource_inventoried_as_id, weak_pointer(EconomicResource), null: true)
      add(:to_resource_inventoried_as_id, weak_pointer(EconomicResource), null: true)

      # add(:resource_classified_as, {:array, :string}, virtual: true)

      add(:resource_conforms_to_id, weak_pointer(ResourceSpecification), null: true)

      add(:resource_quantity_id, weak_pointer(Bonfire.Quantify.ObservablePhenomenon), null: true)
      add(:effort_quantity_id, weak_pointer(Bonfire.Quantify.ObservablePhenomenon), null: true)

      add(:has_beginning, :timestamptz)
      add(:has_end, :timestamptz)
      add(:result_time, :timestamptz)

      # optional context as in_scope_of
      add(:context_id, weak_pointer(), null: true)

      # TODO: use string or link to Agreement?
      add(:agreed_in, :string)
      # belongs_to(:agreed_in, Agreement)

      add(:at_location_id, weak_pointer(Bonfire.Geolocate.Geolocation), null: true)

      add(:triggered_by_id, weak_pointer(Observation), null: true)

      add(:creator_id, weak_pointer(ValueFlows.Util.user_schema()), null: true)

      add(:published_at, :timestamptz)
      add(:deleted_at, :timestamptz)
      add(:disabled_at, :timestamptz)

      timestamps(inserted_at: false, type: :utc_datetime_usec)
    end
  end

  def down do
    drop_pointable_table(ValueFlows.Observe.Observation)
  end
end
