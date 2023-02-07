defmodule HackerTest do
  use ExUnit.Case, async: false
  alias Hacker.PricesDb, as: DB

  def read_till_close(socket, bs \\ []) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, packet} -> read_till_close(socket, [bs, packet])
      {:error, :closed} -> {:ok, :erlang.list_to_binary(bs)}
    end
  end

  test "client could send msg" do
    send = :binary.copy("a", 1024 * 100)
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 5002, mode: :binary, active: false)
    assert :gen_tcp.send(socket, send) == :ok
    assert :gen_tcp.shutdown(socket, :write)
    {:ok, return} = read_till_close(socket)
    assert byte_size(return) == byte_size(send)
  end

  test "client send msg out of buffer" do
    send = :binary.copy("a", 1024 * 100 + 1)
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 5002, mode: :binary, active: false)
    assert :gen_tcp.send(socket, send) == :ok
    assert :gen_tcp.shutdown(socket, :write)
    {:ok, return} = read_till_close(socket)
    assert byte_size(return) == 0
  end

  test "multiple clients could send/rec msg" do
    tasks =
      for i <- 1..30 do
        Task.async(fn ->
          {:ok, socket} =
            :gen_tcp.connect(~c"localhost", 5002, [mode: :binary, active: false], 15000)

          assert :gen_tcp.send(socket, "foo") == :ok
          assert :gen_tcp.shutdown(socket, :write)
          {:ok, return} = :gen_tcp.recv(socket, 0)
          assert return == "foo"
        end)
      end

    Task.await_many(tasks)
  end

  test "prime " do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 5002, mode: :binary, active: false)
    :gen_tcp.send(socket, Jason.encode!(%{method: "isPrime", number: 7}) <> "\n")

    assert {:ok, data} = :gen_tcp.recv(socket, 0, 5002)
    assert String.ends_with?(data, "\n")
    assert Jason.decode!(data) == %{"method" => "isPrime", "prime" => true}

    :gen_tcp.send(socket, Jason.encode!(%{method: "isPrime", number: 6}) <> "\n")

    assert {:ok, data} = :gen_tcp.recv(socket, 0, 5002)
    assert String.ends_with?(data, "\n")
    assert Jason.decode!(data) == %{"method" => "isPrime", "prime" => false}
  end

  test "adding elements and getting the average" do
    db = DB.new()

    assert DB.query(db, 0, 100) == 0

    db =
      db
      |> DB.add(1, 10)
      |> DB.add(2, 20)
      |> DB.add(3, 30)

    assert DB.query(db, 0, 100) == 20
    assert DB.query(db, 0, 2) == 15
    assert DB.query(db, 2, 3) == 25
    assert DB.query(db, 4, 100) == 0
  end

  test "handles queries" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 5002, mode: :binary, active: false)

    :ok = :gen_tcp.send(socket, <<?I, 1000::32, 1::32-signed-big>>)
    :ok = :gen_tcp.send(socket, <<?I, 2000::32-signed-big, 2::32-signed-big>>)
    :ok = :gen_tcp.send(socket, <<?I, 3000::32-signed-big, 3::32-signed-big>>)

    :ok = :gen_tcp.send(socket, <<?Q, 1000::32-signed-big, 3000::32-signed-big>>)
    assert {:ok, <<2::32-signed-big>>} = :gen_tcp.recv(socket, 0)
  end

  test "handles clients separately" do
    {:ok, socket1} = :gen_tcp.connect(~c"localhost", 5002, mode: :binary, active: false)
    {:ok, socket2} = :gen_tcp.connect(~c"localhost", 5002, mode: :binary, active: false)

    :ok = :gen_tcp.send(socket1, <<?I, 1000::32-signed-big, 1::32-signed-big>>)
    :ok = :gen_tcp.send(socket2, <<?I, 2000::32-signed-big, 2::32-signed-big>>)

    :ok = :gen_tcp.send(socket1, <<?Q, 1000::32-signed-big, 3000::32-signed-big>>)
    assert {:ok, <<1::32-signed-big>>} = :gen_tcp.recv(socket1, 4, 10_000)

    :ok = :gen_tcp.send(socket2, <<?Q, 1000::32-signed-big, 3000::32-signed-big>>)
    assert {:ok, <<2::32-signed-big>>} = :gen_tcp.recv(socket2, 4, 10_000)
  end
end
