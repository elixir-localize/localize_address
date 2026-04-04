defmodule Localize.Address.Address do
  @moduledoc """
  Represents a parsed or constructed postal address.

  The struct contains canonical address component fields that map to
  both libpostal parser output labels and OpenCageData address-formatting
  template variables. Fields that are not applicable for a given address
  are `nil`.

  """

  @type t :: %__MODULE__{
          attention: String.t() | nil,
          house: String.t() | nil,
          house_number: String.t() | nil,
          road: String.t() | nil,
          neighbourhood: String.t() | nil,
          city: String.t() | nil,
          municipality: String.t() | nil,
          county: String.t() | nil,
          state_district: String.t() | nil,
          state: String.t() | nil,
          postcode: String.t() | nil,
          territory: String.t() | nil,
          territory_code: String.t() | nil,
          island: String.t() | nil,
          archipelago: String.t() | nil,
          continent: String.t() | nil,
          raw_input: String.t() | nil
        }

  defstruct [
    :attention,
    :house,
    :house_number,
    :road,
    :neighbourhood,
    :city,
    :municipality,
    :county,
    :state_district,
    :state,
    :postcode,
    :territory,
    :territory_code,
    :island,
    :archipelago,
    :continent,
    :raw_input
  ]
end
