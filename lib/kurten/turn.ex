defmodule Kurten.Turn do


  @module_doc """
  possible states for a turn
  1. pending. player can still choose another card
  2. lost
  3. won
"""
  defstruct [:player, :bet, state: :pending, cards: []]

  def calc_state(cards) do
    values = Enum.map(cards, fn card -> card.attributes.values end)
    sums = calc_sums(values)
    cond do
      21 in sums -> :won
      rosier?(cards) -> :won
      Enum.all?(sums, &(&1 > 21)) -> :lost
      true -> :pending
    end
  end

  defp rosier?(cards) do
    length(cards) == 2 and Enum.all?(cards, fn card -> Enum.any?(card.attributes, fn {k, v} -> v == "rosier" end) end)
  end

 @doc "calculate all possible sums of cards, since a card can have more than one value"
  def calc_sums(cards) do
    Enum.reduce(cards, fn x, acc ->
      get_combinations(x, acc)
      |> List.flatten
    end)
  end

  @doc "gets the all the combinations of 2 lists"
  def get_combinations(sums_a, sums_b) do
    for a <- sums_a do
      for b <- sums_b do
        a + b
      end
    end
  end

end
