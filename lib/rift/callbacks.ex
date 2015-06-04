defmodule Rift.Callbacks do
  @moduledoc ~S"""
  Callback implementation for structs.

  Presently, you may define `after_to_elixir` and `after_to_erlang`. after_to_elixir
  is called after a tuple is converted to an Elixir struct and after_to_erlang is called
  when an Elixir struct is turned into a tuple.
  """

  defmodule Callback do
    defstruct name: nil, guard: nil, body: nil

    def new(name, guard, body) do
      %Callback{name: name, guard: guard, body: body}
    end
  end

  defmacro __using__(_opts) do
    Module.register_attribute(__CALLER__.module, :callbacks, accumulate: true)
    quote do
      require Rift.Callbacks
      import Rift.Callbacks, only: [callback: 3]
    end
  end

  defmacro callback(callback_name, opts, do: body) do
    callback = Callback.new(callback_name, opts, body)
    Module.put_attribute(__CALLER__.module, :callbacks, callback)
  end

  def reconstitute(module) do
    module
    |> Module.get_attribute(:callbacks)
    |> Enum.map(&reconstitute_callback/1)
  end

  defp reconstitute_callback(callback=%Rift.Callbacks.Callback{}) do
    quote do
      callback(unquote(callback.name), unquote(callback.guard)) do
        unquote(callback.body)
      end
    end
  end

  def default_to_elixir do
    quote do
      def to_elixir(to_convert, :string) when is_bitstring(to_convert) do
        to_convert
      end

      def to_elixir(to_convert, :string) when is_list(to_convert) do
        List.to_string(to_convert)
      end

      def to_elixir(to_convert, {:map, {key_type, val_type}}) when is_tuple(to_convert) do
        to_convert
        |> :dict.to_list
        |> Enum.into(HashDict.new,
                     fn({k, v}) ->
                       {to_elixir(k, key_type),
                        to_elixir(v, val_type)}
                     end)
      end

      def to_elixir(to_convert, {:set, item_type}) when is_tuple(to_convert) do
        to_convert
        |> :sets.to_list
        |> Enum.into(HashSet.new, &(to_elixir(&1, item_type)))
      end

      def to_elixir(to_convert, {:list, item_type}) when is_list(to_convert) do
        to_convert
        |> Enum.map(&(to_elixir(&1, item_type)))
      end

      def to_elixir(to_convert, type) when is_tuple(to_convert) do
        to_convert
        |> Tuple.to_list
        |> Enum.map(&(to_elixir(&1, type)))
        |> List.to_tuple
      end

      def to_elixir(to_convert, _type) do
        to_convert
      end
    end
  end

  def default_to_erlang do
    quote do
      def to_erlang(bitstring, :string) when is_bitstring(bitstring) do
        String.to_char_list(bitstring)
      end

      def to_erlang(elixir_list, {:list, item_type}) when is_list(elixir_list) do
        elixir_list
        |> Enum.map(&(to_erlang(&1, item_type)))
      end

      def to_erlang(elixir_dict=%HashDict{}, {:map, {key_type, val_type}}) do
        elixir_dict
        |> Enum.map(
            fn({k, v}) ->
              {to_erlang(k, key_type),
               to_erlang(v, val_type)}
            end)
        |> :dict.from_list
      end

      def to_erlang(elixir_set=%HashSet{}, {:set, item_type}) do
        elixir_set
        |> Enum.map(&(to_erlang(&1, item_type)))
        |> :sets.from_list
      end

      def to_erlang(to_convert, _type) do
        to_convert
      end

    end
  end

  def build(module, _filter \\ fn(_callback) -> true end) do
    defined_callbacks = module
    |> Module.get_attribute(:callbacks)
    |> Enum.map(fn(callback) ->
                  build_internal(callback.name, callback) end)

    quote do
      unquote_splicing(defined_callbacks)
      defp after_to_elixir(x) do
        x
      end

      defp after_to_erlang(x) do
        x
      end
    end
  end

  defp build_internal(:after_to_elixir, callback=%Callback{}) do
    quote do
      defp after_to_elixir(unquote(callback.guard)) do
        unquote(callback.body)
      end
    end
  end

  defp build_internal(:after_to_erlang, callback=%Callback{}) do
    quote do
      defp after_to_erlang(unquote(callback.guard)) do
        unquote(callback.body)
      end
    end
  end

  defp build_internal(unknown, _) do
    raise "Warning: undefined callback #{unknown}"
  end

end
