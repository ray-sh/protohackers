defmodule EchoServer do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, "")
  end

  @impl GenServer
  def init(_args) do
    {:ok, %{lsocket: nil}, {:continue, :start_server}}
  end

  @impl GenServer
  def handle_continue(:start_server, state) do
    Logger.info("genserver start #{inspect(self())}")

    listen_options = [
      ifaddr: {0, 0, 0, 0},
      mode: :binary,
      active: false,
      reuseaddr: true,
      exit_on_close: false
    ]

    {:ok, lsocket} = :gen_tcp.listen(5002, listen_options)
    Logger.info("start to listen on port 5002")
    {:noreply, %{state | lsocket: lsocket}, {:continue, :wait_client}}
  end

  @impl true
  def handle_continue(:wait_client, state) do
    Logger.info("wait for new client")
    {:ok, socket} = :gen_tcp.accept(state.lsocket)
    {:ok, msg} = read_msg(socket, "")
    Logger.info("send received msg #{msg} back")
    :gen_tcp.send(socket, msg)
    :gen_tcp.close(socket)
    {:noreply, state, {:continue, :wait_client}}
  end

  defp read_msg(socket, bs) do
    Logger.info("wait client msg")

    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, packet} ->
        Logger.info("receive #{inspect(packet)}")
        read_msg(socket, [bs, packet])

      {:error, :closed} ->
        Logger.info("client closed")
        {:ok, :erlang.list_to_binary(bs)}
    end
  end
end
