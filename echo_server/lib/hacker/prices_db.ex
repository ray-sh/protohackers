defmodule Hacker.PricesDb do
  def new do
    []
  end

  def add(db, ts, price) when is_integer(ts) and is_integer(price) and is_list(db) do
    [{ts, price} | db]
  end

  def query(db, from, to) when is_integer(from) and is_integer(to) and is_list(db) do
    Stream.filter(db, fn {ts, _} ->
      ts >= from and ts <= to
    end)
    |> Enum.reduce({0, 0}, fn {_, price}, {sum, account} ->
      {sum + price, account + 1}
    end)
    |> then(fn
      {_sum, 0} -> 0
      {sum, account} -> div(sum, account)
    end)
  end
end
