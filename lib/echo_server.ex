defmodule EchoServer do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, "")
  end

  @impl GenServer
  def init(_args) do
    listen_options = [
      ifaddr: {0, 0, 0, 0},
      mode: :binary,
      active: false,
      reuseaddr: true,
      exit_on_close: false
    ]

    case :gen_tcp.listen(5002, listen_options) do
      {:ok, lsocket} ->
        {:ok, %{lsocket: lsocket}, {:continue, :wait_connect}}

      {:error, error} ->
        Logger.error("can't listen on the port #{inspect(error)}")
        {:stop, error}
    end
  end

  @impl true
  def handle_continue(:wait_connect, state) do
    case :gen_tcp.accept(state.lsocket) do
      {:ok, socket} ->
        {:ok, msg} = read_msg(socket, "")
        Logger.info("send received msg #{msg} back")
        :gen_tcp.send(socket, msg)
        :gen_tcp.close(socket)

      {:error, error} ->
        Logger.error("accept error #{inspect(error)}")
    end

    {:noreply, state, {:continue, :wait_connect}}
  end

  defp read_msg(socket, bs) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, packet} ->
        read_msg(socket, [bs, packet])

      {:error, :closed} ->
        Logger.info("client closed")
        {:ok, bs}
    end
  end
end
