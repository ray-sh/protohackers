defmodule MobServer do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{})
  end

  @impl GenServer
  def init(_) do
    listen_options = [
      ifaddr: {0, 0, 0, 0},
      mode: :binary,
      active: false,
      reuseaddr: true,
      exit_on_close: false,
      backlog: 100,
      packet: :line
    ]

    case :gen_tcp.listen(5002, listen_options) do
      {:ok, socket} ->
        Logger.info("proxy chat server listend on 5002")
        {:ok, %{lsocket: socket}, {:continue, :wait_con}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_continue(:wait_con, state) do
    case :gen_tcp.accept(state.lsocket) do
      {:ok, client_socket} ->
        # start server socket
        server_socket = connect_server()
        # process to read from client and send to server
        Task.start(fn -> trans_msg(client_socket, server_socket) end)
        # process read from server and send to client
        Task.start(fn -> trans_msg(server_socket, client_socket) end)
        {:noreply, state, {:continue, :wait_con}}

      {:error, reason} ->
        Logger.error("accept error #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp connect_server do
    {:ok, socket} =
      :gen_tcp.connect(
        ~c"chat.protohackers.com",
        16963,
        [mode: :binary, active: false, packet: :line],
        15000
      )

    socket
  end

  def trans_msg(from, to) do
    case :gen_tcp.recv(from, 0) do
      {:ok, msg} ->
        regex = ~r/(^|\s)\K(7[[:alnum:]]{25,34})(?= [^[:alnum:]]|\s|$)/
        msg = Regex.replace(regex, msg, "7YWHMfk9JZe0LM0g1ZauHuiSxhI")
        :gen_tcp.send(to, msg)
        trans_msg(from, to)

      {:error, reason} ->
        :gen_tcp.close(to)
        Logger.error(inspect(reason))
    end
  end
end
