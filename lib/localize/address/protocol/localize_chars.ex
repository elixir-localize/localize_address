defimpl Localize.Chars, for: Localize.Address.Address do
  @moduledoc false

  def to_string(value), do: Localize.Address.to_string(value, [])
  def to_string(value, options), do: Localize.Address.to_string(value, options)
end
