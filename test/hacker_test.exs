defmodule HackerTest do
  use ExUnit.Case, async: false

  test "client could send msg" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 5002, mode: :binary, active: false)
    assert :gen_tcp.send(socket, "foo") == :ok
    assert :gen_tcp.shutdown(socket, :write)
    {:ok, return} = :gen_tcp.recv(socket, 0, 5000)
    assert return == "foo"
  end
end
