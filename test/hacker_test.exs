defmodule HackerTest do
  use ExUnit.Case, async: false

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
      for _ <- 1..3 do
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.connect(~c"localhost", 5002, mode: :binary, active: false)
          assert :gen_tcp.send(socket, "foo") == :ok
          assert :gen_tcp.shutdown(socket, :write)
          {:ok, return} = :gen_tcp.recv(socket, 0, 5000)
          assert return == "foo"
        end)
      end

    for task <- tasks do
      Task.await(task)
    end
  end
end
